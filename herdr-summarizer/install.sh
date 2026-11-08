#!/usr/bin/env bash
set -euo pipefail

# ── herdr-summarizer: opt-in background job (macOS / launchd) ────────────────
# Runs herdr-summarize every few minutes so herdr panes and spaces carry a label,
# heat, whose-move (ball) and a full description. Deliberately NOT run by
# bootstrap.sh: it creates a recurring background job that calls a model.
#
#   ./install.sh              install, or reinstall after a git pull (idempotent)
#   ./install.sh --uninstall  stop the job and remove its plist
#
# The scripts themselves (herdr-summarize, herdr-recent) are passive and come from
# the stowed herdr package (~/.local/bin). Re-running always leaves exactly one job.

LABEL="dev.dotfiles.herdr-summarizer"
INTERVAL=300  # seconds between passes
DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN="$HOME/.local/bin/herdr-summarize"
LOG="$HOME/Library/Logs/herdr-summarizer.log"
DOMAIN="gui/$(id -u)"

unload() { launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true; }

if [[ "${1:-}" == "--uninstall" ]]; then
  unload
  rm -f "$PLIST"
  echo "==> herdr-summarizer job removed (state kept in ~/.local/state/herdr-summarizer)"
  exit 0
fi
[[ $# -eq 0 ]] || { sed -n '4,13p' "$0"; exit 1; }

# ── requirements ─────────────────────────────────────────────────────────────
[[ "$(uname)" == "Darwin" ]] || { echo "launchd is macOS-only; nothing to do." >&2; exit 1; }
missing=()
command -v herdr >/dev/null 2>&1 || missing+=("herdr")
command -v claude >/dev/null 2>&1 || missing+=("claude")
command -v fzf >/dev/null 2>&1 || missing+=("fzf (for the prefix+a picker)")
[[ -x /usr/bin/python3 ]] || missing+=("/usr/bin/python3 (run: xcode-select --install)")
[[ -x "$BIN" ]] || missing+=("$BIN (stow the herdr package: ./bootstrap.sh)")
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
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
# Rendered, not symlinked: launchd needs absolute paths, which differ per user.
sed -e "s|@LABEL@|$LABEL|g" -e "s|@BIN@|$BIN|g" \
    -e "s|@INTERVAL@|$INTERVAL|g" -e "s|@LOG@|$LOG|g" \
    "$DIR/launchd.plist.template" > "$PLIST"
plutil -lint "$PLIST" >/dev/null

unload
# bootout returns before the job is fully gone; bootstrapping too early fails with EIO.
for _ in $(seq 1 50); do
  launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || break
  sleep 0.1
done
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "==> herdr-summarizer installed: every ${INTERVAL}s, log at $LOG"
echo "    run now:  launchctl kickstart $DOMAIN/$LABEL"
echo "    status:   launchctl print $DOMAIN/$LABEL"
echo "    remove:   $DIR/install.sh --uninstall"
