# Dotfiles Plans

The record of what was built. Each file here is the implementation plan for a change that is on `master`.

Plans are not a queue. The queue is `docs/proposals/`: every proposal there is approved, and `/execute-proposals`
writes a plan for each one at the moment it executes it, then deletes the proposal and adds the plan here. See
`docs/proposals/README.md`.

## Plans

| Plan | Status | Description |
|------|--------|-------------|
| [tmux-agent-notifications](tmux-agent-notifications.md) | `done` | macOS desktop notifications when Claude Code finishes, click to switch pane |
| [neovim-claude-sync](neovim-claude-sync.md) | `done` | Keep Neovim in sync with Claude Code file changes (3 tiers) |
| [tmux-session-persistence](tmux-session-persistence.md) | `done` | Persist tmux sessions across reboots with resurrect + continuum |
| [claude-context-management](claude-context-management.md) | `done` | Global CLAUDE.md via Stow so every Claude Code session has context |

## Running the queue

In a Claude Code session started in `~/dotfiles`:

```
/execute-proposals                # every proposal in docs/proposals/ on master
/execute-proposals git-config     # only the named proposals
/execute-proposals --dry-run      # review the proposals and print the dispatch table; change nothing
```

It reviews each proposal against the current repo, writes its plan, implements independent units in parallel
worktrees, has each add a `validate.sh` check, merges them into one branch, validates that branch live, runs an
adversarial review, and opens one PR. It never merges to `master`. Details: `.claude/skills/execute-proposals/SKILL.md`.
