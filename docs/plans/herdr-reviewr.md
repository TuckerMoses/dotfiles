---
status: done
created: 2026-11-17
updated: 2026-11-17
proposal: "session 2026-11-17 (herdr plugin research)"
---

# Plan: herdr-reviewr

## Goal
Install `persiyanov/herdr-reviewr` pinned to a reviewed commit and bind a key to toggle it: a split pane with the
agent's diff (uncommitted, branch, last turn, commits) where line comments are collected and sent to the agent input.

## Context
lazygit/lazyjj popups show diffs but cannot hand structured comments to Claude.

Read at the pinned commit `bb71050caa5d3a0b1a414527783eb7a772447f9f` (release v0.52.2, 2026-11-15; MIT; ~1000 stars,
50 open issues):
- `herdr-plugin.toml`: id `persiyanov.reviewr`, `min_herdr_version = "0.9.3"` (machine: 0.9.5). One split pane,
  actions `toggle` / `open` / `close`, events `worktree.created` / `worktree.opened` → `--action auto-open`
  (gated by `auto_open`).
- `herdr/install.sh` (the `[[build]]` step): downloads `herdr-reviewr-<target>.tar.gz` from the GitHub release whose
  tag equals the manifest version, verifies it against the release's `.sha256`, installs `bin/herdr-reviewr`, and
  symlinks it into `~/.local/state/herdr/plugins/persiyanov.reviewr/bin/` and, if it exists, `~/.local/bin/`
  (only if that path is a symlink or absent). Nothing else.
- Config: `~/.config/herdr/plugins/config/persiyanov.reviewr/config.toml`, applied on save; an invalid file blocks
  the pane until fixed. Default theme `catppuccin`.
- Needs git; PR tab needs `gh` (present).

## Steps
1. `bootstrap.sh`, herdr plugins block, keeping the line shape `validate.sh` reads:
   ```
   # herdr-reviewr: review an agent's diff, send line comments back (pinned; read before bumping)
   if ! herdr plugin list 2>/dev/null | grep -q persiyanov.reviewr; then
     herdr plugin install persiyanov/herdr-reviewr --ref <sha> --yes || echo ...
   fi
   ```
   The pin in a variable or inline; the grep name must be the plugin id `persiyanov.reviewr` (`herdr plugin list`
   prints ids). Bootstrap keeps `--yes` because the pin is the review; first install on this machine is done by hand
   without `--yes` in Phase 6.
2. Stowed plugin config `herdr/.config/herdr/plugins/config/persiyanov.reviewr/config.toml`:
   `auto_open = false`, `theme = "catppuccin"` (Catppuccin Mocha is the repo palette; use the theme name reviewr
   accepts for Mocha if it distinguishes flavours), `default_scope = "uncommitted"`, `toggle_placement = "split"`,
   `toggle_direction = "right"`. Nothing else.
3. `herdr/.config/herdr/config.toml`, a `# ── herdr-reviewr ──` section in the keys area (before the
   `# ── herdr-summarizer tokens` section):
   `prefix+alt+r` → `plugin_action` `persiyanov.reviewr.toggle`, description "review diff". Same alt family as the
   lazygit/lazyjj popups (`prefix+alt+g`, `prefix+alt+j`); free in herdr's defaults and this config.
4. `validate.sh`: checks below.

## Validation
- Installed: automatic, from the bootstrap line (`validate.sh` reads plugin names from it).
- **Pin is what is installed**: the commit in `herdr plugin list`'s `[github:persiyanov/herdr-reviewr@<sha>]` equals the
  `--ref` in `bootstrap.sh`; warn when they differ (someone ran `herdr plugin update`). Fails/warns when the plugin
  is updated past the reviewed commit.
- **Binary present and runs**: `<plugin root>/bin/herdr-reviewr --version` (or `--help`) exits 0. Plugin root from
  `herdr plugin list` / the github-installations dir. Fails when: the build step's download failed.
- The keys check from herdr-plus-wire-up (every bound `plugin_action` exists) covers the binding. If that unit is
  not merged yet, do not duplicate it.
- **Config parses**: the stowed reviewr `config.toml` parses with `tomllib` and has `auto_open = false`.
- Show each fails against a broken copy before committing.

## Outside the repo
- First install by hand (Phase 6), no `--yes`: `herdr plugin install persiyanov/herdr-reviewr --ref <sha>`.
- `~/.local/bin/herdr-reviewr` symlink created by the installer (not stowed; harmless; list in PR).
- `~/.config/herdr/plugins/config/persiyanov.reviewr/` will be created by stow.

## Trial in git and jj repos (Phase 6, before docs)
Try in `~/dotfiles` (git) and `~/Vault` (colocated jj+git) and `~/aios/lib` (jj only, no `.git`). Expected: git works,
colocated probably works through its git repo, jj-only does not. Record the result in `docs/herdr.html`; if jj
repos do not work, it ships for git and the guide says so.

## Edge cases
- Unsent comments are lost when the pane closes; it polls files every 5 s only while open.
- `auto_open = false` means worktree events still fire the hook; the hook just returns.

## Left out
Windows; PR-tab hosts other than GitHub; rebinding reviewr's internal keys.

## As built (2026-11-17)
- Key `prefix+alt+r`. Bootstrap installs with `--ref bb71050` and `--yes`. The pin is a reviewed commit, but it is
  not the whole review: `herdr/install.sh` downloads the release binary for the manifest's version and checks it only
  against the `.sha256` of the same release. So the review covers the source and install script at the pin, and the
  binary itself is trusted to the release, not verified. bb71050 is the commit the `v0.52.2` tag points to (checked
  with `gh api` on 2026-11-18: the tag is annotated and dereferences to bb71050caa5d). `herdr-plugins review` now
  checks that the tag for the manifest version points at the commit being pinned. The first install on the main
  machine was done by hand without `--yes`.
- reviewr has no `--version`. `validate.sh` probes the binary with `--action validate-probe`, which must answer
  "unknown action". An unknown action returns before reviewr reads its config or re-points symlinks, which is why the
  probe writes nothing (verified at bb71050); the probe must stay an action reviewr does not know.
- The config check enforces reviewr's own key and value lists, copied from `src/config.rs` and `src/theme.rs` at the
  pin. A bump of the pin must refresh those lists. `catppuccin` is reviewr's name for Mocha.
- A pin check, shared with fingers, warns when the installed commit differs from the `--ref` in `bootstrap.sh`.
