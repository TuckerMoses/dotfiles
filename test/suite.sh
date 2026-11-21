#!/usr/bin/env bash
set -euo pipefail

# ── Dotfiles test suite ─────────────────────────────────────────────────────
# Runs the same core (bootstrap x3, a headless herdr server, nvim plugins, the
# summarizer hook, an interactive zsh, validate.sh) in one of four places:
#
#   test/suite.sh local        throwaway $HOME on this machine, fully isolated
#   test/suite.sh vm-native    fresh Ubuntu guest, this machine's arch (hvf/kvm)
#   test/suite.sh vm-emulated  fresh Ubuntu guest, the other arch (TCG)
#   test/suite.sh here         the real $HOME of a disposable Linux machine
#                              (needs DOTFILES_TEST_DISPOSABLE=1)
#   test/suite.sh report <run-dir>...   side-by-side table of finished runs
#
# Options: --keep (leave the throwaway HOME or the guest), --resume <run-dir>
# (vm-*: reboot the kept guest and continue), --boot-timeout <s>, --timeout <s>.
# local and the guests test the committed HEAD (a git bundle); here tests the checkout it runs in.
# Exit: 0 passed, 1 the suite failed, 3 the environment could not be started.
# Each run writes test/.runs/<env>-<timestamp>/: log, result, validate.txt, meta.

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
RUNS="$REPO/test/.runs"
# shellcheck source=lib/vm.sh
source "$REPO/test/lib/vm.sh"

