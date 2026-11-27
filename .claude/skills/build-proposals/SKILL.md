---
name: build-proposals
description: Take this repo's approved proposals from proposal to plan to working change, delivered as one reviewed pull request. Reads every proposal in docs/proposals/ on master, writes an implementation plan for each against the repo as it is now, implements independent units in parallel git worktrees with Opus subagents, has each add a new validate.sh check, merges everything into one integration branch, tests that branch with test/suite.sh in three environments (an isolated local HOME, a native Ubuntu guest, an emulated one) before validating it live, runs claude-materia:adversarial-review on it, and opens a single PR that deletes the executed proposals and records their plans in docs/plans/. Use when the user says "build the proposals", "run the proposals", "build what's approved", "execute the plans", "what's in the queue", "/build-proposals", or asks to work through docs/proposals.
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
  main checkout; running it elsewhere repoints the user's live config. The one exception is
  `test/suite.sh`, which stows only into a throwaway `$HOME` or inside a guest (CI and `here`: see
  "Worktree testing" in `CLAUDE.md`). Only Phase 7, and Phase 8's fixes when Phase 7 left the branch checked out
  in the main checkout, touch the live machine, and only from the main checkout;
  the one earlier change is the system-package install in Phase 5 step 6 (or Phase 6 step 4, for a package it missed).
- **A fix agent** is created from the main checkout at `.worktrees/fix-<short-name>`, on branch `fix/<short-name>` cut from
  the integration branch's HEAD, and briefed as in Phase 4 with the commit under test and the failure evidence in place of
  the plan text: in Phase 6 the failing run dir's absolute path (it may read, not write, that dir), in Phase 7 the failing `bootstrap.sh`/`validate.sh` output
  and the Phase 0 baseline lines it is compared with. It adds a `validate.sh` check only if the fix adds behaviour. Before
  merging, read its diff as in Phase 5 step 1. If it passes, merge it with `--no-ff`, then run `git worktree remove` and
  `git branch -d`, all where the integration branch is checked out (the integration worktree in Phase 6, the main
  checkout in Phase 7). If it fails those grounds, or the agent returns no commit, do not merge it: remove it with
  `git worktree remove --force` and `git branch -D`, and dispatch one replacement briefed with the reason. Stop fixing
  a failure when the replacement is also rejected or returns no commit, or when the same step fails again in the same
  environment (Phase 6), or the same `validate.sh` line fails again (Phase 7), after a fix for it; and a third fix
  in one phase is a stop. Both count yours and fix agents', across all failures and environments.
- **Subagents change nothing outside their worktree**: nothing in `$HOME`, no installs, no pushes.
  The exceptions are `test/suite.sh local`, which may create its throwaway `$HOME` under `$TMPDIR` and nothing
  else, and the Phase 8 review's fixers, which may edit the main checkout on the live path (Phase 8); the rest
  of this rule still binds them.
- **Being in `docs/proposals/` on `master` is the approval.** Do not re-argue whether a proposal
  is worth doing. Do check whether it is still correct and executable.
- **Only `master` counts.** A proposal in an open PR, on another branch, or in the scout's
  `ideas.md` is not approved. Never act on one.
- **A proposal leaves the folder only in the PR that implements it.** If that PR is not merged,
  the proposal is still on `master` and still queued.
- Branch names are plain (`feat/...`, `plan/...`, `fix/...`). The `claude/` prefix is reserved for automation.
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

Then tell the user in two lines what is about to happen, including that the system packages the branch
adds are installed before or during Phase 6, and that Phase 7 will switch the live config to the integration branch
and may install tools, after the Phase 6 test passes.

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
| `blocked` | Has a "Needs decision" or "Waiting on" section, needs a decision only the user can make, or needs something that is not on this machine | Not dispatched; stays in `docs/proposals/` |
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
  `~/.zshrc.local`, any tool to install. Those are handled by you, never by a subagent: system packages
  in Phase 5 step 6, the rest in Phase 7;
- **Edge cases** and what was deliberately left out.

Where the proposal's assumptions no longer hold (a tmux-only part now that herdr is the
multiplexer, a step already done, a different theme), the plan follows the repo, and says so
under a heading **Differences from the proposal**.

