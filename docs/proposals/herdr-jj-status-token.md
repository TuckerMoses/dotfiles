---
created: 2026-11-17
source: session 2026-11-17 (herdr plugin research)
---

# herdr sidebar: a jj status token for jj repos

- **What:** Have this repo's own herdr code report a `$jj_status` token (bookmark or change, plus a dirty mark) for workspaces that are jj repos, and show it in the spaces sidebar row.
- **Why here:** `[ui.sidebar.spaces]` in `herdr/.config/herdr/config.toml` shows herdr's `branch` and `git_status` tokens, which say nothing useful in the jj repos (vault, life, lib). herdr core will not add jj support (issue #218 closed as not planned).
- **Effort:** small.
- **Touches:** `herdr/.local/bin/herdr-summarize` or `herdr-summarizer/plugin/`, `herdr/.config/herdr/config.toml`, `validate.sh`, `docs/herdr.html`.
- **Needs the real machine:** yes.
- **Notes for the plan:** Do this in-house instead of installing `mroth/herdr-jj-status` or `OliverGilan/herdr-jj` (4 and 5 stars): they wrap the same `workspace.report_metadata` call the summarizer already makes, and herdr's own docs use a `$jj_status` token as their example. No timer: refresh on events the plugin already handles, adding `workspace.focused` only if needed. The token must be empty in non-jj repos so the row renders as it does today, and must not slow the hook; `jj` can be slow on a cold repo, so bound it with a timeout and never let it snapshot the working copy if that can be avoided. Decide in the plan whether the git tokens should be hidden for colocated jj repos.
- **Links:** https://github.com/herdrdev/herdr/issues/218, https://github.com/mroth/herdr-jj-status
