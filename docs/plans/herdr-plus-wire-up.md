---
status: done
created: 2026-11-17
updated: 2026-11-17
proposal: "session 2026-11-17 (herdr plugin research)"
---

# Plan: herdr-plus, wired up

## Goal
Make the already-installed `cloudmanic/herdr-plus` (installed at `f38df35`, v0.1.24) do something: a small set of
project templates, worktree auto-layouts for the git repos, a few quick actions, and keys for its `projects` and
`quick-actions` actions.

## Context
`bootstrap.sh` installs it, but its config dir `~/.config/herdr/plugins/config/cloudmanic.herdr-plus/` was empty on
2026-11-17, its plugin log had no runs, and `config.toml` bound none of its actions. `validate.sh` passes it on
"installed and enabled" alone.

Facts read from the installed source (`config.go`, `README.md`, `herdr-plugin.toml`):
- It reads everything from `$HERDR_PLUGIN_CONFIG_DIR` (= the dir above): `projects/*.toml`, `worktrees/*.toml`,
  `quick-actions/*.toml`, and an optional `config.toml` (`[projects] placement`, `[quick_actions] placement`,
  `[worktree] branch_prefix`).
- It seeds example quick actions only when `quick-actions/` does not exist, so a stowed `quick-actions/` is never
  overwritten.
- Worktree auto-layout runs on herdr's `worktree.created` / `worktree.opened` events (git only) and is a no-op when no
  layout's `repo` matches the repo basename.
- Every `working_dir` must exist or the template is rejected before anything opens.

## Steps
1. Stow the config from the herdr package (already `--no-folding`, so each file is its own link and herdr's state
   stays real). New files under `herdr/.config/herdr/plugins/config/cloudmanic.herdr-plus/`:
   - `config.toml`: `[projects] placement = "popup"`, `[quick_actions] placement = "popup"` (leave the tiled layout
     alone, like the lazygit/lazyjj popups). No `branch_prefix`; branch prefixes are not a convention here.
   - `projects/dotfiles.toml` (`~/dotfiles`: claude, lazygit, shell), `projects/claude-materia.toml`
     (`~/claude-materia`: claude, lazygit, shell), `projects/vault.toml` (`~/Vault`: claude, lazyjj, shell),
     `projects/aios.toml` (`~/aios`: claude, shell). Four, not every directory. Tabs start `claude` (plain `claude`,
     no extra flags), and use lazygit or lazyjj according to the repo's VCS.
   - `worktrees/dotfiles.toml` and `worktrees/claude-materia.toml` (repo match on basename; tabs claude, lazygit,
     shell). No wildcard layout: a wildcard would fire in every repo, including ones herdr-reviewr also auto-opens in.
   - `quick-actions/`: `validate-dotfiles.toml` (`~/dotfiles/validate.sh -q`), `reload-herdr.toml`
     (`herdr server reload-config`), `summarizer-pass.toml` (`herdr-summarize pass`, only meaningful with the opt-in
     plugin). Each a `command` action; check the exact action-file schema against the installed `quickactions.go`.
2. `herdr/.config/herdr/config.toml`: in the keys area (after the popups, **before** the
   `# ── herdr-summarizer tokens` section, so other units' edits to the sidebar rows merge cleanly) add a
   `# ── herdr-plus ──` section with two `[[keys.command]]` `plugin_action` bindings:
   - `prefix+t` → `cloudmanic.herdr-plus.projects` ("projects")
   - `prefix+space` → `cloudmanic.herdr-plus.quick-actions` ("quick actions")
   Both are absent from herdr's built-in defaults and from this config. Confirm with `herdr config check` on the
   edited file (`HERDR_CONFIG_PATH=<file> herdr config check`).
3. (Superseded by docs/plans/herdr-plugin-pins.md: bootstrap now pins herdr-plus with `--ref` and installs it only when Go is present.) `bootstrap.sh`: no install change (it already installs herdr-plus). Update its comment to say the config comes
   from the herdr package.
4. `validate.sh`, herdr section: the new checks below.

## Validation
- **Every bound `plugin_action` exists** (all plugins, not only this one): parse every `[[keys.command]]` with
  `type = "plugin_action"` from the stowed `config.toml` (Python `tomllib`), compare each `command` against
  `<plugin_id>.<action_id>` pairs from `herdr plugin action list` (JSON), fail naming each binding whose action
  herdr does not list. Fails when: a plugin is uninstalled, an action id is misspelled, or a plugin renames an action.
- **herdr-plus templates load**: every `projects/*.toml` and `worktrees/*.toml` in the plugin config dir parses as
  TOML, has the required keys (`name` for projects, `repo` for worktrees, at least one `[[tabs]]`), and every
  `working_dir` it names (after `~`/`$VAR` expansion and tab-relative resolution) exists. Missing directories are a
  **warning** (a repo not cloned on this machine), parse errors a failure. Fails when: a template is malformed.
- Show both fail by pointing them at a broken copy (a binding to `cloudmanic.herdr-plus.nope`; a template with a
  syntax error) before committing.

## Outside the repo
- `~/.config/herdr/plugins/config/cloudmanic.herdr-plus/` exists and is empty, so stow links into it with no conflicts.
- `~/.config/herdr/plugins/config/herdr-plus/` (empty, created 2026-11-17 09:23, not used by the plugin) is a stray;
  remove it by hand in Phase 6 only if still empty.
- `herdr server reload-config` after stowing.

## Edge cases
- herdr-plus reads its config fresh on each picker open, so no reload is needed for template edits.
- If a working_dir is missing (e.g. on Linux), herdr-plus refuses that one template with a message; the others work.
- If after a week of use the keys go unused, the alternative is removing herdr-plus from `bootstrap.sh` and deleting
  its config files; the keys check would then fail until the two bindings are removed too, which is the point.

## Left out
Wildcard worktree layout; templates for every directory; `branch_prefix`; repo-local `.herdr-plus/quick-actions/`.

## As built (2026-11-17)
- Keys `prefix+t` (projects) and `prefix+space` (quick actions); both pickers open as popups.
- The quick action that runs a summarizer pass calls `herdr-summarize run` (there is no `pass` subcommand). The
  validate and summarizer actions wait for Enter before closing, since herdr-plus closes its pane when the command
  exits.
- `validate.sh` gained two checks. The first applies to every plugin: each bound `plugin_action` must be an action herdr
  lists. `herdr config check` accepts any name, so this check covers what it misses. The second loads the herdr-plus
  config with herdr-plus's own load rules: projects, worktrees, quick actions and placements. A file that would empty a
  picker is a failure; a missing `working_dir` is a warning.
- The TOML checks need Python's `tomllib`. macOS's `/usr/bin/python3` (3.9) does not have it, so `validate.sh` uses the
  first `python3.11+` it finds and warns when there is none.