Plans written here are not committed yet. They travel with their implementation and are
committed on the integration branch in Phase 5.

For a `blocked` proposal with a "Waiting on" section, check whether the capability it names now exists on this
machine; if it does, say so and treat the proposal as `ready` once the user deletes the section. Otherwise report
what it waits on and leave the file untouched. For any other `blocked` proposal, write the exact question the user must answer. In Phase 5 it goes into
that proposal's "Needs decision" section, so the next run and the user both see it.

## Phase 3: units and the dispatch table

**Units.** Plans that would edit the same config file, or that depend on each other, go into
one unit and are implemented in order by one agent. Everything else is its own unit. Units run
in parallel, so two units must never need the same package file.

**Model.** Writing plans and implementing them both run on Opus. Every implementation agent is
dispatched with `model: "opus"`. Do not drop to a cheaper model to save cost; the adversarial
review in Phase 8 chooses its own models.

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
   - that it may run `test/suite.sh local` (not the VM environments; Phase 6 runs those) to check its own work: the suite
     is safe from a worktree and tests the committed `HEAD`, so commit first. It must still never
     stow or bootstrap by hand. A `local` that exits 3 only because a system package it adds to `bootstrap.sh` is
     missing is reported as that, and does not fail the unit;
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
5. Commit all of it on the integration branch. Remove every unit worktree; keep the integration
   worktree, because Phase 6 runs from it.
6. For each word on this host's `for pair in` line of `bootstrap.sh` on `feat/build-proposals-<date>` but not on
   `master`'s (`package:command`, or one word for both) whose command fails `command -v`, install its package
   as `bootstrap.sh` would: `test/suite.sh local` refuses to start without them.
   Tell the user which, then install without waiting; if an install fails or needs a password, stop
   before Phase 6, report the packages installed so far, the one that failed, and its command, and leave the integration worktree in place.

## Phase 6: test in three environments

The live machine is touched only after the integration branch passes one suite in three places,
all on the same commit. `test/README.md` describes the suite.

```bash
test/suite.sh local         # throwaway $HOME, env -i, its own herdr server and tmux socket dir
test/suite.sh vm-native     # fresh Ubuntu guest, this machine's arch (HVF or KVM)
test/suite.sh vm-emulated   # fresh Ubuntu guest, the other arch (TCG: several times slower)
```

1. Run all three from the integration worktree, in parallel, each as a background command, and
   wait for all three to exit.
2. The suite tests the committed `HEAD` of the checkout it runs from, copied as a git bundle;
   uncommitted changes are not tested. Commit everything first, and commit nothing to the branch
   until all three runs have taken their bundle: `local` when its log prints `local: HOME=`, a
   guest only once it has booted, when its log prints `suite running in the guest`. The report's
   `commit` row is the commit a guest bundled, so step 6 can check it.
3. Exit codes: `0` passed, `1` the suite failed, `3` the environment could not be started.
   - On `1`: read the run dir (`log`, `result`, `validate.txt`; for guests `console.log` and
     `guest/`), fix on the branch (small fixes yourself, larger ones through a fix agent), commit, and re-run that environment fresh. Do not `--resume` a guest after a fix: it
     keeps the clone it already has. A fix is a new commit, so re-run any environment that passed
     on the old one. A guest run's `log` (not `guest/log`) whose `timed out after` line says `no guest output for` under 300s,
     or a network or download error nothing on the branch caused, has nothing to fix: re-run that environment fresh,
     unchanged, once per commit (after a timeout, with `--timeout` twice the value that ran out); this does not count
     toward the fix-agent bound. A re-run that fails the same way, or a failure the fix-agent rule says to stop on, is
     handled like `3`.
   - On `3`: report which environment and why, list the system packages installed so far (they stay
     installed), and stop the whole run (no Phase 7, 8 or 9), leaving the branch and integration
     worktree as they are until the user says how to proceed. Never skip an
     environment silently, and never go on to the live phase on two out of three.
