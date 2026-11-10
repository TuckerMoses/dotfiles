# herdr-summarizer: support harnesses other than Claude Code

**Status:** `pending`

## Problem

herdr's own state dot works for every agent it detects. Everything `herdr-summarize` adds does not:
the label, the orange needs-you label, heat, the stale mark, the description and the nesting in the
`prefix+a` picker only appear for Claude Code sessions. A Codex, opencode or pi pane shows a dot and
an empty label.

## Where the script is Claude-specific

Three places in `herdr/.local/bin/herdr-summarize`:

1. **Finding the transcript.** `TRANSCRIPTS` is `~/.claude/projects`, and a session is located as
   `*/<session-id>.jsonl` there.
2. **Reading the transcript.** `read_transcript` parses Claude Code's JSONL: which entries are user
   and assistant prose, which are tool calls (ignored by the diff gate), and where the
   `herdr agent ...` commands and name/session pairs used for linking appear.
3. **Knowing the session.** The session ID comes from herdr's Claude integration hook
   (`herdr integration install claude`). Without an integration a pane has no `agent_session`.

Not Claude-specific, and can stay as is: the summarizing model (`claude -p` reads plain text, whatever
harness produced it), the diff gate, statuses, stale reviews, token publishing, the plugin and the picker.

## Approach

Make the transcript source an adapter chosen by the pane's `agent` field:

- `locate(agent_session) -> path`
- `read(path) -> (turns, links, name_pairs)`, the shape `read_transcript` returns today

Move the current code into a `claude` adapter first, with no behaviour change. Then add one adapter per
harness actually in use. A pane whose agent has no adapter keeps today's behaviour (no label).

herdr's `agent_session` already carries a `kind` of `id` or `path`. Harnesses whose integration reports a
`path` need no `locate` step.

## To find out before building

- Which harnesses to support first. `herdr integration status` lists the ones herdr can integrate with
  (codex, opencode, pi, copilot, droid and others); none but Claude is installed on this machine.
- For each: where its transcripts live, their format, and whether user/assistant prose can be told
  apart from tool traffic. This decides whether the diff gate works unchanged.
- Whether each integration reports a session reference at all, and as `id` or `path`.
- Whether linking (a parent driving a child through `herdr agent` commands) is visible in that
  harness's transcript. If not, those sessions are simply never nested.

## Done when

- A second harness shows labels, status and descriptions in the sidebar and picker.
- Claude sessions behave exactly as before (same labels on an unchanged transcript, no extra model calls).
- `docs/herdr.html` ("Limits worth knowing") and the `?` guide no longer say Claude only.
