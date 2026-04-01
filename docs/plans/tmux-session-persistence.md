---
status: done
created: 2026-03-29
updated: 2026-03-31
---

# Plan: tmux Session Persistence

## Goal
Persist tmux sessions (windows, panes, layout, working directories) across reboots so you never lose your workspace.

## Context
- tmux 3.6a, TPM already configured in `.tmux.conf`
- User runs multiple panes with Claude Code agents, neovim, and shells
- Dotfiles repo at `~/dotfiles`, managed with GNU Stow

## Implementation Steps

### 1. Install tmux-resurrect via TPM
Add to `~/dotfiles/tmux/.tmux.conf` before the `run '~/.tmux/plugins/tpm/tpm'` line:

```tmux
set -g @plugin 'tmux-plugins/tmux-resurrect'
```

Then run `prefix + I` (capital I) to install via TPM.

### 2. Configure resurrect
Add these settings:

```tmux
# Restore neovim sessions (requires Session.vim in project root)
set -g @resurrect-strategy-nvim 'session'

# Capture and restore pane contents
set -g @resurrect-capture-pane-contents 'on'

# Save/restore working directories
set -g @resurrect-processes 'false'  # don't restore running programs, just layout + dirs
```

Setting `@resurrect-processes` to `false` means it restores the layout, pane positions, and working directories — but doesn't try to restart Claude Code or other processes (which would likely fail or duplicate sessions).

### 3. Optional: Add tmux-continuum for auto-save
```tmux
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @continuum-save-interval '10'  # auto-save every 10 minutes
set -g @continuum-restore 'on'        # auto-restore on tmux start
```

This removes the need to manually save (`prefix + Ctrl-s`).

### 4. Usage
- **Save**: `prefix + Ctrl-s`
- **Restore**: `prefix + Ctrl-r`
- **Auto** (with continuum): sessions save every 10 min and restore on tmux start

### 5. Test
- Set up a multi-pane layout with different working directories
- Save with `prefix + Ctrl-s`
- Kill tmux server: `tmux kill-server`
- Start tmux, restore with `prefix + Ctrl-r`
- Verify: layout, pane sizes, and working directories should match

## Dependencies
- tmux-plugins/tmux-resurrect (via TPM)
- tmux-plugins/tmux-continuum (optional, via TPM)
