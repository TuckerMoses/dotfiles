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

# ── what programs actually load ──────────────────────────────────────────────
# A stowed file can be correct and still not be what a program uses: another
# file it also reads can override it, an environment variable can point it
# elsewhere, or a long-running process can still hold an older version.
section "What programs actually load"
mtime() { /usr/bin/python3 -c 'import os,sys; print(int(os.path.getmtime(os.path.realpath(sys.argv[1]))))' "$1" 2>/dev/null || echo 0; }
when()  { /usr/bin/python3 -c 'import sys,time; print(time.strftime("%Y-%m-%d %H:%M", time.localtime(int(sys.argv[1]))))' "$1"; }

# Environment variables that silently redirect a program to another config.
for var in ZDOTDIR XDG_CONFIG_HOME STARSHIP_CONFIG ATUIN_CONFIG_DIR NVIM_APPNAME HERDR_CONFIG_PATH; do
  val="${!var:-}"; [[ -z "$val" ]] && continue
  case "$var" in
    ZDOTDIR)         [[ "$(real "$val")" == "$(real "$HOME")" ]] && continue ;;
    XDG_CONFIG_HOME) [[ "$(real "$val")" == "$(real "$HOME/.config")" ]] && continue ;;
  esac
  fail "$var=$val redirects a program away from the dotfiles config"
done

# tmux: it loads every file in its built-in search list, so any other existing
# file adds to (and can override) the dotfiles one. The list comes from the binary.
if have tmux; then
  tmux_conf="$(real "$DOTFILES_DIR/tmux/.tmux.conf")"
  search="$(strings "$(command -v tmux)" 2>/dev/null | grep -m1 -E '^[^ ]*tmux\.conf(:[^ ]*tmux\.conf)+$' || echo "/etc/tmux.conf:~/.tmux.conf:\$XDG_CONFIG_HOME/tmux/tmux.conf:~/.config/tmux/tmux.conf")"
  shadow=0; seen=" "
  IFS=':' read -r -a candidates <<<"$search"
  for c in "${candidates[@]}"; do
    c="${c/#\~/$HOME}"; c="${c/\$XDG_CONFIG_HOME/${XDG_CONFIG_HOME:-$HOME/.config}}"
    [[ -e "$c" ]] || continue
    r="$(real "$c")"; [[ "$seen" == *" $r "* ]] && continue; seen="$seen$r "
    [[ "$r" == "$tmux_conf" ]] && continue
    fail "tmux also loads $c, which is not the dotfiles config"; shadow=1
  done
  (( shadow )) || pass "tmux: no other config file on its search path"
  # Running servers keep the config they loaded until it is re-sourced.
  conf_t="$(mtime "$HOME/.tmux.conf")"; servers=0
  sockdir="$(real "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)")"
  for sock in "$sockdir"/*; do
    [[ -S "$sock" ]] || continue
    start="$(tmux -S "$sock" display -p '#{start_time}' 2>/dev/null)" || continue
    servers=$((servers+1))
    if (( start < conf_t )); then
      warn "tmux server $(basename "$sock") started $(when "$start"), before ~/.tmux.conf changed $(when "$conf_t"): run tmux source-file ~/.tmux.conf"
    else pass "tmux server $(basename "$sock") started after the last config change"; fi
  done
  (( servers )) || info "no tmux server running"
fi

# Ghostty on macOS also reads its Application Support config, after the XDG one,
# so anything in it overrides the dotfiles config.
if [[ "$OS" == "Darwin" ]]; then
  for f in "$HOME/Library/Application Support/com.mitchellh.ghostty/config" \
           "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"; do
    [[ -e "$f" ]] || continue
    if [[ -s "$f" ]]; then fail "ghostty also loads ${f/#$HOME/~} after the dotfiles config, overriding it"
    else info "ghostty: ${f/#$HOME/~} exists but is empty (harmless; anything added there overrides the dotfiles config)"; fi
  done
  gpid="$(pgrep -f 'Ghostty.app/Contents/MacOS/ghostty' | head -1)"
  if [[ -n "$gpid" ]]; then
    gstart="$(/usr/bin/python3 -c 'import sys,time; print(int(time.mktime(time.strptime(sys.argv[1].strip(), "%a %b %d %H:%M:%S %Y"))))' "$(ps -o lstart= -p "$gpid")" 2>/dev/null || echo 0)"
    gconf="$(mtime "$HOME/.config/ghostty/config")"
    if (( gstart < gconf )); then warn "ghostty started before its config changed $(when "$gconf"): reload it (cmd+shift+,) unless you already have"
    else pass "ghostty started after the last config change"; fi
  fi
fi

# nvim: its config dir comes from the repo, but it also loads plugin, ftplugin,
# after and lua files from its data "site" dir, and a running nvim keeps the
# config it started with.
if have nvim; then
  site="$HOME/.local/share/nvim/site"; extra=""
  for d in plugin ftplugin after lua init.lua init.vim; do [[ -e "$site/$d" ]] && extra="$extra $d"; done
  if [[ -n "$extra" ]]; then warn "nvim also loads config from ${site/#$HOME/~} (${extra# }), which is not in dotfiles"
  else pass "nvim: nothing config-like outside the dotfiles config dir"; fi
  nconf="$(find "$DOTFILES_DIR/nvim" -type f -exec stat -f '%m' {} + 2>/dev/null | sort -n | tail -1)"
  [[ -n "$nconf" ]] || nconf="$(find "$DOTFILES_DIR/nvim" -type f -printf '%T@\n' 2>/dev/null | cut -d. -f1 | sort -n | tail -1)"
  stale=0; running=0
  for p in $(pgrep -x nvim); do
    running=$((running+1))
    pstart="$(/usr/bin/python3 -c 'import sys,time; print(int(time.mktime(time.strptime(sys.argv[1].strip(), "%a %b %d %H:%M:%S %Y"))))' "$(ps -o lstart= -p "$p")" 2>/dev/null || echo 0)"
    if (( pstart < ${nconf:-0} )); then
      stale=$((stale+1))
      warn "nvim (pid $p, in $(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | sed "s#^$HOME#~#")) started $(when "$pstart"), before its config changed $(when "$nconf"): restart it"
    fi
  done
  if (( running && !stale )); then pass "all $running running nvim instances started after the last config change"; fi
  (( running )) || info "no nvim running"
fi

# zsh: startup files it loads that the repo does not manage.
for f in .zshenv .zprofile .zlogin .zlogout .zshrc.local; do
  [[ -e "$HOME/$f" ]] || continue
  [[ "$(real "$HOME/$f")" == "$DOTFILES_DIR"/* ]] && continue
  warn "zsh loads ~/$f, which is not in dotfiles"
done

# herdr keeps the config it loaded until a reload; its log records both.
if have herdr && [[ -f "$HOME/.config/herdr/herdr-server.log" ]]; then
  hconf="$(mtime "$HOME/.config/herdr/config.toml")"
  hload="$( { grep 'herdr server started' "$HOME/.config/herdr/herdr-server.log"
              grep 'api.request.complete' "$HOME/.config/herdr/herdr-server.log" | grep 'outcome="ok"' | grep 'method="server.reload_config"'
            } | cut -c1-19 | sort | tail -1)"
  if [[ -n "$hload" ]]; then
    hload_t="$(/usr/bin/python3 -c 'import sys,calendar,time; print(calendar.timegm(time.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%S")))' "$hload")"
    if (( hload_t < hconf )); then warn "herdr last loaded its config $(when "$hload_t"), before it changed $(when "$hconf"): run herdr server reload-config"
    else pass "herdr loaded its config after the last change"; fi
  fi
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
