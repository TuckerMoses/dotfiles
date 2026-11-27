# Shared by the build-sandbox checks that run programs: a throwaway HOME filled from this build
# the way the sandbox app (nix/packages/sandbox.nix) fills one, and the same environment.
{ pkgs }:
let
  lib = pkgs.lib;
  d = pkgs.dotfiles;
in
rec {
  # Shell lines that make $HOME a throwaway home under the build directory and export the
  # sandbox app's environment. `path` is extra packages, after the tools and scripts.
  mkHome =
    {
      path ? [ ],
    }:
    ''
      # ── Throwaway HOME ───────────────────────────────────────────────────────
      # Short, under the build directory: herdr's and tmux's unix sockets live under it.
      export HOME="$TMPDIR/h"
      mkdir -p "$HOME"
      cp -R ${d.home-tree}/. "$HOME/"
      chmod -R u+w "$HOME"
      mkdir -p "$HOME/.local/bin" "$HOME/.local/share/dotfiles" "$HOME/.tmp" "$HOME/.run"
      chmod 700 "$HOME/.tmp" "$HOME/.run"
      ln -s ${d.oh-my-zsh-bundle} "$HOME/.oh-my-zsh"
      for s in herdr-summarize herdr-recent herdr-login-warning herdr-plugins; do
        ln -s "${d.scripts}/bin/$s" "$HOME/.local/bin/$s"
      done
      ln -s ${d.summarizer-plugin} "$HOME/.local/share/dotfiles/herdr-summarizer-plugin"

      # ── Environment ──────────────────────────────────────────────────────────
      # As the sandbox app sets it. nixpkgs' zsh sources /etc/set-environment on NixOS unless
      # __NIXOS_SET_ENVIRONMENT_DONE is set.
      export PATH="${lib.makeBinPath ([ d.tools d.scripts ] ++ path)}"
      export SHELL="${pkgs.zsh}/bin/zsh"
      export TERM=xterm-256color LANG=C.UTF-8 COLORTERM=truecolor DOTFILES_SANDBOX=1
      export TMUX_TMPDIR="$HOME/.tmp" TMPDIR="$HOME/.tmp" XDG_RUNTIME_DIR="$HOME/.run"
      export __NIXOS_SET_ENVIRONMENT_DONE=1
      cd "$HOME"
    '';

  # A check: `script` runs in a throwaway HOME, calls `fail <message>` on a broken assertion,
  # and $out exists only when it got to the end.
  #
  # The build sandbox has /bin/sh but no /usr/bin/env, which every NixOS machine has, and no
  # /tmp. herdr-login-warning calls `/usr/bin/env python3` in its body (scripts.nix rewrites only
  # /usr/bin/python3) and zsh writes here-documents to /tmp. So the script runs in a bubblewrap
  # namespace that is the build sandbox plus /usr/bin/env and a /tmp, and nothing else from outside.
  mkCheck =
    name:
    {
      path ? [ ],
      env ? { },
    }:
    script:
    let
      body = pkgs.writeText "check-${name}.sh" ''
        set -euo pipefail
        fail() { echo "${name}: FAIL: $*" >&2; exit 1; }
        ${mkHome { inherit path; }}
        ${script}
        echo "${name}: all assertions passed"
      '';
    in
    pkgs.runCommand "check-${name}" env ''
      ${pkgs.bubblewrap}/bin/bwrap --unshare-user --die-with-parent \
        --bind /nix /nix --bind "$NIX_BUILD_TOP" "$NIX_BUILD_TOP" \
        --dev-bind /dev /dev --proc /proc --tmpfs /tmp --ro-bind /bin /bin --ro-bind /etc /etc \
        --ro-bind ${pkgs.coreutils}/bin/env /usr/bin/env \
        --chdir "$NIX_BUILD_TOP" \
        -- ${pkgs.bash}/bin/bash ${body}
      touch "$out"
    '';
}
