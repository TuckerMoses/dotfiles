---
created: 2026-11-26
source: user
---

# herdr: one space → tab → pane tree instead of two sidebar panels

- **What:** Replace the separate Spaces and Agents panels with one collapsible tree: spaces, then
  their tabs, then the panes in each tab, each pane showing its summarizer label. A notification
  expands its branch and focuses that pane.
- **Why here:** The Agents panel (`agent_panel_sort = "priority"`) is a flat list of 11 rows that
  all read "awaiting …" (see `herdr-summarizer-signal.md`). Where a session lives can be read only
  from the dim tab name on row two, and three rows share the same tab name. The Spaces panel above
  it repeats the space names a second time.
- **What herdr 0.9.5 can do:** The sidebar is drawn by herdr. Config only chooses token rows and
  `agent_panel_sort = "spaces" | "priority"`. `"spaces"` groups agents by space, but there is no
  tab level, no collapse below space level, and no way for a plugin to draw into the sidebar.
  Plugins can open panes with `overlay`, `popup`, `split`, `tab` or `zoomed` placement. Those live
  inside one tab, not beside every tab. The built-in Goto picker (`prefix+g`) is already a flat
  list grouped by space.
- **Options:**
  1. **Popup tree (recommended first step).** Rebuild the `prefix+a` picker as a collapsible
     space → tab → pane tree. It keeps the summarizer preview and filtering, and `prefix+o`
     (jump to the notified pane) also opens it expanded to that pane. Switch the sidebar to
     `agent_panel_sort = "spaces"` and hide the Spaces panel's second row, so the persistent view
     is at least grouped. Fully supported; small to medium effort.
  2. **Persistent tree pane.** A plugin `split` pane running the tree, kept open in each tab by a
     `tab.created` hook, with the native sidebar collapsed (`sidebar_collapsed_mode = "hidden"`).
     It works, but it costs one pane per tab, fights zoom and layouts, and has to be re-created
     after restores. Large effort and fragile.
  3. **Upstream.** Ask herdr for a tab level and collapsible groups in the Agents panel (for
     example `agent_panel_sort = "tree"`). This is the right long-term home, and option 1 can
     stand in until it lands.
- **Effort:** option 1 medium; option 2 large; option 3 an issue plus waiting.
- **Touches:** `herdr/.local/bin/herdr-recent`, `herdr/.local/bin/herdr-summarize` (`list` gains tab
  rows), `herdr/.config/herdr/config.toml` (sidebar rows and sort, `prefix+o`), `docs/herdr.html`,
  `validate.sh`.
- **Needs the real machine:** yes. Test in a throwaway herdr session, not the live one.

## Needs decision
Which option: 1 (popup tree and grouped sidebar now; recommended), 2 (persistent pane), or 1
plus 3 (also file the upstream request)? And with option 1, should `prefix+o` open the tree at the
notified pane, or keep herdr's direct jump and leave the tree on `prefix+a`?
