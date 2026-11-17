---
created: 2026-11-17
source: session 2026-11-17 (herdr plugin research)
---

# herdr-reviewr: review an agent's diff and send line comments back

- **What:** Install `persiyanov/herdr-reviewr` and bind a key to toggle it: a split pane showing the agent's diff (uncommitted, branch, last turn, commits) where line comments are collected and pasted into the agent's input.
- **Why here:** The lazygit and lazyjj popups show a diff but cannot hand structured comments to Claude; today that is retyped by hand. Of roughly 60 plugins looked at on 2026-11-17 this was the only one adding a workflow the setup lacks.
- **Effort:** small to medium.
- **Touches:** `bootstrap.sh`, `herdr/.config/herdr/config.toml`, `validate.sh`, `docs/herdr.html`, `CLAUDE.md`.
- **Needs the real machine:** yes.
- **Notes for the plan:** Facts as of 2026-11-17: version 0.52.2, `min_herdr_version` 0.9.3 (machine has 0.9.5), MIT, 49 open issues; its installer downloads a release binary and verifies a SHA-256. Set `auto_open = false` so it does not open on every `worktree.created`/`worktree.opened`. Install pinned to a commit with `--ref`, not HEAD; keep the `herdr plugin list | grep -q <name>` line shape in `bootstrap.sh` because `validate.sh` reads plugin names from it. It is git-only by its README: before anything else, try it in one git repo and one jj repo (vault, life or lib) and record what happens; if it does not work in jj repos, ship it for git and say so in `docs/herdr.html`. It polls files every 5 seconds only while its pane is open, and unsent comments are lost when the pane closes. Its optional PR tab needs `gh`. Plugins are unreviewed and run as the user, so read `herdr-plugin.toml` and the install script at the pinned commit first.
- **Links:** https://github.com/persiyanov/herdr-reviewr
