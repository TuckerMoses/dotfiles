---
status: done
created: 2026-11-17
updated: 2026-11-17
proposal: "session 2026-11-17 (herdr plugin research)"
---

# Plan: a `$jj_status` sidebar token for jj repos

## Goal
herdr-summarize reports a `$jj_status` workspace token (bookmark, else short change id, plus a dirty mark) for
workspaces whose directory is in a jj repo, shown in the spaces sidebar row. Empty everywhere else.

## Context
`[ui.sidebar.spaces]` shows herdr's `branch` and `git_status`, which say nothing useful in the jj repos. herdr core
will not add jj (issue #218, closed not planned). The summarizer already calls `workspace report-metadata` for the
`$summary` workspace token in `publish()`, so this is one more token on the same call; no third-party plugin.

Machine facts (2026-11-17): jj 0.43.0. jj repos: `~/Vault` and `~/roadmap` (colocated with git), `~/aios/lib` and
`~/aios/containers/life` (jj only). `jj log -r @ --no-graph --ignore-working-copy -T ...` takes ~0.05 s in Vault.
herdr's `workspace list` has no directory; `pane list --workspace <id>` gives each pane's `cwd`.

## Steps
1. `herdr/.local/bin/herdr-summarize`:
   - `workspace_dir(panes)`: the `cwd` of the workspace's first pane in creation order (`pane_order`), the
     workspace's home. `do_pass` already builds `panes_by_ws`; pass it to `publish`.
   - `jj_status(path)`: return "" unless `jj` is on `SEARCH_PATH` and a `.jj` directory exists at `path` or an
     ancestor (walk up in Python, no subprocess). Else run
     `jj log -r @ --no-graph --ignore-working-copy --color never -T <template>` with `cwd=path` and
     `timeout=2`; template: `@`'s local bookmarks if any, else `@-`'s, else `change_id.shortest(8)` (two `jj log`
     calls at most, or one revset/template that yields both), followed by `*` when `@` is non-empty. Any error or timeout returns "" and logs once per pass. `--ignore-working-copy` means it never
     snapshots; the dirty mark reflects jj's last snapshot. Say so in the help text.
   - Cache per directory within a pass (two workspaces in the same repo cost one call).
   - `publish()`: the workspace target's tokens become `{"summary": ..., "jj_status": jj_status(dir)}`. Empty
     clears it (`--clear-token`), so non-jj workspaces render as today.
   - Help text: document `$jj_status`.
   - Do not add events: `pane.focused` and turn ends already trigger passes. `workspace.focused` only if testing
     shows a stale token on workspace switch with no pane focus event.
   - Note `do_pass` only runs when `claude` is found (it is a summarizer). The token rides along; that is acceptable
     for an opt-in plugin and is documented.
2. `herdr/.config/herdr/config.toml`, `[ui.sidebar.spaces]` first row: append `{ token = "$jj_status", dim = true }`
   after `git_status`, and update the `herdr-summarizer tokens` comment to name `$jj_status`. Only that section.
3. `validate.sh`, herdr-summarizer section: checks below.

## Decision: git tokens in colocated jj repos
Keep `branch` and `git_status` in the row. herdr rows are static config, so they cannot be hidden per workspace;
replacing them with our own git token for every repo is out of scope. In colocated repos the row shows both; in
jj-only repos the git tokens are empty and `$jj_status` alone shows.

## Validation
- **The token is computed correctly**: run `herdr-summarize` in a self-test mode (add a `jj-status <dir>`
  subcommand that prints the token) against a throwaway jj repo created in a temp dir (`jj git init`, then write a
  file → expect a `*`; `jj bookmark create t` → expect `t`), and against a plain temp dir → expect empty. Skip with
  info when `jj` is absent. Fails when: the template breaks on a jj upgrade, or the non-jj case returns text.
  (Creating a temp repo under `$TMPDIR` and deleting it keeps validate.sh read-only with respect to the machine.)
- **The token is live**: when the summarizer plugin is linked and herdr runs, for each workspace whose home pane's
  cwd is in a jj repo, `herdr workspace list` shows a non-empty `jj_status` token; warn (not fail) when it is
  missing, since a pass may not have run since the workspace opened. Fails silently-never: if no jj workspace is
  open, info.
- **The row shows it**: the stowed `config.toml`'s `[ui.sidebar.spaces]` rows contain `$jj_status`.
- Show each fails against a broken copy (a template typo; the token removed from the row).

## Outside the repo
None; reload herdr config in Phase 6 and open a workspace in `~/Vault`.

## Edge cases
- A workspace whose home pane is in a subdirectory of a jj repo: the ancestor walk finds it.
- jj slow on a cold or huge repo: 2 s timeout, then empty for that pass.
- A jj repo inside a git repo or vice versa: `.jj` nearest ancestor wins; git tokens are herdr's.

## Left out
`mroth/herdr-jj-status`, `OliverGilan/herdr-jj`; a timer; per-pane jj tokens.

## As built (2026-11-17)
- One `jj log` call per working copy per pass, with a template that returns four fields: `@`'s bookmarks, `@-`'s
  bookmarks, the short change id, and the dirty mark. Bookmark names are cut to 20 characters, the last being `…`, to fit the
  34-column sidebar; several are joined with `,`.
- When a workspace's `pane list` fails mid-pass, its token is left as it was rather than cleared.
- `herdr-summarize jj-status DIR` prints the token and exits 1 when jj fails. `validate.sh` uses it on a throwaway repo
  in `$TMPDIR` and on each open space.
- Known gap: a space's home is its first pane. A space whose first pane is outside a jj repo gets no token, even when
  other panes are in one.
- No `workspace.focused` event was added.