log()  { printf '[suite %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die3() { log "cannot start the environment: $*"; exit 3; }
usage() { sed -n '4,19p' "$0" | sed 's/^# \{0,1\}//'; }

STEPS=(bootstrap-1 herdr-server bootstrap-2 bootstrap-3-idempotent nvim-plugins summarizer-hook zsh-interactive validate teardown)

real_home() {
  /usr/bin/env python3 -c 'import os,pwd; print(pwd.getpwuid(os.getuid()).pw_dir)' 2>/dev/null \
    || getent passwd "$(id -un)" | cut -d: -f6
}

meta_set() { # meta_set <run-dir> <key> <value>
  local f="$1/meta"; touch "$f"
  grep -v "^$2=" "$f" > "$f.tmp" || true
  echo "$2=$3" >> "$f.tmp"; mv "$f.tmp" "$f"
}
meta_get() { sed -n "s/^$2=//p" "$1/meta" 2>/dev/null | tail -1; }

new_run_dir() {
  local d; d="$RUNS/$1-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$d"; (cd "$d" && pwd -P)
}

bundle_head() { # bundle_head <file>: HEAD (and its branch, so the clone checks it out)
  local branch
  branch="$(git -C "$REPO" symbolic-ref -q --short HEAD || true)"
  if [[ -n "$(git -C "$REPO" status --porcelain --untracked-files=no)" ]]; then
    log "note: uncommitted changes are not tested; testing commit $(git -C "$REPO" rev-parse --short HEAD)"
  fi
  git -C "$REPO" bundle create -q "$1" HEAD ${branch:+"$branch"}
}

# ── the core ────────────────────────────────────────────────────────────────
# Runs with HOME already set to the home under test and DOT pointing at a clone
# inside it. Each step writes $RUN/state/<n>; a passed step is not repeated on
# --resume, except server, validate and teardown, which always run (the herdr server
# does not survive a reboot).

record() { # record <n> <status> <detail>
  printf '%s\t%s\t%s\t%s\n' "$1" "${STEPS[$(( $1 - 1 ))]}" "$2" "$3" > "$RUN/state/$1"
  cat "$RUN"/state/[0-9]* 2>/dev/null | sort -n > "$RUN/result"
  log "step $1 ${STEPS[$(( $1 - 1 ))]}: $2${3:+ ($3)}"
}

# with_timeout <seconds> <cmd...>: macOS has no timeout(1); perl is on both OSes.
with_timeout() { perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$@"; }

# The herdr socket this environment resolves must be inside $HOME, and nothing
# from an outer herdr session may be in the environment.
herdr_guard() {
  local v sock
  for v in $(compgen -e); do
    [[ "$v" == HERDR_* && "$v" != HERDR_SUMMARIZER_* ]] && { log "refusing: $v is set"; return 1; }
  done
  sock="$(herdr status server 2>/dev/null | sed -n 's/^ *socket: //p' | head -1 | tr -s /)"
  if [[ -z "$sock" || "$sock" != "$HOME"/* ]]; then
    log "refusing: herdr would use socket '${sock:-?}', which is not inside $HOME"; return 1
  fi
}
herdr_up() { herdr workspace list >/dev/null 2>&1; }

core_bootstrap() { # core_bootstrap <n> <run#>
  local n="$1" out="$RUN/bootstrap-$2.txt" rc=0
  log "running ./bootstrap.sh (run $2)"
  (cd "$DOT" && ./bootstrap.sh) > "$out" 2>&1 || rc=$?
  sed 's/^/    | /' "$out"
  if (( rc != 0 )); then record "$n" fail "exit $rc"; return; fi
  if [[ "$2" == 3 ]] && grep -q '^==> Installing' "$out"; then
    record "$n" fail "installed again: $(grep '^==> Installing' "$out" | head -3 | tr '\n' ';')"; return
  fi
  record "$n" pass "exit 0"
}

core_server() {
  herdr_guard || { record 2 fail "herdr socket not isolated"; return; }
  if herdr_up; then record 2 pass "already running"; return; fi
  mkdir -p "$HERDR_SUMMARIZER_STATE"
  nohup herdr server > "$RUN/herdr-server.out" 2>&1 < /dev/null &
  echo $! > "$RUN/herdr-server.pid"
  local i
  for i in $(seq 1 60); do herdr_up && break; sleep 1; done
  if herdr_up; then record 2 pass "herdr server (headless), pid $(cat "$RUN/herdr-server.pid")"
  else record 2 fail "herdr server did not answer within 60s"; fi
}

core_nvim() {
  local out err
  log "installing nvim plugins (Lazy! restore, from lazy-lock.json)"
  out="$(cd "$HOME" && with_timeout "$NVIM_TIMEOUT" nvim --headless '+Lazy! restore' '+qa' 2>&1)" || true
  echo "$out" | tail -20 | sed 's/^/    | /'
  [[ -d "$HOME/.local/share/nvim/lazy" ]] || { record 5 fail "no plugins installed"; return; }
  # A second start installs whatever LazyVim adds on first run, a third must be clean.
  (cd "$HOME" && with_timeout "$NVIM_TIMEOUT" nvim --headless '+qa' >/dev/null 2>&1) || true
  err="$(cd "$HOME" && with_timeout 300 nvim --headless '+qa' 2>&1 | grep -iE 'error|E[0-9]{2,4}:' | head -3 || true)"
  if [[ -n "$err" ]]; then record 5 fail "$(echo "$err" | tr '\n' ' ')"
  else record 5 pass "$(find "$HOME/.local/share/nvim/lazy" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') plugins, starts clean"; fi
}

core_summarizer() {
  herdr_guard || { record 6 fail "herdr socket not isolated"; return; }
  herdr_up || { record 6 fail "herdr server not running"; return; }
  local plugin="$DOT/herdr-summarizer/plugin" logs i verdict
  herdr plugin list 2>/dev/null | grep -q '^- herdr-summarizer ' || herdr plugin link "$plugin" >/dev/null \
    || { record 6 fail "herdr plugin link failed"; return; }
  herdr_guard || { record 6 fail "herdr socket not isolated"; return; }
  # Creating and focusing a workspace emits pane.focused, which the plugin subscribes to.
  herdr workspace create --cwd "$HOME" --label suite --focus >/dev/null || { record 6 fail "workspace create failed"; return; }
  for i in $(seq 1 "$HOOK_TIMEOUT"); do
    logs="$(herdr plugin log list --plugin herdr-summarizer --limit 50 2>/dev/null || true)"
    verdict="$(echo "$logs" | /usr/bin/python3 -c 'import json,sys
try: logs=json.load(sys.stdin)["result"]["logs"]
except Exception: logs=[]
done=[l for l in logs if l.get("status") not in ("running","pending","queued")]
bad=[l for l in done if l.get("status")!="succeeded"]
if not logs or len(done)<len(logs): print("wait")
elif bad: print("fail %d of %d hook runs failed: %s" % (len(bad), len(logs), (bad[0].get("stderr") or "")[:200].replace("\n"," ")))
else: print("pass %d hook runs succeeded (%s)" % (len(logs), ",".join(sorted(set(l["event"] for l in logs)))))' 2>/dev/null || echo wait)"
    [[ "$verdict" != wait ]] && break
    sleep 1
  done
  if [[ "$verdict" == pass* && ! -s "$HERDR_SUMMARIZER_STATE/state.json" ]]; then
    verdict="fail hook ran but herdr-summarize wrote no state"
  fi
  case "$verdict" in
    pass*) record 6 pass "${verdict#pass }" ;;
    fail*) record 6 fail "${verdict#fail }" ;;
    *)     record 6 fail "no hook run logged within ${HOOK_TIMEOUT}s" ;;
  esac
}

core_zsh() {
  # A real interactive zsh in a pty (a throwaway tmux server): zsh-vi-mode runs
  # zvm_after_init (fzf, atuin) at the first prompt, which `zsh -i -c` never shows.
  # In `here` (guests, CI) PATH is the one the suite started with, so ~/.local/bin must come from .zshrc; in `local` it is already on the starting PATH.
  local sock="dotfiles-suite-zsh" probe="$RUN/zsh-probe.zsh" out="$RUN/zsh-probe.out" err="$RUN/zsh-stderr.txt" i missing=""
  cat > "$probe" <<'EOF'
print -r -- "zvm=${+functions[zvm_init]}"
print -r -- "starship=${+functions[prompt_starship_precmd]}"
[[ "$(bindkey -M viins '^T')" == *fzf* ]] && print fzf=1 || print fzf=0
[[ "$(bindkey -M viins '^R')" == *atuin* ]] && print atuin=1 || print atuin=0
print -r -- "zoxide=${+functions[__zoxide_z]}"
print -r -- probe-done
EOF
  rm -f "$out" "$err"
  tmux -L "$sock" kill-server 2>/dev/null || true
  tmux -L "$sock" -f /dev/null new-session -d -x 160 -y 40 \
    "cd '$HOME' && env PATH='$ORIG_PATH' SHELL='$(command -v zsh)' zsh -i 2>'$err'"
  for i in $(seq 1 "$ZSH_TIMEOUT"); do
    [[ -n "$(tmux -L "$sock" capture-pane -p 2>/dev/null | tr -d '[:space:]')" ]] && break; sleep 1
  done
  sleep 2
  tmux -L "$sock" send-keys "source '$probe' > '$out' 2>&1; exit" Enter
  for i in $(seq 1 "$ZSH_TIMEOUT"); do grep -q probe-done "$out" 2>/dev/null && break; sleep 1; done
  tmux -L "$sock" kill-server 2>/dev/null || true
  [[ -f "$out" ]] || { record 7 fail "zsh never ran the probe (no prompt within ${ZSH_TIMEOUT}s)"; return; }
  sed 's/^/    | /' "$out"
  for i in zvm starship fzf atuin zoxide; do grep -qx "$i=1" "$out" || missing="$missing $i"; done
  if [[ -s "$err" ]]; then record 7 fail "stderr: $(head -2 "$err" | tr '\n' ' ')"
  elif [[ -n "$missing" ]]; then record 7 fail "not loaded:$missing"
  else record 7 pass "stderr empty; zsh-vi-mode starship fzf atuin zoxide loaded"; fi
}

core_validate() {
  local rc=0
  (cd "$DOT" && ./validate.sh) > "$RUN/validate.txt" 2>&1 || rc=$?
  sed 's/^/    | /' "$RUN/validate.txt"
  local summary; summary="$(tail -1 "$RUN/validate.txt")"
  if (( rc == 0 )); then record 8 pass "$summary"; else record 8 fail "exit $rc: $summary"; fi
}

core_teardown() {
  local stopped="" sock
  if command -v herdr >/dev/null 2>&1 && herdr_guard >/dev/null 2>&1 && herdr_up; then
    herdr server stop >/dev/null 2>&1 || true; stopped="herdr"
  fi
  if [[ -f "$RUN/herdr-server.pid" ]]; then
    kill "$(cat "$RUN/herdr-server.pid")" 2>/dev/null || true; rm -f "$RUN/herdr-server.pid"
  fi
  for sock in "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"/*; do
    [[ -S "$sock" ]] || continue
    tmux -S "$sock" kill-server 2>/dev/null && stopped="$stopped tmux:$(basename "$sock")"
  done
  record 9 pass "stopped: ${stopped:-nothing running}"
}

run_core() {
  mkdir -p "$RUN/state"
  ORIG_PATH="$PATH"
  # What .zshrc does for an interactive shell; the suite's own commands need it too.
  [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
  export HERDR_SUMMARIZER_STATE="$HOME/.local/state/herdr-summarizer"
  export HERDR_SUMMARIZER_DRY=1     # the summarizer never calls a model in the suite
  # Stands in for an installed Claude Code (its config dir only: no binary, no
  # login), so bootstrap installs herdr's Claude integration and validate checks it.
  mkdir -p "$HOME/.claude"
  local done_ok n
  done_ok() { [[ -f "$RUN/state/$1" ]] && [[ "$(cut -f3 "$RUN/state/$1")" == pass ]]; }
  trap 'core_teardown' EXIT
  done_ok 1 || core_bootstrap 1 1
  core_server
  for n in 3 4; do done_ok "$n" || core_bootstrap "$n" "$((n - 1))"; done
  done_ok 5 || core_nvim
  done_ok 6 || core_summarizer
  done_ok 7 || core_zsh
  core_validate
  trap - EXIT
  core_teardown
  if cut -f3 "$RUN/result" | grep -qv pass; then return 1; fi
}

# ── here ────────────────────────────────────────────────────────────────────
env_here() {
  [[ "$(uname)" == Linux ]] || { log "here: only on Linux"; exit 1; }
  [[ "${DOTFILES_TEST_DISPOSABLE:-}" == 1 ]] || {
    log "here: bootstraps the real \$HOME of this machine; set DOTFILES_TEST_DISPOSABLE=1 if it is disposable"; exit 1; }
  RUN="${RUN_DIR:-$(new_run_dir here)}"; mkdir -p "$RUN"
  DOT="$REPO"
  unset TMUX TMUX_PANE
  export TERM="${TERM:-xterm-256color}"
  [[ "$TERM" == dumb ]] && export TERM=xterm-256color
  local rc=0
  run_core > >(tee -a "$RUN/log") 2>&1 || rc=$?
  echo "$rc" > "$RUN/exit"
  return "$rc"
}

# ── local ───────────────────────────────────────────────────────────────────
# Outer half: checks, a fresh HOME, then re-runs this script under env -i so no
# variable from the calling session (HERDR_*, TMUX*, XDG_*, ZDOTDIR, ...) survives.
env_local() {
  local real tmpbase home path brewp missing=() pair pairs rc=0 start=$SECONDS
  real="$(real_home)"
  RUN="$(new_run_dir local)"
  tmpbase="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  home="$(cd "$(mktemp -d "$tmpbase/dft.XXXXXX")" && pwd -P)"
  # herdr's and tmux's sockets live under it; sun_path is 104 bytes on macOS.
  (( ${#home} <= 72 )) || die3 "throwaway HOME path too long for unix sockets: $home (set TMPDIR shorter)"
  [[ "$home" != "$real" && "$home" != "$(cd "$HOME" && pwd -P)" ]] || die3 "throwaway HOME equals the real home"
  path="$home/.local/bin"
  if [[ "$(uname)" == Darwin ]]; then
    command -v brew >/dev/null 2>&1 || die3 "Homebrew is not installed"
    brewp="$(brew --prefix)"; path="$path:$brewp/bin:$brewp/sbin"
  fi
  path="$path:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  # bootstrap.sh would install a missing system package (brew/apt): a machine
  # change outside $HOME. Stop instead.
  if [[ "$(uname)" == Darwin ]]; then
    pairs="$(sed -n 's/^  for pair in \(.*\); do$/\1/p' "$REPO/bootstrap.sh" | head -1)"
    [[ -n "$pairs" ]] || { rm -rf "$home"; die3 "no macOS 'for pair in' loop found in bootstrap.sh (reformatted?)"; }
    for pair in $pairs herdr; do
      PATH="$path" command -v "${pair#*:}" >/dev/null 2>&1 || missing+=("${pair%%:*}")
    done
    brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1 || missing+=("--cask font-jetbrains-mono-nerd-font")
  else
    pairs="$(sed -n 's/^  for pair in \(.*\); do$/\1/p' "$REPO/bootstrap.sh" | sed -n 2p)"
    [[ "$pairs" == *stow* ]] || { rm -rf "$home"; die3 "no Linux 'for pair in' loop found in bootstrap.sh (reformatted?)"; }
    for pair in $pairs; do
      case "${pair#*:}" in jj|lazyjj) continue ;; esac   # release binaries, installed into HOME (same list as bootstrap.sh's Linux loop)
      PATH="$path" command -v "${pair#*:}" >/dev/null 2>&1 || missing+=("${pair%%:*}")
    done
  fi
  if (( ${#missing[@]} )); then
    rm -rf "$home"
    die3 "bootstrap.sh would install system packages here: ${missing[*]}. Install them first."
  fi
  meta_set "$RUN" env local; meta_set "$RUN" arch "$(uname -m)"; meta_set "$RUN" accel "-"
  meta_set "$RUN" os "$(uname -s)"; meta_set "$RUN" commit "$(git -C "$REPO" rev-parse --short HEAD)"
  meta_set "$RUN" home "$home"; meta_set "$RUN" started "$(date '+%Y-%m-%d %H:%M:%S')"
  bundle_head "$RUN/repo.bundle"
  git clone -q "$RUN/repo.bundle" "$home/dotfiles" || die3 "clone of the bundle failed"
  mkdir -p "$home/t"
  log "local: HOME=$home  run=$RUN"
  # git: no system config and no credential helper. On macOS, Xcode's gitconfig sets
  # credential.helper=osxkeychain; the throwaway HOME has no keychain, so every https
  # clone (Oh My Zsh, TPM plugins, lazy.nvim) would raise a "Keychain Not Found" dialog
  # on the user's screen. A fresh machine has no such helper either.
  env -i HOME="$home" USER="$(id -un)" LOGNAME="$(id -un)" PATH="$path" SHELL=/bin/bash \
    TERM=xterm-256color LANG="${LANG:-en_US.UTF-8}" TMPDIR="${TMPDIR:-/tmp}" TMUX_TMPDIR="$home/t" \
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
    GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= \
    DOTFILES_TEST_REAL_HOME="$real" \
    bash "$home/dotfiles/test/suite.sh" __local-inner "$RUN" > >(tee -a "$RUN/log") 2>&1 || rc=$?
  wait
  finish "$RUN" "$rc" "$start"
  # chmod: Go's module cache (herdr-plus builds with go where it is installed) is read-only.
  if (( rc == 0 && ! KEEP )); then chmod -R u+w "$home"; rm -rf "$home"; meta_set "$RUN" home "(removed)"
  else log "throwaway HOME kept: $home"; fi
  return "$rc"
}

# Inner half: runs under env -i, as the clone inside the throwaway HOME.
env_local_inner() {
  RUN="$1"; DOT="$REPO"
  local v home_p real_p
  home_p="$(cd "$HOME" && pwd -P)"; real_p="$(cd "${DOTFILES_TEST_REAL_HOME:?}" && pwd -P)"
  [[ "$home_p" != "$real_p" ]] || { log "refusing: HOME is the real home"; exit 3; }
  [[ "$DOT" == "$home_p"/* ]] || { log "refusing: the repo under test is not inside the throwaway HOME"; exit 3; }
  for v in $(compgen -e); do
    case "$v" in HERDR_*|TMUX|TMUX_PANE|ZDOTDIR|XDG_*|STARSHIP_*|ATUIN_*|NVIM_APPNAME)
      log "refusing: $v is set"; exit 3 ;; esac
  done
  [[ "$TMUX_TMPDIR" == "$HOME"/* ]] || { log "refusing: TMUX_TMPDIR is outside HOME"; exit 3; }
  # Step 1's bootstrap.sh already talks to herdr (plugin and integration installs). Only a herdr
  # already on PATH can be checked here; one bootstrap installs is first checked in step 2.
  if command -v herdr >/dev/null 2>&1; then herdr_guard || exit 3; fi
  run_core || exit 1
}

# ── vm-native / vm-emulated ─────────────────────────────────────────────────
env_vm() {
  local env="$1" arch mode rc=0 start=$SECONDS n=0 st i
  if [[ -n "$RESUME" ]]; then
    RUN="$(cd "$RESUME" && pwd -P)"; env="$(meta_get "$RUN" env)"
    [[ -f "$RUN/overlay.qcow2" ]] || die3 "$RUN has no kept guest to resume"
  else RUN="$(new_run_dir "$env")"; fi
  if [[ "$env" == vm-native ]]; then arch="$(vm_host_arch)" || exit 3; mode=native
  else arch="$(vm_other_arch)"; mode=tcg; fi
  BOOT_TIMEOUT="${BOOT_TIMEOUT:-$([[ $mode == native ]] && echo 600 || echo 2400)}"
  CORE_TIMEOUT="${CORE_TIMEOUT:-$([[ $mode == native ]] && echo 5400 || echo 21600)}"
  exec > >(tee -a "$RUN/log") 2>&1
  trap 'vm_cleanup' EXIT
  trap 'exit 130' INT TERM HUP   # so the guest is still powered off
  if [[ -z "$RESUME" ]]; then
    meta_set "$RUN" env "$env"; meta_set "$RUN" arch "$arch"; meta_set "$RUN" accel "$mode"
    meta_set "$RUN" os "Ubuntu $VM_RELEASE"; meta_set "$RUN" commit "$(git -C "$REPO" rev-parse --short HEAD)"
    meta_set "$RUN" started "$(date '+%Y-%m-%d %H:%M:%S')"
    vm_create "$RUN" "$arch" || die3 "could not prepare the $arch guest"
  fi
  vm_start "$RUN" "$mode" || die3 "qemu did not start"
  vm_wait "$RUN" "$BOOT_TIMEOUT" || die3 "guest never became reachable"
  if ! vm_ssh "$RUN" 'test -d dotfiles'; then
    bundle_head "$RUN/repo.bundle"
    meta_set "$RUN" commit "$(git -C "$REPO" rev-parse --short HEAD)"   # the commit actually bundled
    vm_ssh "$RUN" 'cat > repo.bundle' < "$RUN/repo.bundle" || die3 "copying the bundle failed"
    vm_ssh "$RUN" 'git clone -q repo.bundle dotfiles' || die3 "clone in the guest failed"
  fi
  # Detached in the guest, so a dropped SSH connection does not stop the run.
  if ! vm_ssh "$RUN" 'test -f run/exit'; then
    vm_ssh "$RUN" 'mkdir -p run; if [ -f run/pid ] && kill -0 "$(cat run/pid)" 2>/dev/null; then :; else
      DOTFILES_TEST_DISPOSABLE=1 RUN_DIR=$HOME/run TERM=xterm-256color setsid nohup dotfiles/test/suite.sh here > run/console.out 2>&1 < /dev/null & echo $! > run/pid; fi' \
      || die3 "could not start the suite in the guest"
  fi
  log "suite running in the guest (log follows)"
  local again="re-run fresh, or with --keep to be able to resume"
  (( KEEP )) && again="continue with --resume $RUN --keep"
  while :; do
    if ! st="$(vm_ssh "$RUN" "tail -n +$((n + 1)) run/log 2>/dev/null")"; then
      vm_alive "$RUN" || die3 "the guest died during the run (see console.log; then $again)"
      sleep 20; continue
    fi
    if [[ -n "$st" ]]; then printf '%s\n' "$st"; n=$(( n + $(printf '%s\n' "$st" | wc -l) )); fi
    i="$(vm_ssh "$RUN" 'cat run/exit 2>/dev/null' || true)"
    [[ -n "$i" ]] && { rc="$i"; break; }
    if (( SECONDS - start > CORE_TIMEOUT )); then log "timed out after ${CORE_TIMEOUT}s (then $again)"; rc=1; break; fi
    sleep 15
  done
  mkdir -p "$RUN/guest"
  vm_ssh "$RUN" 'tar -C run -cf - .' | tar -C "$RUN/guest" -xf - || log "could not copy results out of the guest"
  for i in result validate.txt; do cp "$RUN/guest/$i" "$RUN/$i" 2>/dev/null || true; done
  [[ -f "$RUN/result" ]] || rc=3
  finish "$RUN" "$rc" "$start"
  return "$rc"
}

vm_cleanup() {
  [[ -n "${RUN:-}" ]] || return 0
  vm_stop "$RUN" 2>/dev/null || true
  if (( KEEP )); then
    log "guest kept: $RUN (continue an interrupted run: test/suite.sh --resume $RUN --keep)"
  else rm -f "$RUN/overlay.qcow2" "$RUN/vars.fd" "$RUN/seed.iso" "$RUN/repo.bundle"; fi
}

finish() { # finish <run-dir> <rc> <start-seconds>
  meta_set "$1" exit "$2"; meta_set "$1" seconds "$(( SECONDS - $3 ))"
  meta_set "$1" finished "$(date '+%Y-%m-%d %H:%M:%S')"
  log "result ($1/result):"; sed 's/^/    /' "$1/result" 2>/dev/null || true
  log "exit $2 after $(( (SECONDS - $3) / 60 ))m$(( (SECONDS - $3) % 60 ))s"
}

# ── report ──────────────────────────────────────────────────────────────────
report() {
  local d i n hdr sep row s
  hdr="| step |"; sep="|---|"
  for d in "$@"; do
    hdr="$hdr $(meta_get "$d" env) ($(meta_get "$d" arch), $(meta_get "$d" accel)) |"; sep="$sep---|"
  done
  echo "$hdr"; echo "$sep"
  for i in "${!STEPS[@]}"; do
    n=$((i + 1)); row="| $n. ${STEPS[$i]} |"
    for d in "$@"; do
      s="$(awk -F'\t' -v n="$n" '$1 == n {print $3 ($4 != "" ? ": " $4 : "")}' "$d/result" 2>/dev/null | cut -c1-90)"
      row="$row ${s:-not run} |"
    done
    echo "$row"
  done
  row="| commit |"; for d in "$@"; do row="$row $(meta_get "$d" commit) |"; done; echo "$row"
  row="| wall time |"; for d in "$@"; do s="$(meta_get "$d" seconds)"; row="$row $(( ${s:-0} / 60 ))m$(( ${s:-0} % 60 ))s |"; done; echo "$row"
  row="| exit |"; for d in "$@"; do row="$row $(meta_get "$d" exit) |"; done; echo "$row"
}

# ── main ────────────────────────────────────────────────────────────────────
KEEP=0; RESUME=""; ENV_NAME=""; ARGS=()
NVIM_TIMEOUT="${DOTFILES_TEST_NVIM_TIMEOUT:-1800}"
HOOK_TIMEOUT="${DOTFILES_TEST_HOOK_TIMEOUT:-180}"
ZSH_TIMEOUT="${DOTFILES_TEST_ZSH_TIMEOUT:-120}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep) KEEP=1 ;;
    --resume) RESUME="${2:?--resume needs a run dir}"; shift ;;
    --boot-timeout) BOOT_TIMEOUT="${2:?}"; shift ;;
    --timeout) CORE_TIMEOUT="${2:?}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) if [[ -z "$ENV_NAME" ]]; then ENV_NAME="$1"; else ARGS+=("$1"); fi ;;
  esac
  shift
done
[[ -n "$RESUME" && -z "$ENV_NAME" ]] && ENV_NAME="$(meta_get "$RESUME" env)"

case "$ENV_NAME" in
  local)        env_local ;;
  __local-inner) env_local_inner "${ARGS[0]}" ;;
  vm-native|vm-emulated) env_vm "$ENV_NAME" ;;
  here)         env_here ;;
  report)       (( ${#ARGS[@]} )) || { usage; exit 1; }; report "${ARGS[@]}" ;;
  *)            usage; exit 1 ;;
esac