4. `local` is fully isolated and must never be worked around. Never run herdr, `stow` or
   `bootstrap.sh` by hand against the real `$HOME` to help a failing run; a `local` that refuses
   to start (for example, a system package `bootstrap.sh` would install is missing) is a `3`, unless the package
   it names is one this branch added to `bootstrap.sh`'s loop: install it as in Phase 5 step 6 and re-run (not a fix; an install that fails or needs a password is a `3`).
5. What the suite cannot show is reported as **not tested**, never as passed: anything a headless
   guest cannot show (Ghostty rendering, clipboard, fonts on screen, sounds), model calls (the
   summarizer runs dry), `dnf` (no Fedora guest), and each plugin `bootstrap.sh` skipped in an
   environment because its build tool is missing there (name the plugin and the environments: the
   guests have no go or cargo, and `local` runs under `env -i`, so a tool only in a user directory
   such as `~/.cargo/bin` is missing there too).
6. When all three pass on the same commit, save the output of
   `test/suite.sh report <run-dir> <run-dir> <run-dir>` (a side-by-side table: each step, commit,
   wall time, exit) to the session scratchpad for the PR: removing the integration worktree deletes
   its gitignored `test/.runs/`. Then push the integration branch and remove the integration
   worktree.

## Phase 7: validate the integration branch live

This follows "Worktree testing" in `CLAUDE.md`.

