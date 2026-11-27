# The throwaway-HOME programs (docs/design/nix-dotfiles.md, section 6): `sandbox` runs a shell
# or one command in a fresh HOME filled from this build; `herdr-sandbox` also starts a herdr
# server inside it. Both refuse to run against the real home and clean up on exit.
{
  lib,
  writeShellApplication,
  coreutils,
  gnused,
  cacert,
  zsh,
  tools,
  scripts,
  home-tree,
  oh-my-zsh-bundle,
  summarizer-plugin,
  withHerdr ? false,
}:
let
  name = if withHerdr then "herdr-sandbox" else "sandbox";
  certs = "${cacert}/etc/ssl/certs/ca-bundle.crt";
in
writeShellApplication {
  inherit name;
  # Only for this outer script; the sandboxed program gets the PATH set below.
  runtimeInputs = [
    coreutils
    gnused
  ];
  text = ''
    # ── Arguments ────────────────────────────────────────────────────────────
    herdr_mode=${if withHerdr then "1" else "0"}
    keep=0 with_plugins=0 summarizer=0 attach=1
    usage() {
      if (( herdr_mode )); then
        echo "usage: herdr-sandbox [--keep] [--with-plugins] [--summarizer] [--no-attach] [--] [command...]"
      else
        echo "usage: sandbox [--keep] [--summarizer] [--] [command...]"
      fi
    }
    while (( $# )); do
      case "$1" in
        --keep) keep=1 ;;
        --summarizer) summarizer=1 ;;
        --with-plugins) (( herdr_mode )) || { usage >&2; exit 2; }; with_plugins=1 ;;
        --no-attach) (( herdr_mode )) || { usage >&2; exit 2; }; attach=0 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) break ;;
      esac
      shift
    done

    # ── Guards ───────────────────────────────────────────────────────────────
    canon() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"; }
    # The user database's home, not $HOME; the same call on Linux and macOS.
    passwd_home="$(${tools}/bin/python3 -I -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
    [[ -n "$passwd_home" ]] || { echo "sandbox: could not read this user's home from the user database" >&2; exit 3; }
    caller_home="''${HOME:-}"

    # ── Cleanup ──────────────────────────────────────────────────────────────
    # Until the guards pass, only an empty directory is ever removed (rmdir).
    home="" home_ok=0 server_pid="" tmux_tmpdir=""
    # shellcheck disable=SC2329 # run by the EXIT trap
    cleanup() {
      local rc=$? sock
      if [[ -n "$server_pid" ]]; then
        inenv herdr server stop >/dev/null 2>&1 || true
        for _ in $(seq 1 50); do kill -0 "$server_pid" 2>/dev/null || break; sleep 0.1; done
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
      fi
      if [[ -n "$tmux_tmpdir" ]]; then
        for sock in "$tmux_tmpdir/tmux-$(id -u)"/*; do
          if [[ -S "$sock" ]]; then inenv tmux -S "$sock" kill-server >/dev/null 2>&1 || true; fi
        done
      fi
      if [[ -z "$home" ]]; then :
      elif (( ! home_ok )); then rmdir "$home" 2>/dev/null || true
      elif (( keep )); then echo "sandbox: kept $home" >&2
      elif [[ "$home" == /tmp/dfs.* || "$home" == /private/tmp/dfs.* ]]; then
        # Go's module cache (herdr plugin builds) is read-only.
        chmod -R u+w "$home" 2>/dev/null || true
        rm -rf "$home"
      fi
      exit "$rc"
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    home="$(canon "$(mktemp -d /tmp/dfs.XXXXXX)")"
    # herdr's and tmux's sockets live under it; sun_path is 104 bytes on macOS.
    (( ''${#home} <= 40 )) || { echo "sandbox: HOME path too long for unix sockets: $home" >&2; exit 3; }
    for h in "$passwd_home" "$caller_home"; do
      [[ -z "$h" || "$home" != "$(canon "$h")" ]] || { echo "sandbox: refusing: new HOME $home is the real home" >&2; exit 3; }
    done
    tmux_tmpdir="$home/.tmp"
    [[ "$tmux_tmpdir" == "$home"/* ]] || { echo "sandbox: refusing: TMUX_TMPDIR is outside HOME" >&2; exit 3; }
    home_ok=1

    # ── The throwaway HOME ───────────────────────────────────────────────────
    cp -R ${home-tree}/. "$home/"
    chmod -R u+w "$home"
    mkdir -p "$home/.local/bin" "$home/.local/share/dotfiles" "$tmux_tmpdir" "$home/.run"
    chmod 700 "$tmux_tmpdir" "$home/.run"
    ln -s ${oh-my-zsh-bundle} "$home/.oh-my-zsh"
    for s in herdr-summarize herdr-recent herdr-login-warning herdr-plugins; do
      ln -s "${scripts}/bin/$s" "$home/.local/bin/$s"
    done
    ln -s ${summarizer-plugin} "$home/.local/share/dotfiles/herdr-summarizer-plugin"

    # nixpkgs' zsh sources /etc/set-environment on NixOS, replacing PATH, unless
    # __NIXOS_SET_ENVIRONMENT_DONE is set.
    envv=(
      HOME="$home"
      PATH="${tools}/bin:${scripts}/bin"
      SHELL="${zsh}/bin/zsh"
      TERM=xterm-256color
      LANG=C.UTF-8
      COLORTERM=truecolor
      DOTFILES_SANDBOX=1
      SSL_CERT_FILE="${certs}"
      NIX_SSL_CERT_FILE="${certs}"
      TMUX_TMPDIR="$tmux_tmpdir"
      TMPDIR="$tmux_tmpdir"
      XDG_RUNTIME_DIR="$home/.run"
      __NIXOS_SET_ENVIRONMENT_DONE=1
    )
    (( summarizer )) && envv+=(HERDR_SUMMARIZER_DRY=1)
    inenv() { (cd "$home" && env -i "''${envv[@]}" "$@"); }

    # ── herdr ────────────────────────────────────────────────────────────────
    if (( herdr_mode )); then
      sock="$(inenv herdr status server 2>/dev/null | sed -n 's/^ *socket: //p' | head -1 | tr -s /)"
      [[ -n "$sock" && "$sock" == "$home"/* ]] || { echo "sandbox: refusing: herdr would use socket '$sock', not inside $home" >&2; exit 3; }
      (cd "$home" && exec env -i "''${envv[@]}" herdr server > "$home/.herdr-server.log" 2>&1 < /dev/null) &
      server_pid=$!
      for _ in $(seq 1 600); do inenv herdr workspace list >/dev/null 2>&1 && break; sleep 0.1; done
      inenv herdr workspace list >/dev/null 2>&1 \
        || { echo "sandbox: herdr server did not answer within 60s; log:" >&2; tail -20 "$home/.herdr-server.log" >&2; exit 1; }
      if (( with_plugins )); then
        inenv dotfiles-herdr-plugins-sync || { echo "sandbox: plugin sync failed" >&2; exit 1; }
      fi
      if (( summarizer )); then
        inenv herdr plugin link "$home/.local/share/dotfiles/herdr-summarizer-plugin" >/dev/null \
          || { echo "sandbox: linking the summarizer plugin failed" >&2; exit 1; }
      fi
    fi

    # ── Run ──────────────────────────────────────────────────────────────────
    rc=0
    if (( $# )); then
      inenv "$@" || rc=$?
    elif (( herdr_mode )); then
      (( attach )) && { inenv herdr || rc=$?; }
    else
      inenv "${zsh}/bin/zsh" -i || rc=$?
    fi
    exit "$rc"
  '';
  meta = {
    description =
      if withHerdr then
        "A herdr server and client in a throwaway HOME filled from this build"
      else
        "A shell or command in a throwaway HOME filled from this build";
    platforms = lib.platforms.unix;
    mainProgram = name;
  };
}
