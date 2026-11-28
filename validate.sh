#!/usr/bin/env bash
# ── Highwind validation ─────────────────────────────────────────────────────
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
# NixOS has no /usr/bin/python3. -I on every call: no PYTHON* variables, no script or working dir on sys.path.
PY=/usr/bin/python3; [[ -x "$PY" ]] || PY=python3
real()    { "$PY" -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null || realpath "$1"; }

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
# A file Home Manager placed (the Nix module) instead of a link to this checkout. Prints nothing when it
# is right, else what is wrong. <store> is /nix/store, or a throwaway directory in the self-test below.
nix_placed() {  # <store> <home> <pkg> <rel> <target> <src>
  case "$3/$4" in
    # The module copies these two in as writable files, so lazy.nvim and LazyVim can rewrite them.
    nvim/.config/nvim/lazy-lock.json|nvim/.config/nvim/lazyvim.json)
      [[ -f "$5" && ! -L "$5" && -d "$2/.local/share/highwind" ]] && return ;;
  esac
  if [[ "$(real "$5")" != "$1"/* ]]; then echo "exists but is not linked to this checkout"
  elif [[ "$3" == herdr && "$4" == .local/bin/* ]]; then :  # the build rewrites their interpreters
  elif ! cmp -s "$5" "$6"; then echo "is a Nix store copy that differs from this checkout (rebuild the Home Manager configuration)"; fi
}
for pkg in $packages; do
  [[ -d "$DOTFILES_DIR/$pkg" ]] || continue
  bad=0; count=0
  while IFS= read -r -d '' src; do
    rel="${src#"$DOTFILES_DIR/$pkg/"}"; target="$HOME/$rel"; count=$((count+1))
    if [[ ! -e "$target" ]]; then fail "$pkg: ~/$rel is missing (run ./bootstrap.sh)"; bad=1
    elif [[ "$(real "$target")" != "$(real "$src")" ]]; then
      why="exists but is not linked to this checkout"
      [[ -d /nix/store ]] && why="$(nix_placed /nix/store "$HOME" "$pkg" "$rel" "$target" "$src")"
      [[ -z "$why" ]] || { fail "$pkg: ~/$rel $why"; bad=1; }
    fi
  done < <(find "$DOTFILES_DIR/$pkg" \( -type f -o -type l \) ! -name '.DS_Store' -print0)
  (( bad )) || pass "$pkg ($count file$([[ $count == 1 ]] || echo s))"
done
# nix_placed against a throwaway store and home, since a machine without Nix never reaches it above.
check_nix_placed() {
  local t s src="$DOTFILES_DIR/zsh/.zshrc" got=""
  t="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-validate-store.XXXXXX")"; s="$(real "$t")/store"
  mkdir -p "$s" "$t/home/.local/share/highwind"
  cp "$src" "$s/same"; { cat "$src"; echo '# changed'; } >"$s/differs"; cp "$src" "$t/lock"
  got+="[$(nix_placed "$s" "$t/home" zsh .zshrc "$s/same" "$src")]"
  got+="[$(nix_placed "$s" "$t/home" zsh .zshrc "$s/differs" "$src")]"
  got+="[$(nix_placed "$s" "$t/home" herdr .local/bin/herdr-plugins "$s/differs" "$src")]"
  got+="[$(nix_placed "$s" "$t/home" nvim .config/nvim/lazy-lock.json "$t/lock" "$src")]"
  got+="[$(nix_placed "$s" "$t/home" zsh .zshrc "$t/lock" "$src")]"
  rm -rf "$t"
  if [[ "$got" == "[][is a Nix store copy that differs"*"][][][exists but is not linked to this checkout]" ]]; then
    pass "Nix store copies: equal bytes pass, a difference fails, herdr scripts and nvim lock files exempt (self-test)"
  else fail "Nix store rule (nix_placed) gives the wrong answers on a throwaway store: $got"; fi
}
check_nix_placed

# Configs must work for any user and any home directory: no literal home paths.
hard="$(git -C "$DOTFILES_DIR" grep -nIE '(/Users|/home)/[A-Za-z0-9._-]+' -- . ':!docs' ':!CHANGELOG.md' ':!validate.sh' ':!nix' ':!nixos' || true)"
if [[ -z "$hard" ]]; then pass "no hardcoded home directory paths in tracked files"
else fail "hardcoded home directory path (use \$HOME, ~ or a relative path): $(echo "$hard" | cut -d: -f1,2 | tr '\n' ' ')"; fi
# The Nix files may name test homes (/home/test), never the owner's. A macOS home is built from the
# user name ("/Users" + "/${user}", nix/lib/home-directory.nix); a literal name after /Users/ fails.
check_nix_home_paths() {  # <repo>
  local hard
  hard="$(git -C "$1" grep -nIE '/Users/[A-Za-z0-9._-]|/home/tucker' -- nix nixos || true)"
  if [[ -z "$hard" ]]; then pass "no owner home directory paths under nix/ and nixos/"
  else fail "owner home directory path under nix/ or nixos/ (build it from the user name): $(echo "$hard" | cut -d: -f1,2 | tr '\n' ' ')"; fi
}
check_nix_home_paths "$DOTFILES_DIR"

# Python in these scripts goes through one variable that falls back to python3 on PATH (NixOS has no
# /usr/bin/python3), and every call has -I. herdr-summarize's interpreter line is rewritten by the Nix build instead.
check_python_calls() {  # <repo>
  local f bad="" n
  for f in validate.sh test/suite.sh herdr/.local/bin/herdr-plugins; do
    [[ -f "$1/$f" ]] || { bad+=" $f(missing)"; continue; }
    # [p]: these patterns must not match their own lines in this file.
    grep -qx 'PY=/usr/bin/[p]ython3; \[\[ -x "\$PY" \]\] || PY=python3' "$1/$f" || bad+=" $f(no fallback)"
    n="$(grep -v '^[[:space:]]*#' "$1/$f" | grep -c '/usr/bin/[p]ython3')"
    (( n == 1 )) || bad+=" $f(the absolute python path on $n code lines, not 1)"
    n="$(grep -nE '(python3(\.[0-9]+)?|"\$(PY|p|tomlpy|\{TOMLPY:-\$PY\})")[[:space:]]+-(c|m|[[:space:]]|$)' "$1/$f" | grep -v '^[0-9]*:[[:space:]]*#' | cut -d: -f1 | tr '\n' ',')"
    [[ -z "$n" ]] || bad+=" $f(no -I: line ${n%,})"
  done
  if [[ -z "$bad" ]]; then pass "Python calls: one system-Python fallback variable per script, all with -I"
  else fail "Python calls:$bad"; fi
}
check_python_calls "$DOTFILES_DIR"

# ── tools ────────────────────────────────────────────────────────────────────
section "Tools installed by bootstrap"
if [[ "$OS" == "Darwin" ]]; then pairs="$(sed -n 's/^  for pair in \(.*\); do$/\1/p' "$BOOTSTRAP" | head -1)"
else pairs="$(sed -n 's/^  for pair in \(.*\); do$/\1/p' "$BOOTSTRAP" | sed -n 2p)"; fi
[[ -n "$pairs" ]] || fail "bootstrap.sh: no 'for pair in' tool loop found (reformatted?)"
for cmd in $(for pair in $pairs starship atuin herdr; do echo "${pair#*:}"; done | awk '!seen[$0]++'); do
  if have "$cmd"; then pass "$cmd"; else fail "$cmd not on PATH"; fi
done

# ── configs ──────────────────────────────────────────────────────────────────
section "Configs parse and load"
if have zsh; then
  if err="$(zsh -n "$HOME/.zshrc" 2>&1)"; then pass "zsh: ~/.zshrc syntax"; else fail "zsh: $err"; fi
  # An interactive start must print nothing on stderr and must load zsh-vi-mode
  # (sourced from brew or from the Oh My Zsh custom plugin, whichever exists).
  # HISTFILE and ZSH_COMPDUMP point at a throwaway dir so the real ones are not rewritten.
  zt="$(mktemp -d)"
  out="$(cd "$HOME" && HISTFILE=/dev/null ZSH_COMPDUMP="$zt/zcompdump" zsh -i -c 'print -r -- "zvm-loaded=${+functions[zvm_init]}"' </dev/null 2>&1)"
  rm -rf "$zt"
  errs="$(echo "$out" | grep -v '^zvm-loaded=' || true)"
  if [[ -n "$errs" ]]; then fail "zsh: interactive start writes to stderr: $(echo "$errs" | head -2 | tr '\n' ' ')"
  else pass "zsh: interactive start is clean"; fi
  if echo "$out" | grep -qx 'zvm-loaded=1'; then pass "zsh: zsh-vi-mode loaded"
  else fail "zsh: zsh-vi-mode not loaded (brew install zsh-vi-mode, or re-run ./bootstrap.sh)"; fi
fi

ghostty=""
if have ghostty; then ghostty="$(command -v ghostty)"
elif [[ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ]]; then ghostty=/Applications/Ghostty.app/Contents/MacOS/ghostty; fi
if [[ -n "$ghostty" ]]; then
  if err="$("$ghostty" +validate-config 2>&1)"; then pass "ghostty: config valid"
  else fail "ghostty: $(echo "$err" | head -3 | tr '\n' ' ')"; fi
else info "ghostty not installed; config not checked"; fi

# The Nerd Font the Ghostty config names (the JetBrains Mono Nerd Font family).
font="$(sed -n 's/^font-family *= *//p' "$DOTFILES_DIR/ghostty/.config/ghostty/config" | head -1 | tr -d '"')"
font="${font:-JetBrainsMono Nerd Font}"
if [[ "$OS" == "Darwin" ]]; then
  if have brew && brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then pass "font: JetBrains Mono Nerd Font installed (brew cask)"
  else fail "font: JetBrains Mono Nerd Font not installed (brew install --cask font-jetbrains-mono-nerd-font)"; fi
elif have fc-list && fc-list : family 2>/dev/null | tr ',' '\n' | grep -ixF "$font" >/dev/null; then pass "font: $font installed (fontconfig)"
else fail "font: $font not found by fc-list (run ./bootstrap.sh)"; fi

if have starship; then
  err="$(starship print-config 2>&1 >/dev/null | grep -iE 'unable|error|invalid' || true)"
  if [[ -z "$err" ]]; then pass "starship: config parses"; else fail "starship: $(echo "$err" | head -2 | tr '\n' ' ')"; fi
fi

if have atuin; then
  if err="$(atuin info 2>&1 >/dev/null)"; then pass "atuin: config loads"; else fail "atuin: $(echo "$err" | head -2 | tr '\n' ' ')"; fi
  # Shell history must not upload in the background: the resolved setting, after defaults and env.
  async="$(atuin config get --resolved auto_sync 2>/dev/null | tail -1)"
  if [[ "$async" == "false" ]]; then pass "atuin: auto_sync is off"
  else fail "atuin: auto_sync resolves to '${async:-unknown}', so history would sync in the background once logged in"; fi
  if atuin status >/dev/null 2>&1; then warn "atuin: logged in to a sync server (history uploads when you run atuin sync)"; fi
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
mtime() { "$PY" -I -c 'import os,sys; print(int(os.path.getmtime(os.path.realpath(sys.argv[1]))))' "$1" 2>/dev/null || echo 0; }
when()  { "$PY" -I -c 'import sys,time; print(time.strftime("%Y-%m-%d %H:%M", time.localtime(int(sys.argv[1]))))' "$1"; }

# Environment variables that silently redirect a program to another config.
for var in ZDOTDIR XDG_CONFIG_HOME STARSHIP_CONFIG ATUIN_CONFIG_DIR NVIM_APPNAME HERDR_CONFIG_PATH; do
  val="${!var:-}"; [[ -z "$val" ]] && continue
  case "$var" in
    ZDOTDIR)         [[ "$(real "$val")" == "$(real "$HOME")" ]] && continue ;;
    XDG_CONFIG_HOME) [[ "$(real "$val")" == "$(real "$HOME/.config")" ]] && continue ;;
  esac
  fail "$var=$val redirects a program away from the highwind config"
