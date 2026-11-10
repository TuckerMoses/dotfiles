---
created: 2026-11-09
source: user
---

# herdr-summarizer: support harnesses other than Claude Code

- **What:** Make labels, the orange needs-you label, heat, stale marks, descriptions and picker nesting work for herdr agents that are not Claude Code (Codex, opencode, pi and others).
- **Why here:** herdr's own state dot works for every agent, but everything `herdr-summarize` adds is Claude-only. A non-Claude pane shows a dot and an empty label.
- **Effort:** medium for the first harness, small for each one after.
- **Touches:** `herdr/.local/bin/herdr-summarize`, `validate.sh`, `docs/herdr.html`.
- **Needs the real machine:** yes (the harness installed, with its herdr integration).
- **Notes for the plan:** Three places in the script are Claude-specific: where transcripts live (`~/.claude/projects`), how they are parsed (`read_transcript`), and where the session ID comes from (herdr's Claude integration). Make the transcript source an adapter chosen by the pane's `agent` field: `locate(agent_session) -> path` and `read(path) -> (turns, links, name_pairs)`. Move the Claude code into the first adapter with no behaviour change. herdr's `agent_session` already has a `kind` of `id` or `path`; a `path` needs no locate step. The diff gate depends on telling prose apart from tool traffic, so check that for each harness. Claude sessions must behave exactly as before.

## Needs decision
Which harness first? None besides Claude Code is installed on this machine (`herdr integration status` lists the ones herdr supports). This is not executable until one is in use.
