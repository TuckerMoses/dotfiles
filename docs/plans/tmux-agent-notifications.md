---
status: done
created: 2026-03-27
updated: 2026-04-02
---

# Plan: tmux Agent Completion Notifications

## Goal
When Claude Code finishes in any tmux pane, send a macOS desktop notification that identifies the session. Clicking the notification switches to that pane. Play game sound effects on Claude Code lifecycle events.

## Context
- macOS, Ghostty 1.3.1, tmux 3.6a
- User runs multiple Claude Code agents across tmux panes simultaneously
- Dotfiles repo at `~/dotfiles`, managed with GNU Stow

## Architecture

Two Claude Code plugins split responsibilities:

```
claude-notifications-go     → desktop banners + click-to-focus (sounds OFF)
game-sounds                 → sound effects per event (custom pack from dotfiles)
```

```
Claude Code event fires
  → claude-notifications-go: sends macOS notification with pane metadata
    → User clicks → tmux select-pane + Ghostty activate
  → game-sounds: plays random sound from notification-sounds/<event>/
```

## What Was Built

### 1. claude-notifications-go plugin
- Desktop notifications with session/pane identification
- Click-to-focus: switches to correct tmux pane and brings Ghostty to front
- Sounds disabled (handled by game-sounds instead)
- Config written by bootstrap to `~/.claude/claude-notifications-go/config.json`

### 2. game-sounds plugin with custom pack
- `notification-sounds/` directory in dotfiles contains curated sounds from:
  Metal Gear Solid, Mario, Zelda, Batman, Mortal Kombat, Top Gun,
  Silent Hill, Final Fantasy, Scooby-Doo, Star Trek
- Bootstrap symlinks `notification-sounds/` into the plugin's sounds dir as `custom` pack
- Random sound selection per event (built into game-sounds)

### 3. bootstrap.sh additions
- Installs both plugin marketplaces and plugins via `claude plugin` CLI
- Writes claude-notifications-go config (idempotent — skips if exists)
- Symlinks custom sound pack into game-sounds plugin (`ln -sfn`)
- Sets `active_pack: "custom"` in game-sounds config

## Known Limitation
The symlink into game-sounds breaks on plugin version updates (cache dir is versioned).
Re-running `bootstrap.sh` fixes it. Symptom: sounds stop playing silently.
Upstream feature request: support a `custom_sounds_dir` config field.

## Events Covered

| Event | Notification | Sound |
|-------|-------------|-------|
| Stop (task complete) | Desktop banner + click-to-focus | Random from `task-complete/` |
| Notification (permission) | Desktop banner + click-to-focus | Random from `permission/` |
| SessionStart | — | Random from `session-start/` |
| UserPromptSubmit | — | Random from `task-acknowledge/` |
| Error | Desktop banner | Random from `error/` |