done

# Ghostty on macOS also reads its Application Support config, after the XDG one,
# so anything in it overrides the highwind config.
if [[ "$OS" == "Darwin" ]]; then
  for f in "$HOME/Library/Application Support/com.mitchellh.ghostty/config" \
           "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"; do
    [[ -e "$f" ]] || continue
    if [[ -s "$f" ]]; then fail "ghostty also loads ${f/#$HOME/~} after the highwind config, overriding it"
    else info "ghostty: ${f/#$HOME/~} exists but is empty (harmless; anything added there overrides the highwind config)"; fi
  done
fi
# A running Ghostty keeps the config it started with.
if [[ "$OS" == "Darwin" ]]; then gpid="$(pgrep -f 'Ghostty.app/Contents/MacOS/ghostty' | head -1)"
else gpid="$(pgrep -x ghostty | head -1)"; fi
if [[ -n "$gpid" ]]; then
  gstart="$("$PY" -I -c 'import sys,time; print(int(time.mktime(time.strptime(sys.argv[1].strip(), "%a %b %d %H:%M:%S %Y"))))' "$(ps -o lstart= -p "$gpid")" 2>/dev/null || echo 0)"
  gconf="$(mtime "$HOME/.config/ghostty/config")"
  if [[ "$OS" == "Darwin" ]]; then greload="cmd+shift+,"; else greload="ctrl+shift+,"; fi
  if (( gstart < gconf )); then warn "ghostty started before its config changed $(when "$gconf"): reload it ($greload) unless you already have"
  else pass "ghostty started after the last config change"; fi
fi

