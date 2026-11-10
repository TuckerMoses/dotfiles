# Dotfiles Plans

Implementation plans for terminal/workflow improvements. Each plan is self-contained and can be handed off to a Claude Code agent for execution.

## Plans

| Plan | Status | Description |
|------|--------|-------------|
| [tmux-agent-notifications](tmux-agent-notifications.md) | `done` | macOS desktop notifications when Claude Code finishes, click to switch pane |
| [neovim-claude-sync](neovim-claude-sync.md) | `done` | Keep Neovim in sync with Claude Code file changes (3 tiers) |
| [tmux-session-persistence](tmux-session-persistence.md) | `done` | Persist tmux sessions across reboots with resurrect + continuum |
| [claude-context-management](claude-context-management.md) | `done` | Global CLAUDE.md via Stow so every Claude Code session has context |
| [jujutsu-adoption](jujutsu-adoption.md) | `pending` | Migrate to Jujutsu (jj) for lock-free concurrent agent workflows |
| [herdr-summarizer-other-harnesses](herdr-summarizer-other-harnesses.md) | `pending` | Labels, status and descriptions for herdr agents other than Claude Code |

## Statuses

- `pending` — not started
- `in-progress` — currently being implemented
- `done` — implemented and verified
- `blocked` — waiting on something external

## How to execute plans

Run the `execute-plans` skill in a Claude Code session started in `~/dotfiles`:

```
/execute-plans                 # every pending plan here, plus open plan PRs (claude/plan/*)
/execute-plans git-config      # only the named plans
/execute-plans "direnv"        # an idea with no plan yet: the skill writes the plan, then executes it
/execute-plans --dry-run       # review the plans and print the dispatch table; also lists unplanned ideas
/execute-plans mise --plan-only  # write the plan and open a PR with only the plan file
```

Ideas come from the "dotfiles scout" routine's backlog (`ideas.md` on the `claude/research` branch), the `Planned`
list in `CHANGELOG.md`, or you. The skill is the only thing that writes plans, and only for ideas you name.

It reviews each plan against the current repo, implements independent units in parallel worktrees,
has each add a `validate.sh` check, merges them into one branch, validates that branch live, runs an
adversarial review, and opens one PR. It never merges to `master`. Details: `.claude/skills/execute-plans/SKILL.md`.

To execute a single plan by hand instead:

```
Execute the plan in docs/plans/<plan-name>.md. Follow the CLAUDE.md instructions and update the plan status, changelog, and commit when done.
```