0. **Ask first, and wait for a yes.** Phase 0's note told the user; this asks them. In one short
   message, say that the main checkout will be switched to `feat/build-proposals-<date>` (so the
   stowed config becomes the branch's), which files in `$HOME` will be moved aside, that
   `./bootstrap.sh` will then run (it restows, and installs whatever its `command -v`, directory or status
   checks find missing: name each, from its tool list, Oh My Zsh and its plugins, TPM and the tmux plugins, and
   herdr's Claude integration) and may be re-run after the fixes of step 5 and Phase 8, which herdr
   plugins it will install at their pins with `--yes` (every pinned plugin `herdr plugin list` does not
   show, guarded or not; one behind an `if command -v` guard only when that tool is present; one
   line each: repo, sha7, and the `[[build]]` command of its `herdr-plugin.toml` at the pin; those builds
   already ran in Phase 6, but only in the suite's throwaway `$HOME` and guests, so this is about your real herdr), that Phase 8's review fixes will be made there too, on the live branch, and the checks
   step 4 proves (one line per new check, saying whether step 4 breaks it live (and what it breaks)
   or proves it against a stub).
   Ask whether to go ahead, and wait for the user's explicit yes in this session before step 1.
   Anything else, or no answer, is a no: stop Phase 7, change nothing on the machine, and go on to Phase 8
   (in a worktree, as it says there) and Phase 9.
   This yes is the approval `CLAUDE.md` requires before an agent runs `bootstrap.sh` in the main checkout. It
   covers step 3's run, the step 4 breakages it listed, and the restows and `./bootstrap.sh` reruns of step 5
   and Phase 8 while `git diff <approved sha> -- bootstrap.sh` is empty (record the branch's commit at the yes);
   nothing else. A fix that changes `bootstrap.sh` needs a new ask that shows that diff.
1. In the main checkout: `git checkout feat/build-proposals-<date>`. The stowed config is now
   the branch's version.
2. For each file in `$HOME` that a new package will replace: copy it to the scratchpad, make
   sure the package version carries its content forward, then move the original aside so stow
   can link. List each one for the PR.
3. Run `./bootstrap.sh` (it installs missing tools, stows, and ends with `validate.sh -q`), then
   `./validate.sh` in full. Compare with the Phase 0 baseline.
4. Prove each new check once on the live machine: break what it guards, see it fail, restore. A
   check whose live break would need a command `CLAUDE.md` forbids agents (such as `herdr plugin
   install|uninstall|disable`) is proven instead against a stub on `PATH` or a deliberately broken
   copy (a fake `herdr` reporting the broken state), and the PR says which checks were proven
   that way.
5. Fix failures on the branch: small ones yourself, larger ones through a fix agent. Re-run, within the fix-agent rule's bound, until no failure remains that was not in the baseline.
6. If the fix-agent rule says to stop, say so, skip Phase 8 and go to Phase 9, with the remaining
   failures under item 6 and "not run (Phase 7 stopped)" under item 7. Before that, if a failure not in the baseline breaks the
   login shell, stow links, or tmux or herdr startup, roll back first: say why and what the rollback does, and run it
   only after the user's explicit yes (the step 0 yes does not cover it). Without one, leave the machine as it is
   and report its state in the PR. The rollback, in the main checkout:
   1. Still on the branch, `stow -d . -t "$HOME" -D --no-folding <pkg>` for each package the branch adds or
      extends, so no link is left pointing at a file `master` does not have.
   2. `git checkout master && ./bootstrap.sh`.
   3. Put back each original step 2 moved aside, from its saved copy.
   4. List what stays: tools bootstrap installed, the system packages of Phase 5 step 6 and Phase 6 step 4, and
      the herdr plugins the branch installed, each with the `herdr plugin uninstall <id>` command for the user
      to run (agents may not).

## Phase 8: adversarial review

Invoke the `claude-materia:adversarial-review` skill on the integration branch and follow that
skill's own rules for the loop. Give it a manifest with:

- **intent:** these proposals (name them), implemented on this branch, must each match its plan,
  must not break existing config, and each new `validate.sh` check must be able to fail;
- **locations:** the files changed against `master` (`git diff --name-only master...HEAD`);
- **flags:** the repo rules above, especially stow safety and `validate.sh` staying read-only.

When Phase 7 left the integration branch checked out in the main checkout, its fixes are made there,
so they are live as soon as they are written (the Phase 7 step 0 ask names this). Commit the fixes
it applies, in the main checkout. Then run `./validate.sh` again: review fixes can break things too. A fix that
needs a restow or a `./bootstrap.sh` re-run gets one only if Phase 7 step 0's yes covers it.

If the user said no at Phase 7 step 0, the main checkout is on `master`: make the fixes in a new
worktree of the integration branch (`git worktree add .worktrees/integration feat/build-proposals-<date>`),
never by checking the branch out in the main checkout, and run nothing there that `CLAUDE.md` forbids in a
worktree. Check the fixes with `test/suite.sh local` on their commit before pushing, not `validate.sh`, which
checks the live machine (still on `master`). Push them, and say in the PR that they were not validated live. A no at Phase 7 step 0 does not skip
Phase 8; a Phase 7 stopped at step 6 does.

## Phase 9: the pull request

Run `git push -u origin feat/build-proposals-<date>`, then open one PR against `master` with `gh pr create`, with `--draft` after a no at Phase 7 step 0
(the body says the branch was not validated live) or a Phase 7 step 6 stop. The body has, in this order:

1. **What to review first:** anything that needs the user's decision, and blocked proposals with
   the exact question each one is waiting on.
2. **Proposals table:** proposal, verdict, result, the plan file, the validation check added.
3. **Differences from the proposals**, and deviations the agents reported.
4. **Three environments:** the Phase 6 `test/suite.sh report` table, side by side, with the
   commit and wall time of each, and the not-tested list. Say how commits added after Phase 6 were
   checked: on the live path, by `validate.sh` in the main checkout only, not the suite; after a no at
   Phase 7 step 0, by `test/suite.sh local` only (Phase 8), and not live.
5. **Machine changes from Phases 5 to 7:** tools installed, herdr plugins installed, files in `$HOME` replaced (with the backup
   path), and the steps still to do by hand.
6. **Validation:** baseline against final, as counts, plus any remaining warning.
7. **Adversarial review:** rounds, what was fixed, accepted risks, and the path to its summary.
8. **Queue after merge:** which proposals this PR deletes and which remain in `docs/proposals/`.
9. **Rollback** (none after a no at Phase 7 step 0): the Phase 7 step 6 rollback, filled in for this branch, in its order (`stow -D` on
   the branch first): the packages to `stow -D`, the backup paths, the plugins to uninstall.

Then tell the user: the PR link, where the main checkout is (on `master` after a no at Phase 7 step 0 or a
Phase 7 step 6 rollback, item 9 already run; otherwise on the integration branch and live, with any failures
of a step 6 stop), and the decisions waiting on them.
