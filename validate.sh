#!/usr/bin/env bash
# ── Dotfiles validation ─────────────────────────────────────────────────────
# Checks that everything in this repo is live on this machine and working:
# every stowed file links back to this checkout, the tools bootstrap installs
# exist, each config parses, herdr's plugins and integration are healthy, and
# the opt-in herdr-summarizer (if installed) has no failures.
#
# Read-only: it never installs, stows, reloads or edits anything. Config checks
# that need a running program use a throwaway instance.
#
#   ./validate.sh       full report; exits 1 if anything failed
#   ./validate.sh -q    only warnings and failures
#
# Package and tool lists are read from bootstrap.sh, so a package added there
# is validated here without editing this file.

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOTSTRAP="$DOTFILES_DIR/bootstrap.sh"
QUIET=0; [[ "${1:-}" == "-q" ]] && QUIET=1
OS="$(uname)"

if [[ -t 1 ]]; then G=$'\e[38;2;166;227;161m'; Y=$'\e[38;2;249;226;175m'; R=$'\e[38;2;243;139;168m'; D=$'\e[2m'; B=$'\e[1m'; N=$'\e[0m'
else G=""; Y=""; R=""; D=""; B=""; N=""; fi
FAILS=0; WARNS=0; PASSES=0
pass()    { PASSES=$((PASSES+1)); (( QUIET )) || printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn()    { WARNS=$((WARNS+1)); printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
fail()    { FAILS=$((FAILS+1)); printf '  %s✗%s %s\n' "$R" "$N" "$*"; }
info()    { (( QUIET )) || printf '  %s· %s%s\n' "$D" "$*" "$N"; }
section() { (( QUIET )) || printf '\n%s%s%s\n' "$B" "$*" "$N"; }
have()    { command -v "$1" >/dev/null 2>&1; }
real()    { /usr/bin/python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null || realpath "$1"; }

# ── repo ─────────────────────────────────────────────────────────────────────
section "Repository"
branch="$(git -C "$DOTFILES_DIR" branch --show-current)"
info "branch: $branch"
dirty="$(git -C "$DOTFILES_DIR" status --porcelain --untracked-files=no)"
if [[ -z "$dirty" ]]; then pass "no uncommitted changes to tracked files"
else warn "live config differs from the last commit in: $(echo "$dirty" | awk '{print $2}' | tr '\n' ' ')"; fi
if upstream="$(git -C "$DOTFILES_DIR" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)"; then
  read -r behind ahead < <(git -C "$DOTFILES_DIR" rev-list --left-right --count "$upstream...HEAD")
  if (( ahead == 0 && behind == 0 )); then pass "in sync with $upstream"
  else warn "$branch is $ahead ahead, $behind behind $upstream (as of the last fetch)"; fi
else warn "$branch has no upstream branch"; fi

# ── stow packages ────────────────────────────────────────────────────────────
section "Stowed files (each must link back to this checkout)"
packages="$(sed -n 's/^for pkg in \(.*\); do$/\1/p' "$BOOTSTRAP" | head -1)"
packages="$packages $(grep -o -- '--restow [a-z][a-z0-9_-]*' "$BOOTSTRAP" | awk '{print $2}' | sort -u | tr '\n' ' ')"
for pkg in $packages; do
  [[ -d "$DOTFILES_DIR/$pkg" ]] || continue
  bad=0; count=0
  while IFS= read -r -d '' src; do
    rel="${src#"$DOTFILES_DIR/$pkg/"}"; target="$HOME/$rel"; count=$((count+1))
    if [[ ! -e "$target" ]]; then fail "$pkg: ~/$rel is missing (run ./bootstrap.sh)"; bad=1
    elif [[ "$(real "$target")" != "$(real "$src")" ]]; then fail "$pkg: ~/$rel exists but is not linked to this checkout"; bad=1; fi
  done < <(find "$DOTFILES_DIR/$pkg" -type f ! -name '.DS_Store' -print0)
  (( bad )) || pass "$pkg ($count file$([[ $count == 1 ]] || echo s))"
done

# ── tools ────────────────────────────────────────────────────────────────────
section "Tools installed by bootstrap"
if [[ "$OS" == "Darwin" ]]; then pairs="$(sed -n 's/^  for pair in \(.*\); do$/\1/p' "$BOOTSTRAP" | head -1)"
else pairs="$(sed -n 's/^  for pair in \(.*\); do$/\1/p' "$BOOTSTRAP" | sed -n 2p)"; fi
for cmd in $(for pair in $pairs starship atuin herdr; do echo "${pair#*:}"; done | awk '!seen[$0]++'); do
  if have "$cmd"; then pass "$cmd"; else fail "$cmd not on PATH"; fi
done

# ── configs ──────────────────────────────────────────────────────────────────
section "Configs parse and load"
if have zsh; then
  if err="$(zsh -n "$HOME/.zshrc" 2>&1)"; then pass "zsh: ~/.zshrc syntax"; else fail "zsh: $err"; fi
fi

if have tmux; then
  # Source the config into a throwaway server: source-file reports each bad line
  # ("~/.tmux.conf:12: unknown command") on stderr. Errors from loading it with -f
  # are only shown to the first attached client, so they would be missed.
  sock="dotfiles-validate-$$"
  errs="$(tmux -L "$sock" -f /dev/null new-session -d 'sleep 5' \; source-file "$HOME/.tmux.conf" 2>&1)"
  tmux -L "$sock" kill-server 2>/dev/null
  if [[ -z "$errs" ]]; then pass "tmux: ~/.tmux.conf loads cleanly (throwaway server)"
  else fail "tmux: $(echo "$errs" | head -3 | tr '\n' ' ')"; fi
fi

ghostty=""
if have ghostty; then ghostty="$(command -v ghostty)"
elif [[ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ]]; then ghostty=/Applications/Ghostty.app/Contents/MacOS/ghostty; fi
if [[ -n "$ghostty" ]]; then
  if err="$("$ghostty" +validate-config 2>&1)"; then pass "ghostty: config valid"
  else fail "ghostty: $(echo "$err" | head -3 | tr '\n' ' ')"; fi
else info "ghostty not installed; config not checked"; fi

if have starship; then
  err="$(starship print-config 2>&1 >/dev/null | grep -iE 'unable|error|invalid' || true)"
  if [[ -z "$err" ]]; then pass "starship: config parses"; else fail "starship: $(echo "$err" | head -2 | tr '\n' ' ')"; fi
fi

if have atuin; then
  if err="$(atuin info 2>&1 >/dev/null)"; then pass "atuin: config loads"; else fail "atuin: $(echo "$err" | head -2 | tr '\n' ' ')"; fi
fi

if have nvim; then
  # Only start nvim when its plugins are already installed: on a fresh machine
  # lazy.nvim would install them, and validation must not change anything.
  if [[ -d "$HOME/.local/share/nvim/lazy" ]]; then
    err="$(nvim --headless '+qa' 2>&1 | grep -iE 'error|E[0-9]{2,4}:' | head -3 || true)"
    if [[ -z "$err" ]]; then pass "nvim: starts without errors"; else fail "nvim: $(echo "$err" | tr '\n' ' ')"; fi
  else warn "nvim: plugins not installed yet; open nvim once, then re-run"; fi
fi

# ── herdr ────────────────────────────────────────────────────────────────────
section "herdr"
if have herdr; then
  out="$(herdr config check 2>&1)"
  if echo "$out" | grep -q 'config: ok'; then pass "config.toml valid"; else fail "config.toml: $(echo "$out" | tail -2 | tr '\n' ' ')"; fi
  if herdr workspace list >/dev/null 2>&1; then
    pass "server running"
    plugins="$(herdr plugin list 2>/dev/null)"
    for want in $(sed -n 's/.*herdr plugin list.*grep -q \([a-z][a-z0-9.-]*\); then$/\1/p' "$BOOTSTRAP"); do
      line="$(echo "$plugins" | grep -E "^- [^ ]*$want " || true)"
      if [[ -z "$line" ]]; then fail "plugin $want not installed (run ./bootstrap.sh)"
      elif echo "$line" | grep -q ' enabled '; then pass "plugin $want enabled"
      else fail "plugin $want installed but disabled"; fi
    done
    out="$(herdr integration status 2>&1 | grep -i claude || true)"
    if [[ -z "$out" ]] || echo "$out" | grep -qi 'not installed'; then fail "Claude integration not installed (herdr integration install claude)"
    elif echo "$out" | grep -qi 'outdated'; then warn "Claude integration outdated (herdr integration install claude)"
    else pass "Claude integration current"; fi
  else warn "server not running; plugins and integration not checked"; fi
else info "herdr not installed"; fi

# ── herdr-summarizer (opt-in) ────────────────────────────────────────────────
section "herdr-summarizer (opt-in)"
summ="$HOME/.local/bin/herdr-summarize"
for f in "$summ" "$HOME/.local/bin/herdr-recent"; do
  if [[ -x "$f" ]]; then pass "$(basename "$f") executable"; else fail "$(basename "$f") missing or not executable"; fi
done
if [[ -x "$summ" ]]; then
  if /usr/bin/python3 -c 'import sys; p=sys.argv[1]; compile(open(p).read(), p, "exec")' "$summ" 2>/dev/null \
     && "$summ" help >/dev/null 2>&1; then pass "herdr-summarize compiles and runs"
  else fail "herdr-summarize does not compile or run (try: herdr-summarize help)"; fi
fi
if [[ "$OS" == "Darwin" ]] && launchctl print "gui/$(id -u)/dev.dotfiles.herdr-summarizer" >/dev/null 2>&1; then
  fail "the old launchd job is still loaded (run herdr-summarizer/install.sh to remove it)"
fi
if have herdr && herdr workspace list >/dev/null 2>&1; then
  line="$(herdr plugin list 2>/dev/null | grep -E '^- herdr-summarizer ' || true)"
  if [[ -z "$line" ]]; then info "not installed (opt-in: herdr-summarizer/install.sh)"
  else
    if echo "$line" | grep -q "local:$DOTFILES_DIR/herdr-summarizer/plugin\]"; then pass "plugin linked from this checkout"
    else fail "plugin linked from elsewhere: $(echo "$line" | sed 's/.*\[//; s/\]$//') (re-run herdr-summarizer/install.sh)"; fi
    echo "$line" | grep -q ' enabled ' || fail "plugin is disabled"
    [[ -x "$DOTFILES_DIR/herdr-summarizer/plugin/hook" ]] || fail "plugin hook is not executable"
    logs="$(herdr plugin log list --plugin herdr-summarizer --limit 50 2>/dev/null)"
    failed="$(echo "$logs" | /usr/bin/python3 -c 'import json,sys
try: logs=json.load(sys.stdin)["result"]["logs"]
except Exception: logs=[]
bad=[l for l in logs if l.get("status")!="succeeded"]
print(len(bad), len(logs))' 2>/dev/null || echo "0 0")"
    read -r nbad nall <<<"$failed"
    if (( nbad == 0 )); then pass "last $nall plugin hook runs succeeded"
    else fail "$nbad of the last $nall plugin hook runs failed (herdr plugin log list --plugin herdr-summarizer)"; fi
    [[ -e "$HOME/.local/state/herdr-summarizer/only-sessions" ]] && warn "test guard present: the plugin ignores your sessions (delete ~/.local/state/herdr-summarizer/only-sessions)"
    wlog="$HOME/.local/state/herdr-summarizer/worker.log"
    if [[ -s "$wlog" ]] && tail -50 "$wlog" | grep -q 'Traceback\|Error'; then
      warn "worker logged errors recently: $(grep -E 'Error|error' "$wlog" | tail -1 | cut -c1-120)"
    else pass "worker log clean"; fi
  fi
fi

# ── summary ──────────────────────────────────────────────────────────────────
printf '\n%s%d passed%s · %s%d warnings%s · %s%d failed%s\n' "$G" "$PASSES" "$N" "$Y" "$WARNS" "$N" "$R" "$FAILS" "$N"
(( FAILS == 0 ))
