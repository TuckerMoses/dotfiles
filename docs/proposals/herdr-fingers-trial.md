---
created: 2026-11-17
source: session 2026-11-17 (herdr plugin research)
---

# herdr-fingers: hint-copy paths, SHAs and URLs (trial)

- **What:** Install `nathan-poncet/herdr-fingers`, a port of tmux-fingers, and bind a key: it overlays hints on paths, URLs, SHAs, UUIDs and numbers in the pane, and copies (or pastes, or opens) the one picked.
- **Why here:** Copying a path or commit SHA out of agent output currently means copy mode (`prefix+[`) and a manual selection. This is one keypress plus a hint, with no events and no background work.
- **Effort:** small.
- **Touches:** `bootstrap.sh`, `herdr/.config/herdr/config.toml`, `validate.sh`, `docs/herdr.html`, `CLAUDE.md`.
- **Needs the real machine:** yes.
- **Notes for the plan:** This is a trial: the plugin had 15 stars on 2026-11-17 (pushed 2026-11-10, MIT), so write the plan so that removal is one revert. It builds with `cargo build --release --locked` and needs Rust 1.85 or newer; `cargo` is on this machine, but `bootstrap.sh` does not install Rust, so guard the install on `command -v cargo` and warn otherwise. Its manifest has one action and one overlay pane; `min_herdr_version` 0.7.0. It copies through OSC 52, so check that Ghostty accepts the clipboard write. Its suggested key is `prefix+f`; confirm that is free in herdr's defaults. Pin with `--ref` and read the manifest at that commit first. `hotchpotch/herdr-tiny-fingers` and `rmarganti/herdr-pluck` do the same job and were not read in depth; do not evaluate them unless this one fails.
- **Links:** https://github.com/nathan-poncet/herdr-fingers
