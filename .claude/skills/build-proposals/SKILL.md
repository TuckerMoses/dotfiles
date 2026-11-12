---
name: build-proposals
description: Take this repo's approved proposals from proposal to plan to working change, delivered as one reviewed pull request. Reads every proposal in docs/proposals/ on master, writes an implementation plan for each against the repo as it is now, implements independent units in parallel git worktrees with Opus subagents, has each add a new validate.sh check, merges everything into one integration branch, validates that branch live, runs claude-materia:adversarial-review on it, and opens a single PR that deletes the executed proposals and records their plans in docs/plans/. Use when the user says "build the proposals", "run the proposals", "build what's approved", "execute the plans", "what's in the queue", "/build-proposals", or asks to work through docs/proposals.
user-invocable: true
argument-hint: "[proposal-name ...] [--dry-run]"
---

# Build proposals

Take each approved proposal for this dotfiles repo through its whole life: write its plan, build
it, validate it, and deliver everything as one pull request the user can review.

**The model.** A proposal is a short statement of something worth doing. It becomes approved by
being merged into `docs/proposals/` on `master`: whoever wrote it (the scheduled "dotfiles scout"
routine, the user, another session), merging is the approval. This skill is the only thing that
turns proposals into plans and plans into changes. When a proposal is built, the same PR
deletes it and adds its plan to `docs/plans/` as the record of what was built.

- With no arguments, take every proposal in `docs/proposals/` on `master`.
- With names, take only those.
- `--dry-run` stops after the dispatch table (Phase 3) and changes nothing.

You are the orchestrator. Subagents implement; you write the plans, review their diffs,
integrate, validate and report. Read `CLAUDE.md` in the repo root first: its branch, worktree
and stow rules bind every phase here.

## Rules that hold throughout

- **Never** merge the final PR, push to `master`, force-push, or delete a remote branch. The
  final PR is where this skill stops.
- **Never run `stow`, `bootstrap.sh` or an installer from a worktree.** Stow links point at the
  main checkout; running it elsewhere repoints the user's live config. Only Phase 6 touches the
  live machine, and only from the main checkout.
- **Subagents change nothing outside their worktree**: nothing in `$HOME`, no installs, no pushes.
- **Being in `docs/proposals/` on `master` is the approval.** Do not re-argue whether a proposal
  is worth doing. Do check whether it is still correct and executable.
- **Only `master` counts.** A proposal in an open PR, on another branch, or in the scout's
  `ideas.md` is not approved. Never act on one.
- **A proposal leaves the folder only in the PR that implements it.** If that PR is not merged,
  the proposal is still on `master` and still queued.
- Branch names are plain (`feat/...`, `plan/...`). The `claude/` prefix is reserved for automation.
- Report faithfully. A unit that failed, a check that could not be verified, a proposal that
  was skipped: each is named in the PR with the reason.

## Phase 0: preconditions

Stop and tell the user if any of these fails.

1. The working directory is the main checkout (`git rev-parse --show-toplevel` equals the repo
   and `git worktree list` shows it first), on `master`, with no uncommitted changes to tracked
   files, and level with `origin/master` after `git fetch`.
2. `gh auth status` succeeds.
3. Run `./validate.sh` and keep the full output as the **baseline**. Failures that exist before
   you start are recorded, not blamed on a proposal.

Then tell the user in two lines what is about to happen, including that Phase 6 will switch the
live config to the integration branch and may install tools.

## Phase 1: read the queue

The queue is every `*.md` file in `docs/proposals/` on `master` except `README.md`. The format is
described in `docs/proposals/README.md`.

```bash
ls docs/proposals/*.md | grep -v '/README.md$'
```

If the folder is empty, say so and stop. That is a normal result.

## Phase 2: review each proposal, then write its plan

Proposals can be weeks old and are deliberately short. For each one, read it and the files it
would touch, check what is already installed or configured on this machine, and classify it:

