# Dotfiles Plans

The record of what was built. Each file here is the implementation plan for a change that is on `master`, except a
`superseded` one: built, then replaced before it merged; it names its replacement and is kept as the record.

A plan's Goal, Steps and Validation record what was planned and are not maintained; what exists is its "As built" and the code. Newer plans have an "As built" section (those written by `/build-proposals`, and `herdr-plugin-pins`, which the user requested); the older ones do not, so check them against the code. Everything outside "As built" is as planned, and "As built" wins on any conflict, Removal sections included. Step lines known to be superseded are marked "(superseded, see As built)" or name what replaced them.

Plans are not a queue. The queue is `docs/proposals/`: every proposal there is approved, and `/build-proposals`
writes a plan for each one at the moment it executes it, then deletes the proposal and adds the plan here. See
`docs/proposals/README.md`.

## Plans

| Plan | Status | Description |
|------|--------|-------------|
| [tmux-agent-notifications](tmux-agent-notifications.md) | `done` | macOS desktop notifications when Claude Code finishes, click to switch pane |
| [neovim-claude-sync](neovim-claude-sync.md) | `done` | Keep Neovim in sync with Claude Code file changes (3 tiers) |
| [tmux-session-persistence](tmux-session-persistence.md) | `done` | Persist tmux sessions across reboots with resurrect + continuum |
| [claude-context-management](claude-context-management.md) | `done` | Global CLAUDE.md via Stow so every Claude Code session has context |
| [linux-target](linux-target.md) | `done` | Linux on x86-64 and arm64 as a tested target; one test suite run in three environments before live validation |
| [herdr-plus-wire-up](herdr-plus-wire-up.md) | `done` | herdr-plus project templates, worktree layouts and quick actions; `prefix+t`, `prefix+space` |
| [herdr-reviewr](herdr-reviewr.md) | `superseded` | Review an agent's diff and send line comments back (`prefix+alt+r`), pinned; replaced by tuicr before merge |
| [herdr-fingers-trial](herdr-fingers-trial.md) | `done` | Trial: hint-copy paths, SHAs and URLs from a pane (`prefix+f`), pinned |
| [herdr-jj-status-token](herdr-jj-status-token.md) | `done` | `$jj_status` in the spaces sidebar row for jj repos |
| [herdr-plugin-pins](herdr-plugin-pins.md) | `done` | Every herdr plugin pinned in `bootstrap.sh`; `herdr-plugins status/review/update` moves the pins |
| [tuicr](tuicr.md) | `done` | tuicr replaces herdr-reviewr: diff review for git and jj (`prefix+alt+r`), comments read by the agent skill |
| [herdr-nix-plugin-builds](herdr-nix-plugin-builds.md) | `done` | herdr's three pinned plugins as Nix builds, placed and linked by the Home Manager module; pins stay in `bootstrap.sh` |

## Running the queue

In a Claude Code session started in `~/dotfiles`:

```
/build-proposals                # every proposal in docs/proposals/ on master
/build-proposals git-config     # only the named proposals
/build-proposals --dry-run      # review the proposals and print the dispatch table; change nothing
```

It reviews each proposal against the current repo, writes its plan, implements independent units in parallel
worktrees, has each add a `validate.sh` check, merges them into one branch, tests that branch with `test/suite.sh`
in three environments (isolated local, Linux VM, emulated Linux VM), validates it live, runs an
adversarial review, and opens one PR. It never merges to `master`. Details: `.claude/skills/build-proposals/SKILL.md`.