# nvim: its config dir comes from the repo, but it also loads plugin, ftplugin,
# after and lua files from its data "site" dir, and a running nvim keeps the
# config it started with.
if have nvim; then
  site="$HOME/.local/share/nvim/site"; extra=""
  for d in plugin ftplugin after lua init.lua init.vim; do [[ -e "$site/$d" ]] && extra="$extra $d"; done
  if [[ -n "$extra" ]]; then warn "nvim also loads config from ${site/#$HOME/~} (${extra# }), which is not in highwind"
  else pass "nvim: nothing config-like outside the highwind config dir"; fi
  nconf="$(find "$DOTFILES_DIR/nvim" -type f -exec stat -f '%m' {} + 2>/dev/null | sort -n | tail -1)"
  [[ -n "$nconf" ]] || nconf="$(find "$DOTFILES_DIR/nvim" -type f -printf '%T@\n' 2>/dev/null | cut -d. -f1 | sort -n | tail -1)"
  stale=0; running=0
  for p in $(pgrep -x nvim); do
    running=$((running+1))
    pstart="$("$PY" -I -c 'import sys,time; print(int(time.mktime(time.strptime(sys.argv[1].strip(), "%a %b %d %H:%M:%S %Y"))))' "$(ps -o lstart= -p "$p")" 2>/dev/null || echo 0)"
    if (( pstart < ${nconf:-0} )); then
      stale=$((stale+1))
      warn "nvim (pid $p, in $(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | sed "s#^$HOME#~#")) started $(when "$pstart"), before its config changed $(when "$nconf"): restart it"
    fi
  done
  if (( running && !stale )); then pass "all $running running nvim instances started after the last config change"; fi
  (( running )) || info "no nvim running"
fi

