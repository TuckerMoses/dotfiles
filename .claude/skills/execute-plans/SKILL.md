---
name: execute-plans
description: Execute this repo's approved implementation plans in parallel and deliver one reviewed pull request. Reviews every pending plan against the current repo, groups them into independent units, implements each unit in its own git worktree with a subagent at a model tier chosen per unit, has each add a new validate.sh check, merges everything into one integration branch, validates that branch live, runs claude-materia:adversarial-review on it, and opens a single PR for the user. Use when the user says "execute the plans", "run the pending plans", "implement the approved plans", "/execute-plans", or asks to work through docs/plans or the open plan PRs.
user-invocable: true
argument-hint: "[plan-name ...] [--dry-run]"
---

# Execute plans

Turn the approved plans for this dotfiles repo into one pull request the user can review.

- With no arguments, take every plan in the queue. With plan names, take only those.
- `--dry-run` stops after the dispatch table (Phase 3) and changes nothing.

You are the orchestrator. Subagents implement; you review their diffs, integrate, validate
and report. Read `CLAUDE.md` in the repo root first: its branch, worktree and stow rules bind
every phase here.

## Rules that hold throughout

- **Never** merge the final PR, push to `master`, force-push, close a source plan PR or delete
  a remote branch. The final PR is where this skill stops.
- **Never run `stow`, `bootstrap.sh` or an installer from a worktree.** Stow links point at the
  main checkout; running it elsewhere repoints the user's live config. Only Phase 6 touches the
  live machine, and only from the main checkout.
- **Subagents change nothing outside their worktree**: nothing in `$HOME`, no installs, no pushes.
- **Being in the queue is the approval.** Do not re-argue whether a plan is worth doing. Do
  check whether it is still correct and executable.
- Branch names are plain (`feat/...`, `plan/...`). The `claude/` prefix is reserved for automation.
- Report faithfully. A unit that failed, a check that could not be verified, a plan that was
  skipped: each is named in the PR with the reason.

## Phase 0: preconditions

Stop and tell the user if any of these fails.

1. The working directory is the main checkout (`git rev-parse --show-toplevel` equals the repo
   and `git worktree list` shows it first), on `master`, with no uncommitted changes to tracked
   files, and level with `origin/master` after `git fetch`.
2. `gh auth status` succeeds.
3. Run `./validate.sh` and keep the full output as the **baseline**. Failures that exist before
   you start are recorded, not blamed on a plan.

Then tell the user in two lines what is about to happen, including that Phase 6 will switch the
live config to the integration branch and may install tools.

## Phase 1: gather the queue

Two sources:

- **Pending plans on `master`:** rows marked `pending` in `docs/plans/README.md`.
- **Open plan PRs:** open PRs whose head branch starts with `claude/plan/`. The plan is the one
  `docs/plans/*.md` file the PR adds (not `README.md`). Read it with
  `git show origin/<head>:docs/plans/<file>`. Do not merge or rebase these PRs: they all edit
  the same shared files and conflict with `master`.

```bash
grep -E '^\| \[.*\| `pending`' docs/plans/README.md | sed -E 's/^\| \[([^]]+)\].*/\1/'
gh pr list --state open --limit 100 --json number,headRefName,files -q '.[] | select(.headRefName|startswith("claude/plan/")) | "#\(.number)\t\(.headRefName)\t\([.files[].path | select(startswith("docs/plans/") and (endswith("README.md")|not))] | join(","))"'
```

## Phase 2: review each plan against the repo as it is now

Plans can be months old. For each one, read the plan and the files it touches, check what is
already installed or configured on this machine, and classify it:

| Verdict | Meaning | What happens |
|---|---|---|
| `ready` | Correct and executable as written | Dispatched |
| `amended` | Right goal, stale details (moved files, tmux-only parts now that herdr is the multiplexer, steps already done, a different theme) | Dispatched with your written amendments |
| `blocked` | Needs a decision only the user can make, or something that is not on this machine | Not dispatched; the PR states the exact decision needed |
| `done` | Already true on `master` | Not dispatched; marked done with the evidence |

Write amendments as concrete instructions, not as doubts. Note for each plan what it needs
**outside the repo** (a file in `$HOME` that a new stow package would replace, an entry in
`~/.zshrc.local`, a tool to install). Those are handled in Phase 6 by you, never by a subagent.

## Phase 3: units, tiers and the dispatch table

**Units.** Plans that would edit the same config file, or that depend on each other, go into
one unit and are implemented in order by one agent. Everything else is its own unit. Units run
in parallel, so two units must never need the same package file.

**Tier.** Choose the cheapest model that is sufficient for the unit, and write one line saying why.

