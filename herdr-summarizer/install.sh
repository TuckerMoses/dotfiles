#!/usr/bin/env bash
set -euo pipefail

# ── herdr-summarizer: opt-in herdr plugin ────────────────────────────────────
# Links the herdr-summarizer plugin, which keeps pane labels, status ("needs
# you"), descriptions and stale reviews current from herdr's own events (an agent
# turn ending, an agent appearing, a pane moving or gaining focus). Nothing runs
# on a timer. Deliberately NOT run by bootstrap.sh: it calls a model (Haiku per
# finished turn, Opus once per stale session).
#
#   ./install.sh              link the plugin (idempotent; also removes the
#                             launchd job used by the first version, if present)
#   ./install.sh --uninstall  unlink the plugin
#
# The scripts (herdr-summarize, herdr-recent) are passive and come from the
# stowed herdr package (~/.local/bin).

PLUGIN_ID="herdr-summarizer"
DIR="$(cd "$(dirname "$0")" && pwd)"
LEGACY_LABEL="dev.dotfiles.herdr-summarizer"
LEGACY_PLIST="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"

remove_legacy_launchd() {
  [[ "$(uname)" == "Darwin" ]] || return 0
  if [[ -e "$LEGACY_PLIST" ]] || launchctl print "gui/$(id -u)/$LEGACY_LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/$LEGACY_LABEL" 2>/dev/null || true
    rm -f "$LEGACY_PLIST"
    echo "==> removed the old launchd job ($LEGACY_LABEL)"
  fi
}

linked() { herdr plugin list 2>/dev/null | grep -q "^- $PLUGIN_ID "; }

if [[ "${1:-}" == "--uninstall" ]]; then
  if linked; then herdr plugin unlink "$PLUGIN_ID" >/dev/null; fi
  remove_legacy_launchd
  echo "==> $PLUGIN_ID unlinked (state kept in ~/.local/state/herdr-summarizer)"
  exit 0
fi
[[ $# -eq 0 ]] || { sed -n '4,16p' "$0"; exit 1; }

# ── requirements ─────────────────────────────────────────────────────────────
missing=()
command -v herdr >/dev/null 2>&1 || missing+=("herdr")
command -v claude >/dev/null 2>&1 || missing+=("claude")
command -v fzf >/dev/null 2>&1 || missing+=("fzf (for the prefix+a picker)")
[[ -x /usr/bin/python3 ]] || missing+=("/usr/bin/python3")
[[ -x "$HOME/.local/bin/herdr-summarize" ]] || missing+=("~/.local/bin/herdr-summarize (stow the herdr package: ./bootstrap.sh)")
if (( ${#missing[@]} )); then
  printf 'Missing:\n'; printf '  %s\n' "${missing[@]}"
  exit 1
fi >&2
if ! claude -p --model haiku --no-session-persistence --strict-mcp-config --tools "" \
       --settings '{"disableAllHooks":true}' "Reply with OK" >/dev/null 2>&1; then
  echo "claude -p failed. Log in first (run: claude), then re-run this script." >&2
  exit 1
fi

# ── install ──────────────────────────────────────────────────────────────────
# Relink so the registry always points at this checkout.
if linked; then herdr plugin unlink "$PLUGIN_ID" >/dev/null; fi
herdr plugin link "$DIR/plugin" >/dev/null
remove_legacy_launchd
echo "==> $PLUGIN_ID linked from $DIR/plugin"
echo "    events:  ~/.local/state/herdr-summarizer/events.log"
echo "    picker:  ctrl+b a   (? for the guide)"
echo "    remove:  $DIR/install.sh --uninstall"