# zsh: startup files it loads that the repo does not manage.
# ~/.zshrc.local is the deliberate machine-local layer (.zshrc sources it, and it
# can hold secrets), so it is expected to stay out of the repo. So are two more machine-local files:
# ~/.zshenv (PATH and env for non-interactive shells such as agent hooks, which never read .zshrc)
# and ~/.zprofile (brew shellenv, which must run before oh-my-zsh builds completions in .zshrc).
for f in .zshenv .zprofile .zlogin .zlogout; do
  [[ -e "$HOME/$f" ]] || continue
  [[ "$(real "$HOME/$f")" == "$DOTFILES_DIR"/* ]] && continue
  case "$f" in
    .zshenv)   info "~/.zshenv: machine-local env for non-interactive shells, untracked by design" ;;
    .zprofile) info "~/.zprofile: machine-local login setup (brew shellenv before .zshrc), untracked by design" ;;
    *)         warn "zsh loads ~/$f, which is not in highwind" ;;
  esac
done
[[ -e "$HOME/.zshrc.local" ]] && info "~/.zshrc.local: machine-local layer, untracked by design (keep secrets out of the repo)"

# herdr keeps the config it loaded until a reload; its log records both.
if have herdr && [[ -f "$HOME/.config/herdr/herdr-server.log" ]]; then
  hconf="$(mtime "$HOME/.config/herdr/config.toml")"
  hload="$( { grep 'herdr server started' "$HOME/.config/herdr/herdr-server.log"
              grep 'api.request.complete' "$HOME/.config/herdr/herdr-server.log" | grep 'outcome="ok"' | grep 'method="server.reload_config"'
            } | cut -c1-19 | sort | tail -1)"
  if [[ -n "$hload" ]]; then
    hload_t="$("$PY" -I -c 'import sys,calendar,time; print(calendar.timegm(time.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%S")))' "$hload")"
    if (( hload_t < hconf )); then warn "herdr last loaded its config $(when "$hload_t"), before it changed $(when "$hconf"): run herdr server reload-config"
    else pass "herdr loaded its config after the last change"; fi
  fi
fi

# ── herdr ────────────────────────────────────────────────────────────────────
section "herdr"
# The TOML checks below need Python's tomllib (3.11+); macOS's /usr/bin/python3 can be older.
tomlpy=""
for p in "$PY" python3 python3.14 python3.13 python3.12 python3.11; do
  if have "$p" && "$p" -I -c 'import tomllib' 2>/dev/null; then tomlpy="$(command -v "$p")"; break; fi
done
# Python checks print one "PASS|WARN|FAIL|INFO message" per line; anything else is a crash,
# reported once with its last line (the exception).
emit() {
  local l crash=""
  while IFS= read -r l; do
    case "$l" in
      PASS\ *) pass "${l#PASS }" ;; WARN\ *) warn "${l#WARN }" ;;
      FAIL\ *) fail "${l#FAIL }" ;; INFO\ *) info "${l#INFO }" ;;
      ?*) crash="$l" ;;
    esac
  done
  [[ -z "$crash" ]] || fail "$1 check could not run: $crash"
}
# The config dir herdr hands a plugin (HERDR_PLUGIN_CONFIG_DIR), from `herdr plugin list`.
plugin_config_dir() {
  local d
  d="$(echo "$plugins" | awk -v id="$1" '$1 == "-" { f = ($2 == id); next } f && /^  config: / { sub(/^  config: /, ""); print; exit }')"
  echo "${d:-$HOME/.config/herdr/plugins/config/$1}"
}

# The upstream rules the plugin config checks below were copied from, and the commit they were read
# at. When bootstrap.sh pins another commit, the copies may be stale (false failures, or a new rule
# missed): re-read the upstream source at the new pin, update the rules and this commit.
HERDR_PLUS_RULES_AT=f38df3570bea8f7ca71dc1ba11bce3b123d14402
check_rules_pin() {  # <owner/repo> <commit the copied rules match> <label>
  local pin
  pin="$(sed -n "s#^[[:space:]]*herdr plugin install $1 --ref \([0-9a-f]\{7,40\}\).*#\1#p" "$BOOTSTRAP" | head -1)"
  if [[ -z "$pin" ]]; then return
  elif [[ "$2" == "$pin"* ]]; then pass "$3 config rules match the pinned ${pin:0:7}"
  else warn "$3 config rules were copied at ${2:0:7} but bootstrap.sh pins ${pin:0:7}: re-read the upstream rules at the pin, then update them and their *_RULES_AT in validate.sh"; fi
}

# Every plugin_action key binding must name an action herdr lists. `herdr config check` accepts
# any name, so a misspelled, renamed or uninstalled action is a key that silently does nothing.
check_bound_plugin_actions() {  # <config.toml> <`herdr plugin action list` JSON>
  local out w need skipped=""
  # Plugins bootstrap.sh skips on purpose because their build tool is missing (plugin_needs):
  # a key bound to one of them warns, like the install check, and does not fail, but only
  # while that plugin is also not installed (an installed plugin's renamed action still fails).
  for w in $(plugin_names); do
    need="$(plugin_needs "$w")"
    [[ -n "$need" ]] && ! have "$need" && skipped+="$w:$need "
  done
  out="$("$tomlpy" -I - "$1" "$2" "$skipped" 2>&1 <<'PY'
import json, sys, tomllib
with open(sys.argv[1], "rb") as f:
    cfg = tomllib.load(f)
actions = json.loads(sys.argv[2])["result"]["actions"]
listed = {a["plugin_id"] + "." + a["action_id"] for a in actions}
installed = {a["plugin_id"] for a in actions}
skipped = dict(s.split(":", 1) for s in sys.argv[3].split())  # bootstrap grep name -> missing tool
binds = [k for k in cfg.get("keys", {}).get("command", []) if k.get("type") == "plugin_action"]
bad = [k for k in binds if k.get("command") not in listed]
fails = 0
for k in bad:
    pid = str(k.get("command", "")).rsplit(".", 1)[0]
    why = next((t for w, t in skipped.items() if pid == w or pid.endswith("." + w)), None)
    if why and pid not in installed:
        print(f"WARN key {k.get('key')} runs {k.get('command')}: its plugin is not installed because {why} is missing (bootstrap.sh skips it)")
    else:
        fails += 1
        print(f"FAIL key {k.get('key')} runs plugin action {k.get('command')}, which herdr does not list (plugin missing, or action renamed)")
if not fails:
    print(f"PASS {len(binds) - len(bad)} of {len(binds)} plugin_action key bindings name an action herdr lists" + (f"; {len(bad)} wait on a skipped plugin" if bad else ""))
PY
)"
  emit "key bindings" <<<"$out"
}

# herdr-plus loads every template in a directory or none: one bad file empties the whole picker.
# These are its own load rules (config.go, project.go, worktree.go, action.go at the installed pin).
check_herdr_plus_config() {  # <plugin config dir>
  local out
  check_rules_pin cloudmanic/herdr-plus "$HERDR_PLUS_RULES_AT" herdr-plus
  out="$("$tomlpy" -I - "$1" 2>&1 <<'PY'
import glob, os, re, sys, tomllib
root = sys.argv[1]
home = os.path.expanduser("~")
fails = 0

def say(level, msg):
    global fails
    fails += level == "FAIL"
    print(f"{level} herdr-plus: {msg}")

def expand(s):  # herdr-plus expandPath: ~ and $VAR/${VAR}; empty means home
    s = str(s).strip()
    if s in ("", "~"):
        return home
    if s.startswith("~/"):
        s = os.path.join(home, s[2:])
    return os.path.normpath(re.sub(r"\$\{(\w+)\}|\$(\w+)", lambda m: os.environ.get(m.group(1) or m.group(2), ""), s))

def load(path):
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except Exception as e:
        say("FAIL", f"{os.path.relpath(path, root)} does not parse: {e}")

def tab_problem(tabs):  # validateTabs
    if not tabs:
        return "needs at least one [[tabs]] entry"
    for i, t in enumerate(tabs, 1):
        name = str(t.get("name", "")).strip()
        if not name:
            return f"tab {i} has no name"
        panes = t.get("panes", [])
        if panes and str(t.get("command", "")).strip():
            return f"tab {name} sets both command and [[tabs.panes]]"
        if len(panes) > 4:
            return f"tab {name} has {len(panes)} panes (at most 4)"
        for j, p in enumerate(panes[1:], 2):
            if p.get("split", "") not in ("", "down", "right"):
                return f"tab {name} pane {j} has split {p.get('split')!r} (down or right)"
            if not 0 <= p.get("ratio", 0) < 1:
                return f"tab {name} pane {j} has ratio {p.get('ratio')} (between 0 and 1)"

def nested_dirs(tabs, base):  # tab and pane working_dirs, relative ones joined onto base
    for t in tabs:
        for raw in [t.get("working_dir", "")] + [p.get("working_dir", "") for p in t.get("panes", [])]:
            if str(raw).strip():
                d = expand(raw)
                if os.path.isabs(d):
                    yield raw, d
                elif base:
                    yield raw, os.path.join(base, d)

cfg = load(os.path.join(root, "config.toml")) if os.path.exists(os.path.join(root, "config.toml")) else {}
for section in ("projects", "quick_actions"):
    placement = (cfg or {}).get(section, {}).get("placement", "")
    if placement and placement not in ("overlay", "popup", "split", "tab", "zoomed"):
        say("WARN", f"config.toml [{section}] placement {placement!r} is not a herdr placement; the default is used")

counts = {}
for kind, required in (("projects", "name"), ("worktrees", "repo")):
    files = sorted(glob.glob(os.path.join(root, kind, "*.toml")))
    counts[kind] = len(files)
    for path in files:
        rel = os.path.relpath(path, root)
        d = load(path)
        if d is None:
            continue
        if not str(d.get(required, "")).strip():
            say("FAIL", f"{rel}: {required} is required")
            continue
        problem = tab_problem(d.get("tabs", []))
        if problem:
            say("FAIL", f"{rel}: {problem}")
            continue
        base = None
        if kind == "projects" and str(d.get("working_dir", "")).strip() != "{prompt}":
            base = expand(d.get("working_dir", ""))
            if not os.path.isdir(base):
                say("WARN", f"{rel}: working_dir {d.get('working_dir')} does not exist here; herdr-plus will refuse to open it")
                continue
        for raw, path_ in nested_dirs(d.get("tabs", []), base):
            if not os.path.isdir(path_):
                say("WARN", f"{rel}: working_dir {raw} does not exist here; herdr-plus will refuse to open it")

qa = os.path.join(root, "quick-actions")
files = sorted(glob.glob(os.path.join(qa, "*.toml")))
counts["quick actions"] = len(files)
if not os.path.isdir(qa):
    say("INFO", "no quick-actions/ directory; herdr-plus seeds its example actions on first use")
for path in files:
    rel = os.path.relpath(path, root)
    a = load(path)
    if a is None:
        continue
    kind = a.get("type", "") or "command"
    if not str(a.get("name", "")).strip():
        say("FAIL", f"{rel}: name is required")
    elif not str(a.get("command", "")).strip():
        say("FAIL", f"{rel}: command is required")
    elif kind not in ("command", "select", "form"):
        say("FAIL", f"{rel}: unknown type {kind!r} (command, select or form)")
    elif kind == "select" and not str(a.get("options_command", "")).strip() and not any(o.get("label") for o in a.get("options", [])):
        say("FAIL", f"{rel}: a select action needs an option with a label, or options_command")
    elif a["command"].count("{{") != a["command"].count("}}"):
        say("FAIL", f"{rel}: command has unbalanced {{{{ }}}} (it is a Go template)")

if not fails:
    print("PASS herdr-plus loads " + ", ".join(f"{n} {k}" for k, n in counts.items()))
PY
)"
  emit "herdr-plus" <<<"$out"
}

# Install root herdr runs a plugin from, from `herdr plugin list --json`: empty when the plugin is not
# installed, "-" when it is installed but herdr gives no plugin_root, "?" when the JSON cannot be read.
plugin_root() {  # <plugin list JSON> <plugin id>
  "$PY" -I -c 'import json, sys
for p in json.loads(sys.argv[1])["result"]["plugins"]:
    if p.get("plugin_id") == sys.argv[2]:
        print(p.get("plugin_root") or "-"); break' "$1" "$2" 2>/dev/null || echo "?"
}
# Run <check fn> on an installed plugin's root; a plugin that is installed but has no usable root fails
# (it must not read as "not installed"). Not installed is reported by the install check above.
check_plugin_binary() {  # <plugin list JSON> <plugin id> <check fn>
  local root
  root="$(plugin_root "$1" "$2")"
  case "$root" in
    "") ;;
    "?") fail "plugin $2: could not read herdr plugin list --json; binary not checked" ;;
    "-") fail "plugin $2 installed but herdr reports no plugin_root; binary not checked" ;;
    *) "$3" "$root" ;;
  esac
}

# A plugin bootstrap.sh installs with --ref was reviewed at that commit; `herdr plugin update`
# moves it past the review. The pin logic is herdr-plugins' own (its `check` is offline and reads
# the pins from the bootstrap.sh it is linked from). Not installed is skipped: the install check
# above reports that. Drift is a warning, not a failure: the plugin still works, only off its
# reviewed commit, and `herdr plugin update` or a hand reinstall can cause it on purpose; failing
# would block the whole validate on a state the user may have chosen.
check_plugin_pins() {
  local out rc kind repo rest got
  if ! have herdr-plugins; then fail "herdr-plugins not on PATH (stow the herdr package); plugin pins not checked"; return; fi
  out="$(herdr-plugins check 2>&1)"; rc=$?
  while read -r kind repo rest; do
    case "$kind" in
      ok) pass "plugin $repo at its pinned commit ${rest##* }" ;;
      drift) got="${rest#at }"; got="${got%%,*}"
        warn "plugin $repo is at $got, bootstrap.sh pins ${rest##* }: the user runs herdr-plugins update ${repo#*/} in a terminal to reinstall it at the pin (it then offers newer commits after a review)" ;;
    esac
  done <<<"$out"
  if (( rc > 1 )); then fail "herdr-plugins check: $(echo "$out" | tail -1)"; fi
}