| Verdict | Meaning | What happens |
|---|---|---|
| `ready` | Clear enough to plan and build | Planned and dispatched |
| `blocked` | Has a "Needs decision" section, needs a decision only the user can make, or needs something that is not on this machine | Not dispatched; stays in `docs/proposals/` |
| `done` | Already true on `master` | Not dispatched; deleted in the final PR, with the evidence |

For each `ready` proposal, write its plan now as `docs/plans/<same-name>.md`. Plans are written
on Opus: if this session is not on Opus, hand the writing to an Opus agent and review what it
returns. A plan has YAML frontmatter (`status`, `created`, `updated`, `proposal`: the proposal's
source line), then:

- **Goal** and **context**, taken from the proposal;
- **Steps**: the concrete changes, with the exact files, written against the repo and machine as
  they are today, not as the proposal assumed;
- **Validation**: the `validate.sh` check this will add, and how that check can fail;
- **Outside the repo**: any file in `$HOME` a new stow package would replace, any entry in
  `~/.zshrc.local`, any tool to install. Those are handled in Phase 6 by you, never by a subagent;
- **Edge cases** and what was deliberately left out.

Where the proposal's assumptions no longer hold (a tmux-only part now that herdr is the
multiplexer, a step already done, a different theme), the plan follows the repo, and says so
under a heading **Differences from the proposal**.

Plans written here are not committed yet. They travel with their implementation and are
committed on the integration branch in Phase 5.

For a `blocked` proposal, write the exact question the user must answer. In Phase 5 it goes into
that proposal's "Needs decision" section, so the next run and the user both see it.

## Phase 3: units and the dispatch table

**Units.** Plans that would edit the same config file, or that depend on each other, go into
one unit and are implemented in order by one agent. Everything else is its own unit. Units run
in parallel, so two units must never need the same package file.

**Model.** Writing plans and implementing them both run on Opus. Every implementation agent is
dispatched with `model: "opus"`. Do not drop to a cheaper model to save cost; the adversarial
review in Phase 7 chooses its own models.

If a unit comes back failing its own checks, re-dispatch it once with what failed. A second
failure leaves the unit out and is reported; its proposals stay in the queue.

Print the dispatch table: unit, proposals, verdicts, the main differences from each proposal,
and the blocked and done proposals with their reasons. With `--dry-run`, stop here.

## Phase 4: dispatch

1. Create one worktree per unit, each on its own branch from `master`:
   `git worktree add .worktrees/<unit> -b plan/<unit> master`
2. Launch **all units in a single message** so they run in parallel, each with the Agent tool
   and `model: "opus"`. The brief is the agent's only context. Give it:
   - the absolute worktree path, and the instruction to work only there;
   - the full plan text;
   - the rules: no `stow`, no `bootstrap.sh`, no installs, nothing outside the worktree, no push;
   - **the validation requirement** (below);
   - the static checks it can run from a worktree: `bash -n`, `zsh -n`, a Python compile,
     `HERDR_CONFIG_PATH=<file> herdr config check`, `ghostty +validate-config --config-file=<file>`,
     and sourcing a tmux config into a throwaway server
     (`tmux -L <name> -f /dev/null new-session -d 'sleep 5' \; source-file <file>`);
   - the files it must **not** edit, because you own them: `CHANGELOG.md`, `CLAUDE.md`,
     `README.md`, `docs/herdr.html`, and everything under `docs/plans/` and `docs/proposals/`;
   - what to return: files changed, the check it added and how it fails, tools that need
     installing, anything needed outside the repo, every deviation from the plan, and what it
     could not verify from a worktree.
3. It commits on its branch in the repo's commit style and stops.

**The validation requirement.** Every unit adds at least one new check to `validate.sh`, under
the repo rule "New functionality needs a new `validate.sh` check" in `CLAUDE.md` (what the check
must prove, showing it can fail, and `validate.sh` staying read-only are all defined there). Stow
links for a new package are already checked, because `validate.sh` reads the package list from
`bootstrap.sh`; the new check covers what that cannot. A check that cannot fail is worse than none.

