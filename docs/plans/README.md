# Dotfiles Plans

Implementation plans for terminal/workflow improvements. Each plan is self-contained and can be handed off to a Claude Code agent for execution.

## Plans

| Plan | Status | Description |
|------|--------|-------------|
| [tmux-agent-notifications](tmux-agent-notifications.md) | `pending` | macOS desktop notifications when Claude Code finishes, click to switch pane |
| [neovim-claude-sync](neovim-claude-sync.md) | `pending` | Keep Neovim in sync with Claude Code file changes (3 tiers) |
| [tmux-session-persistence](tmux-session-persistence.md) | `pending` | Persist tmux sessions across reboots with resurrect + continuum |
| [claude-context-management](claude-context-management.md) | `pending` | Global CLAUDE.md via Stow so every Claude Code session has context |
| [jujutsu-adoption](jujutsu-adoption.md) | `pending` | Migrate to Jujutsu (jj) for lock-free concurrent agent workflows |

## Statuses

- `pending` — not started
- `in-progress` — currently being implemented
- `done` — implemented and verified
- `blocked` — waiting on something external

## How to execute a plan

Start a Claude Code session in `~/dotfiles` and run:

```
Execute the plan in docs/plans/<plan-name>.md. Follow the CLAUDE.md instructions and update the plan status, changelog, and commit when done.
```