# The tool bootstrap.sh requires before installing a plugin: an `if command -v <tool>` right after
# that plugin's `grep -q <name>` line (fingers: cargo, herdr-plus: go). Both line shapes the
# plugin-name sed below accepts: `if ! herdr plugin list ... | grep -q <name>; then` and
# `if ! grep -q <name> <<<"$herdr_plugins"; then`.
plugin_needs() {  # <name from the grep -q>
  # Scans the plugin's block from its grep line to its `herdr plugin install` line, the same span
  # herdr-plugins' needs_tool reads, so comments between them do not change the answer.
  awk -v w="$1" 'f && /if command -v [A-Za-z0-9_.-]+/ { match($0, /if command -v [A-Za-z0-9_.-]+/); print substr($0, RSTART + 14, RLENGTH - 14); exit }
    f && /^[ \t]*herdr plugin install / { exit }
    /^[ \t]*if ! herdr plugin list/ && index($0, "grep -q " w "; then") { f = 1 }
    /^[ \t]*if ! grep -q / && index($0, "grep -q " w " <<<\"$herdr_plugins\"; then") { f = 1 }' "$BOOTSTRAP"
}

# The plugin names bootstrap.sh tests for, in either line shape it has used. Empty means the shape
# changed again and every per-plugin check would silently do nothing, so callers fail on it.
plugin_names() {
  sed -n -e 's/.*herdr plugin list.*grep -q \([a-z][a-z0-9.-]*\); then$/\1/p' \
         -e 's/.*grep -q \([a-z][a-z0-9.-]*\) <<<"\$herdr_plugins"; then$/\1/p' "$BOOTSTRAP"
}

# herdr-plugins (stowed to ~/.local/bin) must be the one on PATH and run from this checkout.
check_herdr_plugins_cmd() {
  local hp out
  if ! hp="$(command -v herdr-plugins)"; then fail "herdr-plugins not on PATH (stow the herdr package; is ~/.local/bin on PATH?)"; return; fi
  if [[ "$(real "$hp")" != "$(real "$DOTFILES_DIR/herdr/.local/bin/herdr-plugins")" ]]; then
    fail "herdr-plugins on PATH ($hp) is not this checkout's (stow the herdr package)"; return; fi
  out="$(herdr-plugins help 2>&1)"
  local from; from="$(echo "$out" | sed -n 's/^Pins are read from //p')"
  # CLAUDE.md sends agents to the help for how to read review output, so those rules must print, to their last line.
  if ! echo "$out" | grep -q '^Reading review output' || ! echo "$out" | grep -q 'by path to check that worktree'; then fail "herdr-plugins help does not print its 'Reading review output' rules (header cut?)"
  elif [[ -n "$from" && "$(real "$from")" == "$(real "$BOOTSTRAP")" ]]; then pass "herdr-plugins on PATH, reads pins from this checkout"
  else fail "herdr-plugins help: $(echo "${out:-no output}" | tail -1)"; fi
}

# herdr-fingers (trial) builds with cargo at install; without the binary prefix+f does nothing.
# `scan` reads a screen dump on stdin and prints the hints; with HERDR_PLUGIN_CONFIG_DIR unset it
# uses built-in defaults and writes nothing.
check_fingers_binary() {  # <plugin root>
  local bin="$1/target/release/herdr-fingers" out
  if [[ ! -x "$bin" ]]; then fail "herdr-fingers: $bin missing (the cargo build failed or never ran; reinstall the plugin)"; return; fi
  out="$("$bin" --version 2>&1)"
  if [[ "$out" != herdr-fingers* ]]; then fail "herdr-fingers: $bin does not run: $(echo "${out:-no output}" | head -1)"; return; fi
  out="$(echo "commit 2d9fc997ce1a95976b975da758dccc7b6e011336" | env -u HERDR_PLUGIN_CONFIG_DIR "$bin" scan --width 80 2>&1)"
  if [[ "$out" == *2d9fc997ce1a* ]]; then pass "herdr-fingers: binary runs and hints a SHA (${out%%$'\t'*})"
  else fail "herdr-fingers: scan found no hint in a line holding a SHA: $(echo "${out:-no output}" | head -1)"; fi
}

# popup and pane key bindings run a command line, which `herdr config check` does not look at: a
# command missing from PATH is a key that opens an error. Checks each one's first word (after `exec`),
# with $VAR and ~ expanded, against this shell's PATH.
check_bound_commands() {  # <config.toml>
  local out
  out="$("$tomlpy" -I - "$1" 2>&1 <<'PY'
import os, shlex, shutil, sys, tomllib
with open(sys.argv[1], "rb") as f:
    cfg = tomllib.load(f)
binds = [k for k in cfg.get("keys", {}).get("command", []) if k.get("type") in ("popup", "pane")]
fails = checked = 0
for k in binds:
    try:
        words = shlex.split(str(k.get("command", "")))
    except ValueError:
        words = []
    if words[:1] == ["exec"]:
        words = words[1:]
    word = os.path.expanduser(os.path.expandvars(words[0])) if words else ""
    if "$" in word:
        print(f"INFO key {k.get('key')} runs {words[0]}, which names an unset variable here; not checked")
        continue
    checked += 1
    if not word or not shutil.which(word):
        fails += 1
        print(f"FAIL key {k.get('key')} ({k.get('type')}) runs {word or 'nothing'}, which is not on PATH")
if not fails:
    print(f"PASS {checked} popup and pane key bindings run commands on PATH")
PY
)"
  emit "bound commands" <<<"$out"
}

