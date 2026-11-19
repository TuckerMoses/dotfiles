---
created: 2026-11-19
source: user
---

# herdr: jump back and forward through focus history, like Neovim's ctrl-o / ctrl-i

- **What:** Keep a history of the panes focused across tabs and workspaces, and bind two keys that walk it backward and forward, so going to another tab for one change and returning is a single keypress each way.
- **Why here:** Returning today means remembering where you were and re-navigating (`prefix+1..9`, `ctrl+1..9`, the workspace picker or `prefix+a`). herdr has a built-in `last_pane` action, but it is a two-way toggle and is not bound in `herdr/.config/herdr/config.toml`; it cannot go back more than one step.
- **Effort:** medium.
- **Touches:** `herdr/.config/herdr/config.toml`, `herdr-summarizer/plugin/` or a new small plugin, `validate.sh`, `docs/herdr.html`, `CLAUDE.md` key list.
- **Needs the real machine:** yes.
- **Notes for the plan:** Start by binding the built-in `last_pane` and using it for a few days: if one step back is enough, stop there and say so. If not, build the history in-house: herdr plugins receive `pane.focused`, `tab.*` and `workspace.focused` events and can expose actions, so a plugin can record focus changes and offer `back` and `forward`; no timer. Three things decide whether this is pleasant. First, the keys: in a terminal `ctrl+i` is the same byte as Tab unless the Kitty keyboard protocol disambiguates them, so binding it unprefixed can swallow Tab in every pane; test in Ghostty before committing to it, and fall back to prefixed keys if it is not clean. `ctrl+o` is used by Claude Code (transcript toggle) and by Neovim's own jumplist, and nearly every pane here runs one of those. Decide between prefixed keys (`prefix+ctrl+o` / `prefix+ctrl+i` are free; `prefix+o` is herdr's jump-to-agent) and unprefixed keys that pass through to Neovim the way `vim-herdr-navigation` does for `ctrl+h/j/k/l`; passing through to Claude Code is not possible, so unprefixed `ctrl+o` costs its transcript toggle. Second, what counts as a jump: Neovim records jumps, not every cursor move. Walking `ctrl+h/j/k/l` across four panes should not leave four entries; record a pane only once focus has rested on it (or only on tab and workspace changes plus deliberate jumps), drop entries for closed panes, and do not record the moves made by `back` and `forward` themselves. Third, pane IDs change when a pane moves to another workspace, so key the history on something that survives a move or handle `pane.moved`. `third774/herdr-last-workspace` and `beyondlex/herdr-recent-navigator` cover parts of this and were not read in depth; read them for ideas, do not install them.
- **Links:** https://github.com/herdrdev/herdr/blob/v0.9.5/CHANGELOG.md (the `last_pane` action, #287)
