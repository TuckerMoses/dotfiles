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
  done < <(find "$DOTFILES_DIR/$pkg" \( -type f -o -type l \) ! -name '.DS_Store' -print0)
  (( bad )) || pass "$pkg ($count file$([[ $count == 1 ]] || echo s))"
done

# Configs must work for any user and any home directory: no literal home paths.
hard="$(git -C "$DOTFILES_DIR" grep -nIE '(/Users|/home)/[A-Za-z0-9._-]+' -- . ':!docs' ':!CHANGELOG.md' ':!validate.sh' || true)"
if [[ -z "$hard" ]]; then pass "no hardcoded home directory paths in tracked files"
else fail "hardcoded home directory path (use \$HOME, ~ or a relative path): $(echo "$hard" | cut -d: -f1,2 | tr '\n' ' ')"; fi

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
# ~/.zshrc.local is the deliberate machine-local layer (.zshrc sources it, and it
# can hold secrets), so it is expected to stay out of the repo.
for f in .zshenv .zprofile .zlogin .zlogout; do
  [[ -e "$HOME/$f" ]] || continue
  [[ "$(real "$HOME/$f")" == "$DOTFILES_DIR"/* ]] && continue
  warn "zsh loads ~/$f, which is not in dotfiles"
done
[[ -e "$HOME/.zshrc.local" ]] && info "~/.zshrc.local: machine-local layer, untracked by design (keep secrets out of the repo)"

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
# The TOML checks below need Python's tomllib (3.11+); macOS's /usr/bin/python3 can be older.
tomlpy=""
for p in /usr/bin/python3 python3 python3.14 python3.13 python3.12 python3.11; do
  if have "$p" && "$p" -c 'import tomllib' 2>/dev/null; then tomlpy="$(command -v "$p")"; break; fi
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

# Every plugin_action key binding must name an action herdr lists. `herdr config check` accepts
# any name, so a misspelled, renamed or uninstalled action is a key that silently does nothing.
check_bound_plugin_actions() {  # <config.toml> <`herdr plugin action list` JSON>
  local out
  out="$("$tomlpy" - "$1" "$2" 2>&1 <<'PY'
import json, sys, tomllib
with open(sys.argv[1], "rb") as f:
    cfg = tomllib.load(f)
listed = {a["plugin_id"] + "." + a["action_id"] for a in json.loads(sys.argv[2])["result"]["actions"]}
binds = [k for k in cfg.get("keys", {}).get("command", []) if k.get("type") == "plugin_action"]
bad = [k for k in binds if k.get("command") not in listed]
for k in bad:
    print(f"FAIL key {k.get('key')} runs plugin action {k.get('command')}, which herdr does not list (plugin missing, or action renamed)")
if not bad:
    print(f"PASS all {len(binds)} plugin_action key bindings name an action herdr lists")
PY
)"
  emit "key bindings" <<<"$out"
}

# herdr-plus loads every template in a directory or none: one bad file empties the whole picker.
# These are its own load rules (config.go, project.go, worktree.go, action.go at the installed pin).
check_herdr_plus_config() {  # <plugin config dir>
  local out
  out="$("$tomlpy" - "$1" 2>&1 <<'PY'
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

# Install root herdr runs a plugin from, from `herdr plugin list --json`; empty when not installed.
plugin_root() {  # <plugin list JSON> <plugin id>
  /usr/bin/python3 -c 'import json, sys
for p in json.loads(sys.argv[1])["result"]["plugins"]:
    if p.get("plugin_id") == sys.argv[2]: print(p.get("plugin_root", ""))' "$1" "$2" 2>/dev/null
}

# A plugin bootstrap.sh installs with --ref was reviewed at that commit; `herdr plugin update`
# moves it past the review. Not installed is skipped: the install check above reports that.
check_plugin_pins() {  # <plugin list JSON>
  local repo ref got
  while read -r repo ref; do
    got="$(/usr/bin/python3 -c 'import json, sys
for p in json.loads(sys.argv[1])["result"]["plugins"]:
    s = p.get("source", {})
    if "%s/%s" % (s.get("owner"), s.get("repo")) == sys.argv[2]: print(s.get("resolved_commit", "?"))' "$1" "$repo" 2>/dev/null)"
    [[ -z "$got" ]] && continue
    if [[ "$got" == "$ref"* ]]; then pass "plugin $repo at its pinned commit ${ref:0:7}"
    else warn "plugin $repo is at ${got:0:7}, bootstrap.sh pins ${ref:0:7}: review the new commits and bump the pin, or reinstall at the pin"; fi
  done < <(sed -n 's/.*herdr plugin install \([^ ]*\) --ref \([0-9a-f]\{7,40\}\).*/\1 \2/p' "$BOOTSTRAP")
}

# reviewr: its build step downloads a release binary, so a failed download leaves the key dead.
# `--action <unknown>` makes the binary answer without reading config, herdr or the repo.
check_reviewr_binary() {  # <plugin root>
  local bin="$1/bin/herdr-reviewr" out
  if [[ ! -x "$bin" ]]; then fail "reviewr: $bin missing (its build step's download failed; reinstall the plugin)"; return; fi
  out="$(env -u HERDR_REVIEW_LOG "$bin" --action validate-probe 2>&1)"
  if [[ "$out" == *"unknown action"* ]]; then pass "reviewr: binary runs"
  else fail "reviewr: $bin does not run as reviewr: $(echo "${out:-no output}" | head -1)"; fi
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

# reviewr rejects the whole config.toml (and blocks its pane) on an unknown key or a bad value.
# Keys and values are reviewr's own (src/config.rs, src/theme.rs at the pin in bootstrap.sh).
check_reviewr_config() {  # <config.toml>
  local out
  out="$("$tomlpy" - "$1" 2>&1 <<'PY'
import os, sys, tomllib
path = sys.argv[1]
if not os.path.exists(path):
    print(f"FAIL reviewr: {path} missing (stow the herdr package)"); sys.exit()
try:
    with open(path, "rb") as f:
        cfg = tomllib.load(f)
except Exception as e:
    print(f"FAIL reviewr: config.toml does not parse: {e}"); sys.exit()
keys = {"theme", "default_scope", "markdown_view", "diff_view", "navigator_position", "toggle_placement",
        "toggle_direction", "auto_open", "follow_file_across_tabs", "scrolloff", "github_host", "gitlab_host",
        "azure_devops_host", "editor", "url_opener", "review_prefix", "keybindings"}
themes = {"catppuccin", "catppuccin-frappe", "catppuccin-macchiato", "catppuccin-latte", "tokyo-night",
          "tokyo-night-day", "dracula", "nord", "gruvbox", "gruvbox-light", "one-dark", "one-light", "solarized",
          "solarized-light", "monokai", "rose-pine", "rose-pine-dawn", "ayu", "everforest", "github-light"}
values = {"theme": themes, "default_scope": {"uncommitted", "branch", "last-turn"},
          "toggle_placement": {"split", "overlay", "zoomed", "tab"}, "toggle_direction": {"right", "down"}}
bad = [f"unknown key {k}" for k in cfg if k not in keys]
bad += [f"{k} = {cfg[k]!r} (one of {', '.join(sorted(v))})" for k, v in values.items() if k in cfg and cfg[k] not in v]
if cfg.get("auto_open", True) is not False:
    bad.append("auto_open must be false (a reviewr pane would open in every new worktree)")
for b in bad:
    print(f"FAIL reviewr: config.toml: {b}")
if not bad:
    print("PASS reviewr: config.toml valid, auto_open off")
PY
)"
  emit "reviewr config" <<<"$out"
}

if have herdr; then
  out="$(herdr config check 2>&1)"
  if echo "$out" | grep -q 'config: ok'; then pass "config.toml valid"; else fail "config.toml: $(echo "$out" | tail -2 | tr '\n' ' ')"; fi
  if herdr workspace list >/dev/null 2>&1; then
    pass "server running"
    plugins="$(herdr plugin list 2>/dev/null)"
    for want in $(sed -n 's/.*herdr plugin list.*grep -q \([a-z][a-z0-9.-]*\); then$/\1/p' "$BOOTSTRAP"); do
      line="$(echo "$plugins" | grep -E "^- [^ ]*$want " || true)"
      # bootstrap skips herdr-fingers without cargo, so missing it then is expected
      if [[ -z "$line" && "$want" == herdr-fingers ]] && ! have cargo; then warn "plugin herdr-fingers not installed (needs Rust/cargo: https://rustup.rs, then ./bootstrap.sh)"
      elif [[ -z "$line" ]]; then fail "plugin $want not installed (run ./bootstrap.sh)"
      elif echo "$line" | grep -q ' enabled '; then pass "plugin $want enabled"
      else fail "plugin $want installed but disabled"; fi
    done
    pjson="$(herdr plugin list --json 2>/dev/null)"
    check_plugin_pins "$pjson"
    root="$(plugin_root "$pjson" persiyanov.reviewr)"
    [[ -n "$root" ]] && check_reviewr_binary "$root"
    root="$(plugin_root "$pjson" nathan-poncet.herdr-fingers)"
    [[ -n "$root" ]] && check_fingers_binary "$root"
    if [[ -z "$tomlpy" ]]; then warn "no Python with tomllib (3.11+); key binding and plugin config checks skipped"
    else
      check_bound_plugin_actions "$HOME/.config/herdr/config.toml" "$(herdr plugin action list 2>/dev/null)"
      if echo "$plugins" | grep -q '^- cloudmanic.herdr-plus '; then check_herdr_plus_config "$(plugin_config_dir cloudmanic.herdr-plus)"; fi
      check_reviewr_config "$(plugin_config_dir persiyanov.reviewr)/config.toml"
    fi
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
    # $jj_status is live: each space whose first pane (its home) is in a jj repo carries it.
    if have jj && [[ -x "$summ" ]]; then
      homes="$(/usr/bin/python3 -c 'import json, subprocess
def h(*a):
    return json.loads(subprocess.run(["herdr"] + list(a), capture_output=True, text=True, timeout=10).stdout)["result"]
for w in h("workspace", "list")["workspaces"]:
    try:
        panes = h("pane", "list", "--workspace", w["workspace_id"])["panes"]
    except Exception:
        continue
    if not panes:
        continue
    order = lambda p: (len(p["pane_id"].split(":")[-1]), p["pane_id"].split(":")[-1])
    first = min(panes, key=order)
    print("\x1f".join([w.get("label") or w["workspace_id"], first.get("cwd") or "",
                        (w.get("tokens") or {}).get("jj_status", "")]))' 2>/dev/null)"
      njj=0; missing=""; broken=""
      while IFS=$'\x1f' read -r label dir token; do
        [[ -n "$dir" ]] || continue
        if ! want="$("$summ" jj-status "$dir" 2>/dev/null)"; then broken+=" $label"; continue; fi
        [[ -n "$want" ]] || continue
        njj=$((njj+1))
        [[ -n "$token" ]] || missing+=" $label"
      done <<<"$homes"
      [[ -n "$broken" ]] && warn "jj failed reading the home of space(s):$broken (try: herdr-summarize jj-status DIR)"
      if (( njj == 0 )); then info "no open space has its first pane in a jj repo; \$jj_status not checked live"
      elif [[ -n "$missing" ]]; then warn "\$jj_status missing on jj space(s):$missing (no summarizer pass since they opened? focus a pane there)"
      else pass "\$jj_status shown on all $njj jj space(s)"; fi
    fi
  fi
fi

# ── summary ──────────────────────────────────────────────────────────────────
printf '\n%s%d passed%s · %s%d warnings%s · %s%d failed%s\n' "$G" "$PASSES" "$N" "$Y" "$WARNS" "$N" "$R" "$FAILS" "$N"
(( FAILS == 0 ))