# herdr-plugins takes the repo from HIGHWIND_DIR (the Nix build sets it), and sync refuses outside a
# sandbox. This runs the checkout's copy, which the Stow check ties to the live one (on Nix the live one is
# a wrapper that sets HIGHWIND_DIR itself). A fake herdr comes first on PATH, so even a sync that failed
# to refuse would reach only the fake.
check_herdr_plugins_env() {  # <herdr-plugins>
  local t out rc ph mode
  t="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-validate-hp.XXXXXX")"; mkdir -p "$t/repo" "$t/bin" "$t/home"
  cp "$BOOTSTRAP" "$t/repo/bootstrap.sh"
  printf '#!/bin/sh\necho "$*" >>"%s/herdr-called"\nexit 1\n' "$t" >"$t/bin/herdr"; chmod +x "$t/bin/herdr"
  out="$(HIGHWIND_DIR="$t/repo" "$1" help 2>&1)"
  ph="$("$PY" -I -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
  if [[ "$(real "$(sed -n 's/^Pins are read from //p' <<<"$out")")" != "$(real "$t/repo/bootstrap.sh")" ]]; then
    fail "herdr-plugins ignores HIGHWIND_DIR: help says $(tail -1 <<<"${out:-nothing}")"
  else
    # Each run trips one guard only: a throwaway HOME without HIGHWIND_SANDBOX, then the real HOME with it.
    for mode in "HIGHWIND_SANDBOX unset" "HOME is the real home"; do
      rc=0
      if [[ "$mode" == HIGHWIND* ]]; then out="$(env -u HIGHWIND_SANDBOX HOME="$t/home" PATH="$t/bin:$PATH" HIGHWIND_DIR="$t/repo" "$1" sync 2>&1)" || rc=$?
      else out="$(HIGHWIND_SANDBOX=1 HOME="$ph" PATH="$t/bin:$PATH" HIGHWIND_DIR="$t/repo" "$1" sync 2>&1)" || rc=$?; fi
      if (( rc == 0 )) || [[ -e "$t/herdr-called" || "$out" != *"sync refused"* ]]; then
        fail "herdr-plugins sync did not refuse ($mode, exit $rc): $(tail -1 <<<"${out:-no output}")"; mode=""; break
      fi
    done
    [[ -z "$mode" ]] || pass "herdr-plugins reads HIGHWIND_DIR; sync refuses without HIGHWIND_SANDBOX=1 and in the real HOME"
  fi
  rm -rf "$t"
}
# On a Nix-managed home the plugins are Nix builds, which herdr lists as local links with no commit;
# herdr-plugins reads the commit from the .highwind-pin file each build writes into its root. A fake herdr
# lists one such plugin at bootstrap.sh's first pin, then at another commit: check must report it at its pin,
# then off it (exit 1). Runs the checkout's copy, as above.
check_herdr_plugins_nix() {  # <herdr-plugins>
  local t repo pin out rc=0
  read -r repo pin < <(sed -n 's/^[[:space:]]*herdr plugin install \([^ ]*\) --ref \([0-9a-f]\{7,40\}\).*/\1 \2/p' "$BOOTSTRAP" | head -1)
  if [[ -z "${pin:-}" ]]; then fail "herdr-plugins and Nix-built plugins: no pinned plugin in bootstrap.sh to test with"; return; fi
  t="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-validate-hn.XXXXXX")"; mkdir -p "$t/repo" "$t/bin" "$t/plugin"
  cp "$BOOTSTRAP" "$t/repo/bootstrap.sh"
  printf '#!/bin/sh\ncat "%s/list.json"\n' "$t" >"$t/bin/herdr"; chmod +x "$t/bin/herdr"
  printf '{"result":{"plugins":[{"plugin_id":"nix-built","plugin_root":"%s","source":{"kind":"local"}}]}}\n' "$t/plugin" >"$t/list.json"
  echo "$repo $pin" >"$t/plugin/.highwind-pin"
  out="$(PATH="$t/bin:$PATH" HIGHWIND_DIR="$t/repo" "$1" check 2>&1)" || rc=$?
  if (( rc != 0 )) || ! grep -qx "ok $repo at its pin ${pin:0:7}" <<<"$out"; then
    fail "herdr-plugins check does not see a Nix-built plugin at its pin (exit $rc): $(grep -F "$repo" <<<"$out" | head -1)"
  else
    echo "$repo 0000000000000000000000000000000000000000" >"$t/plugin/.highwind-pin"
    rc=0; out="$(PATH="$t/bin:$PATH" HIGHWIND_DIR="$t/repo" "$1" check 2>&1)" || rc=$?
    if (( rc == 1 )) && grep -qx "drift $repo at 0000000, pinned ${pin:0:7}" <<<"$out"; then
      pass "herdr-plugins check reads a Nix-built plugin's commit (.highwind-pin): at its pin, and off it"
    else fail "herdr-plugins check does not see a Nix-built plugin off its pin (exit $rc): $(grep -F "$repo" <<<"$out" | head -1)"; fi
  fi
  rm -rf "$t"
}
check_herdr_plugins_cmd
check_herdr_plugins_env "$DOTFILES_DIR/herdr/.local/bin/herdr-plugins"
check_herdr_plugins_nix "$DOTFILES_DIR/herdr/.local/bin/herdr-plugins"
if have herdr; then
  out="$(herdr config check 2>&1)"
  if echo "$out" | grep -q 'config: ok'; then pass "config.toml valid"; else fail "config.toml: $(echo "$out" | tail -2 | tr '\n' ' ')"; fi
  [[ -n "$tomlpy" ]] && check_bound_commands "$HOME/.config/herdr/config.toml"
  # The ZOOM pill is a tab_bar_right entry; "herdr loaded its config" above says whether it is live.
  if grep -E '^[[:space:]]*tab_bar_right[[:space:]]*=' "$HOME/.config/herdr/config.toml" 2>/dev/null | grep -q 'type = "zoom"'; then
    pass "zoom indicator in the tab bar"
  else fail "no zoom indicator: tab_bar_right in ~/.config/herdr/config.toml has no { type = \"zoom\" } entry"; fi
  # Claude login warning: wired into the tab bar, runs, and (if it prints) the login needs renewing now.
  lw="$HOME/.local/bin/herdr-login-warning"
  if ! grep -E '^[[:space:]]*tab_bar_right[[:space:]]*=' "$HOME/.config/herdr/config.toml" 2>/dev/null | grep -q 'herdr-login-warning'; then
    fail "no Claude login warning: tab_bar_right in ~/.config/herdr/config.toml does not run herdr-login-warning"
  elif ! [[ -x "$lw" ]] || ! msg="$("$lw" 2>&1)"; then fail "herdr-login-warning missing or failing ($lw)"
  elif [[ -n "$msg" ]]; then warn "tab bar shows: $msg"
  else pass "Claude login warning wired into the tab bar (login more than a day from expiry)"; fi
  if herdr workspace list >/dev/null 2>&1; then
    pass "server running"
    plugins="$(herdr plugin list 2>/dev/null)"
    names="$(plugin_names)"
    npins="$(grep -c '^[[:space:]]*herdr plugin install [^ ]* --ref ' "$BOOTSTRAP" || true)"
    if [[ -z "$names" ]]; then fail "no herdr plugin found in bootstrap.sh's install checks (did their line shape change? see plugin_names)"
    elif (( $(wc -w <<<"$names") != npins )); then
      fail "bootstrap.sh pins $npins herdr plugins but plugin_names finds $(wc -w <<<"$names") ($(echo $names)): a plugin's install check has a line shape plugin_names does not read"; fi
    for want in $names; do
      line="$(echo "$plugins" | grep -E "^- [^ ]*$want " || true)"
      # bootstrap skips a plugin whose build tool is missing, so missing it then is expected
      need="$(plugin_needs "$want")"
      if [[ -z "$line" && -n "$need" ]] && ! have "$need"; then warn "plugin $want not installed (bootstrap.sh skips it without $need on PATH; install $need, then ./bootstrap.sh)"
      elif [[ -z "$line" ]]; then fail "plugin $want not installed (run ./bootstrap.sh)"
      elif echo "$line" | grep -q ' enabled '; then pass "plugin $want enabled"
      else fail "plugin $want installed but disabled"; fi
    done
    pjson="$(herdr plugin list --json 2>/dev/null)"
    check_plugin_pins
    check_plugin_binary "$pjson" nathan-poncet.herdr-fingers check_fingers_binary
    if [[ -z "$tomlpy" ]]; then warn "no Python with tomllib (3.11+); key binding and plugin config checks skipped"
    else
      check_bound_plugin_actions "$HOME/.config/herdr/config.toml" "$(herdr plugin action list 2>/dev/null)"
      if echo "$plugins" | grep -q '^- cloudmanic.herdr-plus '; then check_herdr_plus_config "$(plugin_config_dir cloudmanic.herdr-plus)"; fi
    fi
    out="$(herdr integration status 2>&1 | grep -i claude || true)"
    if [[ ! -d "$HOME/.claude" ]]; then info "Claude Code not set up (no ~/.claude); integration not checked"
    elif [[ -z "$out" ]] || echo "$out" | grep -qi 'not installed'; then fail "Claude integration not installed (herdr integration install claude)"
    elif echo "$out" | grep -qi 'outdated'; then warn "Claude integration outdated (herdr integration install claude)"
    else pass "Claude integration current"; fi
  else warn "server not running; plugins and integration not checked"; fi
