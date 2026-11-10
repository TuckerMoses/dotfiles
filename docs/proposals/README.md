# Proposals

The queue of approved work for this repo. **Every file in this folder on `master` is approved and
actionable.** Merging a proposal here is the approval; there is no status field.

- **Who writes them:** the scheduled "dotfiles scout" routine (as pull requests from
  `claude/proposal/*` branches, at most three open at a time), you, or any session.
- **How one is approved:** its pull request is merged, or you commit the file to `master`.
- **How one is rejected:** close its pull request with a comment saying why. The scout reads those.
- **How one is executed:** `/execute-proposals` in a Claude Code session started in `~/dotfiles`.
  It writes the implementation plan at that point, against the repo and machine as they are then,
  builds it, and opens one PR. That PR deletes the proposal and adds the plan to `docs/plans/`.

A proposal is short on purpose. It says what is wanted and why; the plan is written later, by the
skill, when it can see the machine.

## Format

One file per proposal, `docs/proposals/<kebab-name>.md`:

```markdown
---
created: YYYY-MM-DD
source: scout | user | <where it came from>
---

# <Title>

- **What:** one or two sentences.
- **Why here:** what it improves in this setup, with a number or a file reference where there is one.
- **Effort:** small / medium / large.
- **Touches:** the files or packages it would change.
- **Needs the real machine:** yes or no.
- **Notes for the plan:** known constraints, things already done, what to leave out. Optional.
- **Links:** primary sources. Optional.
```

A proposal that cannot be executed until you decide something carries one more section. While it
is present, `/execute-proposals` skips the proposal and reports the question:

```markdown
## Needs decision
<the exact question>
```

Delete the section, with your answer written into the proposal, to put it back in the queue.

No step-by-step implementation and no blocks of config: that is the plan's job.
