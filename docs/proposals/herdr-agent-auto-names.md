---
created: 2026-11-26
source: user (hand-renaming agents is not going to happen)
---

# herdr: every Claude session gets a herdr agent name, automatically

- **What:** `herdr-summarize` gives every unnamed Claude agent a herdr agent name, sets it again if
  herdr clears it, and leads the sidebar label with that exact name. The name you see in the
  sidebar and in the Claude Code status line is then the one `herdr agent prompt <name>` accepts.
- **Why here:** The sidebar shows three different names, and none of them is reliably
  addressable. Row one leads with the summarizer's model-written `short`, row two is the tab
  label, and the herdr agent name appears nowhere. On 2026-11-26, 4 of 10 labelled rows matched a
  herdr name. `bootstrap` was really `herdr-plugins`, `research` was `research-orchestration`,
  and `aios orch`, `herdr nix` and `backend` had no herdr name at all. Pasting a sidebar name into
  a session got "no such agent" and a list of names the bar never shows. herdr names only agents
  started with `herdr agent start <name>`; anything launched by typing `claude` in a pane stays
  unnamed. The status line (`~/aios/kernel/home/.claude/statusline-command.sh`) already shows the
  herdr name when there is one, and falls back to Claude Code's own title when there is not.
- **Rules:**
  - A session that already has a herdr name keeps it, and that name becomes its `short` as-is.
    The model never renames it, because an orchestrator addresses it by that name.
  - A session without one gets a name from the identity call, slugged to herdr's form
    (`[a-z][a-z0-9_-]{0,31}`, e.g. `aios-orch`), unique among live agents. The summarizer sets it
    with `herdr agent rename <pane> <slug>`.
  - herdr clears a name when the agent exits or is replaced. If the session id is unchanged, the
    summarizer sets the same name again on its next event.
  - The model-written `topic` stays as the tab name only and leaves the agent row.
  - Name at agent detection, not at the first finished turn: use the cwd basename or tab label
    as a placeholder, then the identity call's name once it exists. Rename once, not on every
    identity checkpoint, so a pasted name keeps working.
- **Effort:** small to medium.
- **Touches:** `herdr/.local/bin/herdr-summarize`, `herdr-summarizer/plugin/herdr-plugin.toml`
  (if a new event is needed), `validate.sh`, `docs/herdr.html`.
- **Needs the real machine:** yes. Test in a throwaway herdr session (`herdr --session <name>`
  under a detached tmux, with `HERDR_SUMMARIZER_STATE` pointed at a scratch dir), never the live
  one.
- **Notes for the plan:** Check whether names survive a herdr restart with
  `resume_agents_on_restore`; if not, the re-naming rule above covers it. Check that renaming does
  not disturb an orchestrator that addresses an agent by pane ID. The `validate.sh` check: every
  live Claude agent has a herdr name, and it equals the `short` in the summarizer state.
