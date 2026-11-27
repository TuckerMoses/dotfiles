---
status: done
created: 2026-11-17
updated: 2026-11-17
proposal: "session 2026-11-17 (herdr plugin research)"
---

# Plan: herdr-fingers (trial)

## Goal
Install `nathan-poncet/herdr-fingers` (a Rust port of tmux-fingers) pinned to a reviewed commit and bind a key: hints
over paths, URLs, SHAs, UUIDs and numbers in the focused pane; typing one copies it (Shift pastes, Ctrl opens).
A trial: removal is one revert (superseded: the commit may not survive a squash merge; the removal targets under As built replace this).

## Context
Copying a path or SHA out of agent output today is copy mode (`prefix+[`) plus a manual selection.

Read at pinned commit `2d9fc997ce1a95976b975da758dccc7b6e011336` (HEAD on 2026-11-17; MIT; 15 stars):
- `herdr-plugin.toml`: id `nathan-poncet.herdr-fingers`, `min_herdr_version = "0.7.0"`, `[[build]]` =
  `cargo build --release --locked`, one action `start`, one overlay pane `overlay` (never bind directly).
- No `build.rs` in the crate root; dependencies are crates.io only (base64, crossterm, ratatui, regex, serde,
  serde_json, shell-words, thiserror, toml, unicode-width). `rust-version = "1.85"` (machine: rustc 1.96).
- Copies through OSC 52 by default; herdr forwards it to the attached terminal; Ghostty accepts OSC 52
  (`clipboard-write` default is allow; this repo's ghostty config does not restrict it).
- Writes a commented `config.toml` to its plugin config dir on first run. Not stowed.

## Steps
1. `bootstrap.sh`, herdr plugins block, guarded on cargo and keeping the line shape `validate.sh` reads:
   ```
   # herdr-fingers (trial): hint-copy paths, SHAs, URLs; builds with cargo (Rust >= 1.85)
   if ! herdr plugin list 2>/dev/null | grep -q herdr-fingers; then
     if command -v cargo >/dev/null 2>&1; then herdr plugin install nathan-poncet/herdr-fingers --ref <sha> --yes || ...
     else echo "    (skipping herdr-fingers: needs Rust/cargo, https://rustup.rs)"; fi
   fi
   ```
   Keep the whole block self-contained so the trial reverts as one hunk.
2. `herdr/.config/herdr/config.toml`, a `# ── herdr-fingers (trial) ──` section in the keys area (before the
   `# ── herdr-summarizer tokens` section): `prefix+f` → `plugin_action` `nathan-poncet.herdr-fingers.start`,
   description "hint copy". `prefix+f` is not a herdr default and not used in this config; confirm with
   `herdr config check`.
3. `validate.sh`: checks below.

## Validation
- Installed: automatic from the bootstrap line. Because the install is skipped without cargo, `validate.sh` must
  report a missing herdr-fingers as a **warning** when `cargo` is absent and a failure when cargo is present (adjust
  the generic loop for this one name, or add a small exception list; keep it minimal).
- **Built binary present and runs**: `<plugin root>/target/release/herdr-fingers` exists and is executable (and
  `--help`/`--version` exits 0 if it supports one). Fails when: the cargo build failed or the plugin was installed
  without building.
- **Pin is what is installed**: as for reviewr, compare the installed commit with the `--ref`; warn on drift. If the
  reviewr unit's helper exists, reuse it; within one unit, write it once and use it for both.
- The keys check (every bound `plugin_action` exists) covers the binding.
- Show each fails against a broken copy before committing.

## Outside the repo
- First install by hand in Phase 7, no `--yes`: `herdr plugin install nathan-poncet/herdr-fingers --ref <sha>`
  (cargo build takes a minute or two).
- Verify the copy reaches the macOS clipboard through Ghostty (`pbpaste` after picking a hint).

## Edge cases
- No cargo (e.g. a fresh Linux box): bootstrap skips it with a message, validate warns, the key does nothing.
- Hint keys never use `c`, `i`, `m`, `n`, `q`.

## Removal
Revert the one commit: bootstrap block, key binding, validate checks, docs line; then
`herdr plugin uninstall nathan-poncet.herdr-fingers`. (Superseded, see As built: the target list there is the removal.)

## Left out
`herdr-tiny-fingers`, `herdr-pluck` (not evaluated unless this fails); custom patterns; `clipboard = "system"`.

## As built (2026-11-17)
- Key `prefix+f`. Without cargo, bootstrap skips the install and `validate.sh` warns that the plugin is missing; with
  cargo, a missing plugin is a failure.
- The binary check runs `herdr-fingers --version`, then `scan` on a line holding a SHA, which must produce a hint. It
  runs with `HERDR_PLUGIN_CONFIG_DIR` unset so that it writes no config.
- Removal targets, listed because the commit may not survive a squash merge: the fingers block in `bootstrap.sh`; the
  `prefix+f` binding in `herdr/.config/herdr/config.toml`; the fingers binary check (`check_fingers_binary`) in
  `validate.sh`; the fingers text and the `prefix+f` key line in `CLAUDE.md`;
  the fingers entry in `CHANGELOG.md`; its lines in `docs/herdr.html`; then `herdr plugin uninstall
  nathan-poncet.herdr-fingers`.
