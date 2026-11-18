---
created: 2026-11-17
source: session 2026-11-17 (herdr plugin research)
---

# herdr-plus: wire it up

- **What:** Make the already-installed `cloudmanic/herdr-plus` usable: stow project templates, a worktree auto-layout and quick actions for it, and bind keys for its `projects` and `quick-actions` actions.
- **Why here:** `bootstrap.sh:116-119` installs it, but on 2026-11-17 its config dir was empty, `herdr plugin log list` showed zero runs, and `herdr/.config/herdr/config.toml` binds none of its actions. `validate.sh:243-247` passes it because it only checks "installed and enabled".
- **Effort:** small.
- **Touches:** `herdr/` (new files under `.config/herdr/plugins/config/cloudmanic.herdr-plus/`, `config.toml`), `validate.sh`, `docs/herdr.html`, `CLAUDE.md` key list.
- **Needs the real machine:** yes.
- **Notes for the plan:** herdr-plus reads `projects/`, `worktrees/` and `quick-actions/` from its plugin config dir, plus an optional `config.toml` there; the herdr package is stowed with `--no-folding`, so those files can live in the repo beside herdr's own state. Its worktree auto-layout fills a new git worktree's tabs from a template whose `repo` matches, which covers per-worktree setup, so no separate worktree-setup plugin is wanted. Start with a small set of templates (this repo and the repos already used with lazygit/lazyjj) and do not template every directory. Keys already taken: `prefix+a`, `prefix+alt+g`, `prefix+alt+j`, `prefix+s`, `prefix+w`. The new check should fail when a bound `plugin_action` names an action herdr does not list (`herdr plugin action list`), for every plugin, not only this one. If the plugin turns out not to earn a key after a week of use, the alternative is removing it from `bootstrap.sh`; say so in the plan.
- **Links:** https://github.com/cloudmanic/herdr-plus
