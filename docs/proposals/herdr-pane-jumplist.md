---
created: 2026-11-25
source: user
---

# herdr pane jumplist on ctrl+o / ctrl+i

- **What:** A vim-style jumplist for herdr panes, **per client**: `ctrl+o` goes back through the panes this client
  has focused, `ctrl+i` goes forward again, across tabs and spaces. Both are lowercase chords with no shift
  (`"ctrl+o"`, `"ctrl+i"` in herdr syntax). When Neovim is the foreground process in the focused pane, the key is
  sent to Neovim instead, the same way `ctrl+h/j/k/l` already behave through vim-herdr-navigation.
- **Why here:** herdr 0.9.5's built-in `last_pane` only toggles between two panes. There is no back/forward
  history, and with agent panes spread over many spaces, getting back to where you were takes several moves.
- **Effort:** medium.
- **Touches:** a new local herdr plugin in this repo (a manifest with `back`/`forward` actions plus focus hooks),
  `herdr/.config/herdr/config.toml` (two `[[keys.command]]` plugin_action bindings), `bootstrap.sh` (link the
  plugin; it calls no model, so it is not opt-in), `validate.sh`, `docs/herdr.html`.
- **Needs the real machine:** yes.
- **Notes for the plan:**
  - **Per-client is the requirement.** One shared history is wrong at every device switch, not only when two
    clients are active at once: after A → B → C on the laptop, `ctrl+o` on an iPad sitting on Q must go to Q's
    predecessor, never to C. Do not ship a shared-history fallback.
  - **What herdr gives plugins (probed live, 2026-11-25):** a space switch emits `workspace_focused`,
    `tab_focused` and `pane_focused` together, so all spaces are recorded. Action and event context carry
    workspace, tab, focused pane, `invocation_source` and `correlation_id`, but **no client identity**. That is
    what this proposal is waiting on.
  - **Identity of entries (probed live):** `pane_id` is a slot. It survived a move within a space, but changed on
    a cross-space move (`w5:p15` became `w7:p2`). `terminal_id` survived both moves. A closed pane returns
    `pane_not_found`. Record `terminal_id` plus the agent session ID, and resolve against `herdr pane list` at
    jump time. Correctness must not depend on catching `pane_moved` / `pane_closed`.
  - **Deleted panes:** prune the entry and continue in the same direction. If none remain, do nothing. Jumps never
    create panes.
  - **Server restart:** losing history is acceptable (user, 2026-11-25). Keeping it is a bonus.
  - Vim semantics: a new focus after going back truncates forward history. The plugin's own jumps are not
    recorded. Collapse consecutive duplicates. Cap the length at about 100.
  - **ctrl+i vs Tab:** these are the same byte unless herdr and Ghostty negotiate the kitty keyboard protocol
    (herdr pushes the crossterm enhancement flags, so this is likely). Verify live by pressing the key. If it
    fails, use `prefix+ctrl+i` for forward.
  - **Outside the repo:** Claude Code's `ctrl+o` (`app:toggleTranscript`) is lost in herdr panes, so add
    `ctrl+x ctrl+o` for it in `~/.claude/keybindings.json`. That file is in the kernel repo
    (`~/aios/kernel/home/.claude/`, stowed). It is a separate commit there, done by the orchestrator.
  - Leave out: re-creating closed panes, and any UI for the list.
- **Links:** upstream search, 2026-11-25: herdrdev/herdr #5986, #4999 and #4014 (client identity for plugins, a
  jump list, `HERDR_CLIENT_ID`), all closed as not planned. PRs #4922 and #5743 (native `history_back` /
  `history_forward`) were closed unmerged. Open Ideas discussions #5878, #5374 and #4242 have no maintainer reply.
  Discussion #6164 (herdr-inandout) works around this with a desktop daemon that does not run on macOS.

## Waiting on
herdr exposing which client caused a focus event and which client invoked an action: a client ID in
`HERDR_PLUGIN_EVENT_JSON` / `HERDR_PLUGIN_CONTEXT_JSON`, or per-client focus events. It is not tracked upstream
(see Links). Check herdr's release notes for it. When it lands, delete this section and the proposal is queued.