else info "herdr not installed"; fi

# ── tuicr ────────────────────────────────────────────────────────────────────
# prefix+alt+r opens `tuicr -w`, the uncommitted diff (jj: @), in git and jj repos. tuicr keeps review
# sessions in its data dir (macOS ~/Library/Application Support/tuicr, Linux $XDG_DATA_HOME/tuicr or
# ~/.local/share/tuicr), and even `review list` takes a lock file there, so each run below gets a
# throwaway HOME and XDG dirs inside one mktemp dir, removed afterwards. The repos are throwaway too.
section "tuicr"
# Runs tuicr in <dir> under the throwaway HOME: `review list` (what the agent skill reads), then
# `tuicr -w` with no terminal (a new session, stdin /dev/null). tuicr finds the repo and its diff,
# prints `tuicr-session: <repo dir name>@...` on stderr, then exits when it cannot open /dev/tty; a
# directory it does not see as a repo gets "Make sure you're in a git, jujutsu, or mercurial repository".
check_tuicr_repo() {  # <label> <repo dir with an uncommitted change> <throwaway HOME>
  local out h="$3"
  local tenv=(env HOME="$h" XDG_DATA_HOME="$h/.local/share" XDG_CONFIG_HOME="$h/.config"
              XDG_STATE_HOME="$h/.local/state" XDG_CACHE_HOME="$h/.cache")
  out="$(cd "$2" && "${tenv[@]}" tuicr review list --repo . 2>&1)"
  if [[ "$out" != \[* ]]; then fail "tuicr review list in a throwaway $1 repo: $(head -1 <<<"${out:-no output}")"; return; fi
  out="$(cd "$2" && "${tenv[@]}" "$PY" -I -c 'import subprocess, sys
try:
    r = subprocess.run(sys.argv[1:], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                       text=True, timeout=20, start_new_session=True)
    sys.stdout.write(r.stderr)
except subprocess.TimeoutExpired:
    print("timed out after 20s")
except OSError as e:
    print(e)' tuicr -w --no-update-check 2>&1)"
  if grep -q "^tuicr-session: $(basename "$2")@" <<<"$out"; then pass "tuicr reviews a throwaway $1 repo ($(sed -n 's/^tuicr-session: //p' <<<"$out" | head -1))"
  elif grep -q "Make sure you're in a" <<<"$out"; then fail "tuicr -w does not see a throwaway $1 repo as a repository"
  else fail "tuicr -w in a throwaway $1 repo announced no review session: $(head -1 <<<"${out:-no output}")"; fi
}
if ! have tuicr; then fail "tuicr not on PATH, so prefix+alt+r opens an error (brew install tuicr, or ./bootstrap.sh on Linux)"
elif ! v="$(tuicr --version 2>&1)" || [[ "$v" != tuicr* ]]; then fail "tuicr --version failed: $(head -1 <<<"${v:-no output}")"
else
  pass "tuicr runs ($v)"
  tt="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-validate-tuicr.XXXXXX")"
  mkdir -p "$tt/home" "$tt/git-repo"
  # git with no global or system config: no hooks, templates or signing from the user's setup.
  if ( cd "$tt/git-repo" && export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 &&
       git init -q . && echo a >f && git add f && git -c user.name=v -c user.email=v@v commit -qm init && echo b >>f ) >/dev/null 2>&1
  then check_tuicr_repo git "$tt/git-repo" "$tt/home"
  else fail "tuicr not checked in git: could not make a throwaway git repo"; fi
  if have jj; then
    mkdir -p "$tt/jj-repo"
    # --no-colocate: a jj repo with no .git, like ~/aios/lib (jj git init colocates by default)
    ( cd "$tt/jj-repo" && jj git init --no-colocate . && echo a >f ) >/dev/null 2>&1
    if [[ ! -d "$tt/jj-repo/.jj" ]]; then fail "tuicr not checked in jj: could not make a throwaway jj repo"
    elif [[ -e "$tt/jj-repo/.git" ]]; then fail "tuicr not checked in jj: the throwaway jj repo has a .git, so it would not test a jj-only repo"
    else check_tuicr_repo "jj (no .git)" "$tt/jj-repo" "$tt/home"; fi
  else info "jj not installed; tuicr in jj repos not checked"; fi
  [[ -d "$tt" ]] && rm -rf "$tt"
fi
# The agent skill (upstream skills/tuicr) is how an agent reads the review: `tuicr review comments`.
# A one-time hand step, so missing it warns.
if [[ -f "$HOME/.claude/skills/tuicr/SKILL.md" ]]; then pass "tuicr agent skill installed (~/.claude/skills/tuicr)"
else warn "tuicr agent skill not installed, so agents do not know to read review comments: run npx skills add agavra/tuicr"; fi

# ── herdr-summarizer (opt-in) ────────────────────────────────────────────────
section "herdr-summarizer (opt-in)"
summ="$HOME/.local/bin/herdr-summarize"
for f in "$summ" "$HOME/.local/bin/herdr-recent"; do
  if [[ -x "$f" ]]; then pass "$(basename "$f") executable"; else fail "$(basename "$f") missing or not executable"; fi
done
if [[ -x "$summ" ]]; then
  if "$PY" -I -c 'import sys; p=sys.argv[1]; compile(open(p).read(), p, "exec")' "$summ" 2>/dev/null \
     && "$summ" help >/dev/null 2>&1; then pass "herdr-summarize compiles and runs"
  else fail "herdr-summarize does not compile or run (try: herdr-summarize help)"; fi
fi
# On NixOS herdr, claude and jj are in none of herdr-summarize's fixed directories, only on PATH. Loads the
# checkout's copy (the Stow check ties the live one to it; on Nix the live one is a wrapper) and asks it for
# a command that exists only in a throwaway directory at the end of PATH.
check_summarize_path() {  # <herdr-summarize>
  local t out
  t="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-validate-path.XXXXXX")"
  printf '#!/bin/sh\n' >"$t/dotfiles-validate-probe"; chmod +x "$t/dotfiles-validate-probe"
  out="$(PATH="$PATH:$t" "$PY" -I -c 'import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("herdr_summarize", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("herdr_summarize", loader))
