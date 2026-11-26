---
created: 2026-11-26
source: user (audit of live herdr-summarizer state, 2026-11-26)
---

# herdr-summarizer: labels that tell sessions apart

- **What:** Rework what `herdr-summarize` shows so the sidebar label carries the one thing that
  differs between sessions (what each one is waiting on), take heat from the transcript's last turn
  instead of the file's mtime, and use Claude Code's own recaps where it has written one.
- **Why here:** An audit of `~/.local/state/herdr-summarizer/state.json` against the 12 live agents
  on 2026-11-26 found these problems:
  1. **The status carries no information.** 34 of 43 classified sessions are `you` and none are
     `working`. Every Claude turn ends by handing back to the owner, so "you" just repeats herdr's
     own idle dot. 20 of the 24 stored states begin with "awaiting" (`awaiting decision`,
     `awaiting input`, `awaiting answers`, `awaiting owner…`). In the sidebar, 10 of 11 rows read
     "<name>: awaiting <something>".
  2. **The useful field is hidden.** `your_move` ("confirm the plan approval in the orchestrator's
     pane", "run Phase 7 in a terminal") says what each session needs. It appears only in the
     `prefix+a` preview, never in the sidebar.
  3. **Heat is wrong.** It is the transcript file's mtime. On 2026-11-26 at 00:19:28 something
     rewrote every transcript at once; the restore is the likely cause. As a result, `session-b`
     (last turn 2026-11-16) and `research` (2026-11-16) both show `<1h`. Stale detection uses the
     same clock, so sessions idle for ten days are not marked stale.
  4. **Labels freeze.** The state is rewritten only when the model calls the change material and
     there are at least 1,500 new characters. Two sessions still show summaries from 2026-11-17.
     `backend` shows "fix pass verifying" while its status is `you`.
  5. **Names are cut mid-word.** `research-prici` comes from the agent name `research-pricing`
     cut at `SHORT_MAX` = 14. The default sidebar width also cuts `research-prici: awaiting…`
     and `session-b: awaiting owner…`.
  6. **New sessions are blank.** No line is published until the first turn ends and a model call
     returns, so a fresh pane shows an empty first row (the highlighted `dotfiles-final` row in the
     screenshot). The provisional name, the first words of the opening prompt ("i want to add"),
     is not published and would say nothing anyway.
  7. **Row two repeats the tab.** Three rows read `<1h · aiOS orchestration` because they share
     tab `w3:t1`, which the summarizer itself named after the first pane.
  8. **The agent's voice leaks into descriptions.** "Next I'll commit the fix pass…" is written in
     the agent's first person.
  9. **The names shown cannot be used to address a session.** The sidebar shows three
     different names, and none of them is reliably the one `herdr agent prompt <name>` accepts:
     row one leads with the summarizer's `short` (model-written), row two is the tab label (the
     summarizer's `topic`, or one the owner typed), and the addressable herdr agent name appears
     nowhere. On 2026-11-26, 4 of 10 labelled rows matched a herdr name (`session-b`,
     `requirements`, `pi-harness`, `nixos-baseline`); `bootstrap` is `herdr-plugins`, `research`
     is `research-orchestration`, and `aios orch`, `herdr nix` and `backend` have no herdr name at
     all. No row-two value is an agent name. Pasting one into a session gets "no such agent" and a
     list of names the bar never shows.
  10. **It is about to stop working.** `worker.log` shows `claude -p` failing on 2026-11-20 and
     2026-11-25 with "this sign-in ends between 2026-11-27 and 2026-11-30". After that every
     model call fails, and labels freeze without any visible sign.
- **Proposed fixes:**
  1. Replace the `you/working/idle/done` status and the free-text state with one short **ask**,
     2 to 4 words in the imperative, taken from what `your_move` says. Examples: "approve plan",
     "run phase 7", "answer 3 Qs", "check drag on 8788". Show `—` when nothing is pending. Then the
     label `<short>: <ask>` is what differs between rows. The full `your_move` stays in the
     preview.
  2. Take heat from the timestamp of the last user or assistant entry, not from the file's mtime.
     Stale detection then works again.
  3. Where the transcript has a `system`/`away_summary` entry newer than the last summary, use it
     as the description and skip the description model call. Claude Code writes these recaps
     itself, with full context, in the owner's second person. 41 transcripts already have them.
  4. Refresh the ask on every finished turn; it is cheap and must not lag. Keep the
     material-change gate for the long description only.
  5. Publish a name the moment an agent is detected: the herdr agent name if it has one, else the
     tab label, else the cwd basename. Never publish the opening prompt's first words.
  6. Fit names to whole words or hyphen-segments: `research-pricing` becomes `pricing` when
     `research` is shared with another open session, not `research-prici`.
  7. Show a sidebar token (`$err`, red) when the last model call failed for authentication, and
     have `validate.sh` warn on auth failures in `worker.log`. Separately, move the summarizer to
     `claude setup-token`, as the warning itself suggests.
  8. **One name per session, and it is the herdr agent name.** A session that already has a herdr
     name keeps it, and that name becomes its `short` as-is; the model never renames it, because an
     orchestrator addresses it by that name. A session without one gets a name from the identity
     call, slugged to herdr's form (`aios-orch`, `[a-z][a-z0-9_-]{0,31}`, unique among live
     agents), and the summarizer sets it with `herdr agent rename <pane> <slug>`. Whatever leads
     the sidebar label then works when pasted. The model-written `topic` stays only as the tab
     name, and no longer appears on the agent row.
  9. Drop the tab from row two once the tree navigator (see `herdr-agent-tree.md`) shows tabs as
     structure.
- **Effort:** medium.
- **Touches:** `herdr/.local/bin/herdr-summarize`, `herdr/.config/herdr/config.toml` (sidebar rows),
  `validate.sh`, `docs/herdr.html`.
- **Needs the real machine:** yes, to compare labels on real sessions. Test it in a sandbox
  (`HERDR_SUMMARIZER_STATE` plus a throwaway herdr session), never against the live herdr.
- **Notes for the plan:** Before building, replay the current transcripts through both the old and
  new prompts offline (`HERDR_SUMMARIZER_STATE` pointed at a scratch dir, tabs off) and show the
  two sets of labels side by side. The auth fix (item 7, token) is urgent and independent: the
  sign-in expires 2026-11-27 to 2026-11-30.
