---
created: 2026-03-30
source: user (moved from docs/plans, where it sat pending since March)
---

# Jujutsu (jj) for this repo

- **What:** Run this repo in Jujutsu colocated mode (`jj git init --colocate`), install `jj` from `bootstrap.sh`, and document the agent workflow.
- **Why here:** Several agents working in one checkout collide on `.git/index.lock`. jj uses an operation log instead of a lock, so concurrent writes merge instead of failing.
- **Effort:** large. It changes how every session commits in this repo.
- **Touches:** `bootstrap.sh`, `CLAUDE.md` (branch and worktree workflow), `validate.sh`, the repo's own VCS state.
- **Needs the real machine:** yes.
- **Notes for the plan:** `lazyjj` is already installed and bound to a herdr popup. The original detailed plan is in git history: `git show 871733c:docs/plans/jujutsu-adoption.md`. It predates herdr and `/build-proposals`, both of which give each agent its own worktree.
- **Links:** https://jj-vcs.github.io/jj/

## Needs decision
Is this still wanted? The lock collisions it solves came from several agents sharing one checkout. Agents now work in separate worktrees, which already avoids that. If yes, say whether it should cover only this repo or also become the documented default for sessions here.