loader.exec_module(m)
print(m.which("dotfiles-validate-probe") or "not found")' "$1" 2>&1)"
  if [[ "$out" == "$t/dotfiles-validate-probe" ]]; then pass "herdr-summarize finds commands on PATH after its fixed directories"
  else fail "herdr-summarize does not look on PATH for herdr, claude and jj (NixOS keeps them there): $(tail -1 <<<"${out:-no output}")"; fi
  rm -rf "$t"
}
check_summarize_path "$DOTFILES_DIR/herdr/.local/bin/herdr-summarize"
# $jj_status: what the summarizer reports for a throwaway jj repo (made and removed in
# $TMPDIR, nothing else touched) and for a plain directory.
if [[ -x "$summ" ]] && have jj; then
  jt="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-validate-jj.XXXXXX")"
  plain="$("$summ" jj-status "$jt" 2>&1)"
  ( cd "$jt" && jj git init . && echo x >f && jj status ) >/dev/null 2>&1
  dirty="$("$summ" jj-status "$jt" 2>&1)"
  ( cd "$jt" && jj bookmark create t -r @ ) >/dev/null 2>&1
  mkdir -p "$jt/sub"
  named="$("$summ" jj-status "$jt/sub" 2>&1)"
  [[ -d "$jt" ]] && rm -rf "$jt"
  brief() { head -1 <<<"$1" | sed 's/^.* jj [^ ]*validate-jj[^:]*: //' | cut -c1-90; }  # first line, minus the log prefix
  plain="$(brief "$plain")"; dirty="$(brief "$dirty")"; named="$(brief "$named")"
  if [[ -n "$plain" ]]; then fail "herdr-summarize jj-status: a plain directory gave '$plain', expected nothing"
  elif [[ ! "$dirty" =~ ^[a-z]{8}\*$ || "$named" != "t*" ]]; then
    fail "herdr-summarize jj-status: got '$dirty' and '$named' from a test repo, expected '<change id>*' and 't*' (jj template broken?)"
  else pass "herdr-summarize computes \$jj_status (test repo: $dirty, then $named)"; fi
elif ! have jj; then info "jj not installed; \$jj_status not checked"; fi
hcfg="$HOME/.config/herdr/config.toml"
if [[ -f "$hcfg" ]]; then
  if awk '/^\[/ { s = ($0 == "[ui.sidebar.spaces]") } s && /^rows *=/' "$hcfg" | grep -q '"\$jj_status"'; then
    pass "herdr sidebar spaces row shows \$jj_status"
  else fail "herdr sidebar: [ui.sidebar.spaces] rows in ~/.config/herdr/config.toml lack \$jj_status"; fi
fi
if [[ "$OS" != "Darwin" ]]; then info "launchd: macOS only (old launchd job not checked)"
elif launchctl print "gui/$(id -u)/dev.dotfiles.herdr-summarizer" >/dev/null 2>&1; then
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
    failed="$(echo "$logs" | "$PY" -I -c 'import json,sys
try: logs=json.load(sys.stdin)["result"]["logs"]
except Exception: logs=[]
bad=[l for l in logs if l.get("status")!="succeeded"]
print(len(bad), len(logs))' 2>/dev/null || echo "0 0")"
    read -r nbad nall <<<"$failed"
    if (( nbad == 0 )); then pass "last $nall plugin hook runs succeeded"
    else fail "$nbad of the last $nall plugin hook runs failed (herdr plugin log list --plugin herdr-summarizer)"; fi
    [[ -e "$HOME/.local/state/herdr-summarizer/only-sessions" ]] && warn "test guard present: the plugin ignores your sessions (delete ~/.local/state/herdr-summarizer/only-sessions)"
    wlog="$HOME/.local/state/herdr-summarizer/worker.log"
    # Only the last day counts: the log holds nothing but errors, so any old line would warn forever.
    # Lines start "YYYY-MM-DD HH:MM:SS", which compares correctly as text; untimestamped lines (a
    # traceback) belong to the timestamped line above them.
    since="$("$PY" -I -c 'import time; print(time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - 86400)))')"
    recent="$( [[ -s "$wlog" ]] && awk -v c="$since" '/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] / { keep = (substr($0, 1, 19) >= c) } keep' "$wlog" \
               | grep -E 'Traceback|Error|error|failed' || true)"
    if [[ -n "$recent" ]]; then
      warn "worker logged $(wc -l <<<"$recent" | tr -d ' ') error(s) in the last day: $(tail -1 <<<"$recent" | cut -c1-120)"
    else pass "worker log: no errors in the last day"; fi
    # $jj_status is live: each space whose first pane (its home) is in a jj repo carries it.
    if have jj && [[ -x "$summ" ]]; then
      hrc=0
      homes="$("$PY" -I -c 'import json, subprocess, sys
def h(*a):
    r = subprocess.run(["herdr"] + list(a), capture_output=True, text=True, timeout=10)
    if r.returncode != 0:
        raise RuntimeError("herdr %s exited %d" % (" ".join(a[:2]), r.returncode))
    return json.loads(r.stdout)["result"]
try:
    for w in h("workspace", "list")["workspaces"]:
        panes = h("pane", "list", "--workspace", w["workspace_id"])["panes"]
        if not panes:
            continue
        order = lambda p: (len(p["pane_id"].split(":")[-1]), p["pane_id"].split(":")[-1])
        first = min(panes, key=order)
        print("\x1f".join([w.get("label") or w["workspace_id"], first.get("cwd") or "",
                            (w.get("tokens") or {}).get("jj_status", "")]))
except Exception as e:
    print("ERR %s: %s" % (type(e).__name__, e))
    sys.exit(1)' 2>&1)" || hrc=$?
      njj=0; missing=""; broken=""
      while IFS=$'\x1f' read -r label dir token; do
        [[ -n "$dir" ]] || continue
        if ! want="$("$summ" jj-status "$dir" 2>/dev/null)"; then broken+=" $label"; continue; fi
        [[ -n "$want" ]] || continue
        njj=$((njj+1))
        [[ -n "$token" ]] || missing+=" $label"
      done <<<"$homes"
      [[ -n "$broken" ]] && warn "jj failed reading the home of space(s):$broken (try: herdr-summarize jj-status DIR)"
      if (( hrc != 0 )); then fail "\$jj_status not checked live: could not read the spaces from herdr (${homes#ERR })"
      elif (( njj == 0 )); then info "no open space has its first pane in a jj repo; \$jj_status not checked live"
      elif [[ -n "$missing" ]]; then warn "\$jj_status missing on jj space(s):$missing (no summarizer pass since they opened? focus a pane there)"
      else pass "\$jj_status shown on all $njj jj space(s)"; fi
    fi
  fi
fi

# ── summary ──────────────────────────────────────────────────────────────────
printf '\n%s%d passed%s · %s%d warnings%s · %s%d failed%s\n' "$G" "$PASSES" "$N" "$Y" "$WARNS" "$N" "$R" "$FAILS" "$N"
(( FAILS == 0 ))
