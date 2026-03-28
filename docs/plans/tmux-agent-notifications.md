---
status: pending
created: 2026-03-27
updated: 2026-03-27
---

# Plan: tmux Agent Completion Notifications

## Goal
When Claude Code finishes in any tmux pane, send a macOS desktop notification that identifies the session. Clicking the notification switches to that pane.

## Context
- macOS, Ghostty 1.3.1, tmux 3.6a
- User runs multiple Claude Code agents across tmux panes simultaneously
- Dotfiles repo at `~/dotfiles`, managed with GNU Stow

## Architecture

```
Claude Code finishes
  → Stop hook fires (shell script)
    → Script captures $TMUX_PANE, session name, window index
    → Sends notification via `alerter` with pane metadata
    → If user clicks "Switch" → runs tmux select-window + select-pane
    → If user dismisses → no-op
```

## Implementation Steps

### 1. Install alerter
```bash
brew install vjeantet/tap/alerter
```
`alerter` is the only macOS CLI notification tool that supports clickable action buttons with stdout callbacks. `terminal-notifier` dropped action support in v2.0+. `osascript` notifications have no click callback.

### 2. Create the notification script
Create `~/dotfiles/scripts/claude-notify.sh`:

```bash
#!/usr/bin/env bash
# Called by Claude Code's Stop hook when a response completes.
# Sends a macOS notification; clicking "Switch" jumps to the source tmux pane.

# Skip if not in tmux
[[ -z "$TMUX" ]] && exit 0

# Gather tmux context
PANE_ID="$TMUX_PANE"
SESSION=$(tmux display-message -t "$PANE_ID" -p "#{session_name}")
WINDOW=$(tmux display-message -t "$PANE_ID" -p "#{window_index}")
PANE_INDEX=$(tmux display-message -t "$PANE_ID" -p "#{pane_index}")
WINDOW_NAME=$(tmux display-message -t "$PANE_ID" -p "#{window_name}")

# Send notification with alerter (runs in background so hook doesn't block)
(
  ACTION=$(alerter \
    -title "Claude Code" \
    -subtitle "$SESSION:$WINDOW.$PANE_INDEX" \
    -message "Finished in $WINDOW_NAME" \
    -actions "Switch" \
    -closeLabel "Dismiss" \
    -timeout 30 \
    -appIcon "/Applications/Ghostty.app/Contents/Resources/AppIcon.icns" \
    2>/dev/null)

  if [[ "$ACTION" == "Switch" ]]; then
    tmux select-window -t "$SESSION:$WINDOW"
    tmux select-pane -t "$PANE_ID"
    # Bring Ghostty to front
    osascript -e 'tell application "Ghostty" to activate'
  fi
) &
```

### 3. Add the Stop hook to Claude Code settings
In `~/.claude/settings.json`, add:

```json
{
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "command": "bash ~/dotfiles/scripts/claude-notify.sh"
      }
    ]
  }
}
```

Note: If there's already a Stop hook (e.g., ralph-loop), add this as another entry in the array. Multiple hooks can coexist.

### 4. Stow the scripts package
Add `scripts/` as a new stow package or keep it as a plain directory in the dotfiles repo (since scripts don't need to be symlinked to `$HOME`). The hook references it by absolute path.

### 5. Test
- Open two tmux panes, run `claude` in both
- Ask Claude something in one pane, switch to the other
- When the first finishes, you should get a notification
- Click "Switch" and verify it jumps to the right pane

## Edge Cases to Handle
- **Not in tmux**: Script exits early if `$TMUX` is unset
- **Multiple rapid completions**: Each notification is independent (background subshell)
- **Notification timeout**: 30 seconds before auto-dismiss (configurable)
- **Ghostty not focused**: The `osascript` activate call brings it to front on click

## Optional Enhancements
- Add a sound: `alerter -sound default`
- Filter out short responses (only notify if response took >5s) by checking `$CLAUDE_RESPONSE_DURATION` if available
- Add the pane's working directory to the notification message
- Use `alerter -json` for structured output parsing instead of string matching

## Dependencies
- `alerter` (brew tap: vjeantet/tap/alerter)
- tmux 3.2+ (for `display-message -t` with pane ID)
- macOS (alerter is macOS-only; on Linux, substitute `notify-send` without click support)