## Phase 5: integrate

1. For each unit, **read the diff**, not only the report. Reject a unit whose check cannot fail,
   that edited a file you own, or that reached outside its worktree. A rejected or failed unit
   is re-dispatched once, or left out and reported.
2. Create the integration branch in its own worktree:
   `git worktree add .worktrees/integration -b feat/build-proposals-<YYYY-MM-DD> master`
3. Merge the unit branches into it one at a time with `--no-ff`. `bootstrap.sh` and
   `validate.sh` are edited by most units, so expect conflicts there: they are additive, keep
   both sides, then re-run the static checks.
4. Update the queue and the record yourself, once:
   - for every proposal whose unit was merged: add its plan to `docs/plans/` with `status: done`,
     add a row to the table in `docs/plans/README.md`, and **delete the proposal file**;
   - for every `done` proposal (already true on `master`): delete the proposal file;
   - for every `blocked` proposal: add or update its "Needs decision" section with your question;
   - for a proposal whose unit failed: leave the file untouched.
   Then add the `CHANGELOG.md` entry, update the package table in `CLAUDE.md` and the tree in
   `README.md`, and update `docs/herdr.html` if anything a herdr user would see changed.
5. Push the integration branch. Remove every unit worktree and the integration worktree.

## Phase 6: validate the integration branch live

This follows "Worktree testing" in `CLAUDE.md` and is the only phase that changes the machine.

1. In the main checkout: `git checkout feat/build-proposals-<date>`. The stowed config is now
   the branch's version.
2. For each file in `$HOME` that a new package will replace: copy it to the scratchpad, make
   sure the package version carries its content forward, then move the original aside so stow
   can link. List each one for the PR.
3. Run `./bootstrap.sh` (it installs missing tools, stows, and ends with `validate.sh -q`), then
   `./validate.sh` in full. Compare with the Phase 0 baseline.
4. Prove each new check once on the live machine: break what it guards, see it fail, restore.
5. Fix failures on the branch: small ones yourself, larger ones through a fresh worktree and
   agent. Re-run until no failure remains that was not in the baseline.
6. If it cannot be made clean, say so. Open the PR as a draft with the failures listed, or, if
   the branch leaves the machine in a bad state, `git checkout master && ./bootstrap.sh` and
   report. Tools already installed stay installed; list them.

## Phase 7: adversarial review

Invoke the `claude-materia:adversarial-review` skill on the integration branch and follow that
skill's own rules for the loop. Give it a manifest with:

- **intent:** these proposals (name them), implemented on this branch, must each match its plan,
  must not break existing config, and each new `validate.sh` check must be able to fail;
- **locations:** the files changed against `master` (`git diff --name-only master...HEAD`);
- **flags:** the repo rules above, especially stow safety and `validate.sh` staying read-only.

Commit the fixes it applies. Then run `./validate.sh` again: review fixes can break things too.

## Phase 8: the pull request

Push, then open one PR against `master` with `gh pr create`. The body has, in this order:

1. **What to review first:** anything that needs the user's decision, and blocked proposals with
   the exact question each one is waiting on.
2. **Proposals table:** proposal, verdict, result, the plan file, the validation check added.
3. **Differences from the proposals**, and deviations the agents reported.
4. **Machine changes from Phase 6:** tools installed, files in `$HOME` replaced (with the backup
   path), and the steps still to do by hand.
5. **Validation:** baseline against final, as counts, plus any remaining warning.
6. **Adversarial review:** rounds, what was fixed, accepted risks, and the path to its summary.
7. **Queue after merge:** which proposals this PR deletes and which remain in `docs/proposals/`.
8. **Rollback:** `git checkout master && ./bootstrap.sh`, plus what that does not undo.

Then tell the user: the PR link, that the main checkout is on the integration branch and
therefore live, and the decisions waiting on them.