| Tier | Use when |
|---|---|
| `haiku` | One config file, the plan gives the exact lines, nothing to design |
| `sonnet` | The default: a new stow package, several files, `bootstrap.sh` changes, some judgment |
| `opus` | Logic in scripts (`validate.sh`, `herdr-summarize`), a migration that depends on machine state, or a plan you had to amend heavily |

If a unit comes back failing its own checks twice, re-dispatch it once at the next tier up.

Print the dispatch table: unit, plans and their sources, verdicts, amendments in brief, tier
and reason, and the list of blocked or done plans. With `--dry-run`, stop here.

## Phase 4: dispatch

1. Create one worktree per unit, each on its own branch from `master`:
   `git worktree add .worktrees/<unit> -b plan/<unit> master`
2. Launch **all units in a single message** so they run in parallel, each with the Agent tool
   and the `model` chosen in Phase 3. The brief is the agent's only context. Give it:
   - the absolute worktree path, and the instruction to work only there;
   - the full plan text and your amendments;
   - the rules: no `stow`, no `bootstrap.sh`, no installs, nothing outside the worktree, no push;
   - **the validation requirement** (below);
   - the static checks it can run from a worktree: `bash -n`, `zsh -n`, a Python compile,
     `HERDR_CONFIG_PATH=<file> herdr config check`, `ghostty +validate-config --config-file=<file>`,
     and sourcing a tmux config into a throwaway server
     (`tmux -L <name> -f /dev/null new-session -d 'sleep 5' \; source-file <file>`);
   - the files it must **not** edit, because you own them: `CHANGELOG.md`, `CLAUDE.md`,
     `README.md`, `docs/plans/README.md`, `docs/herdr.html`;
   - what to return: files changed, the check it added and how it fails, tools that need
     installing, anything needed outside the repo, every deviation from the plan, and what it
     could not verify from a worktree.
3. It commits on its branch in the repo's commit style and stops.

**The validation requirement.** Every unit adds at least one new check to `validate.sh` that
fails when that unit's result is not live on the machine: not merely "the file exists", but the
program loads it and uses it. Stow links for a new package are already checked, because
`validate.sh` reads the package list from `bootstrap.sh`; the new check covers what that cannot.
The agent must show the check can fail, by running its logic against a deliberately broken copy.
A check that cannot fail is worse than none. `validate.sh` stays read-only: checks never install,
stow, reload or edit.

## Phase 5: integrate

1. For each unit, **read the diff**, not only the report. Reject a unit whose check cannot fail,
   that edited a file you own, or that reached outside its worktree. A rejected or failed unit
   is re-dispatched once, or left out and reported.
2. Create the integration branch in its own worktree:
   `git worktree add .worktrees/integration -b feat/execute-plans-<YYYY-MM-DD> master`
3. Merge the unit branches into it one at a time with `--no-ff`. `bootstrap.sh` and
   `validate.sh` are edited by most units, so expect conflicts there: they are additive, keep
   both sides, then re-run the static checks.
4. Write the shared files yourself, once: copy each executed plan into `docs/plans/` if it came
   from a PR, set statuses in `docs/plans/README.md`, add the `CHANGELOG.md` entry, update the
   package table in `CLAUDE.md` and the tree in `README.md`, and update `docs/herdr.html` if
   anything a herdr user would see changed.
5. Push the integration branch. Remove every unit worktree and the integration worktree.

## Phase 6: validate the integration branch live

This follows "Worktree testing" in `CLAUDE.md` and is the only phase that changes the machine.

1. In the main checkout: `git checkout feat/execute-plans-<date>`. The stowed config is now the
   branch's version.
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

- **intent:** these plans (name them), implemented on this branch, must each match its plan and
  your amendments, must not break existing config, and each new `validate.sh` check must be able
  to fail;
- **locations:** the files changed against `master` (`git diff --name-only master...HEAD`);
- **flags:** the repo rules above, especially stow safety and `validate.sh` staying read-only.

Commit the fixes it applies. Then run `./validate.sh` again: review fixes can break things too.

## Phase 8: the pull request

Push, then open one PR against `master` with `gh pr create`. The body has, in this order:

1. **What to review first:** anything that needs the user's decision, and blocked plans with
   the exact question each one is waiting on.
2. **Plans table:** plan, source (file or PR number), verdict, tier used, result, the
   validation check added.
3. **Amendments** you made to plans, and deviations the agents reported.
4. **Machine changes from Phase 6:** tools installed, files in `$HOME` replaced (with the backup
   path), and the steps still to do by hand.
5. **Validation:** baseline against final, as counts, plus any remaining warning.
6. **Adversarial review:** rounds, what was fixed, accepted risks, and the path to its summary.
7. **Rollback:** `git checkout master && ./bootstrap.sh`, plus what that does not undo.

Then comment on each source plan PR with a link to the final PR (do not close them), and tell
the user: the PR link, that the main checkout is on the integration branch and therefore live,
and the decisions waiting on them.
