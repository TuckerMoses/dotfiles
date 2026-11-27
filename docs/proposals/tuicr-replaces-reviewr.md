---
created: 2026-11-26
source: user, 2026-11-26, after trying herdr-reviewr live (PR #11)
---

# tuicr replaces herdr-reviewr

- **What:** Install `agavra/tuicr`, a review TUI with vim keys, as the one tool for reviewing an agent's diff and handing line comments back. Remove herdr-reviewr entirely. Use one or the other, not both (the user's decision).
- **Why here:**
  - reviewr needs git. In jj-only repos (`~/aios/lib`, `~/aios/containers/life`) it shows nothing. Its author closed native jj support as not planned (persiyanov/herdr-reviewr#106); colocating each repo is the only workaround.
  - tuicr works in git, jj (including jj repos with no `.git`) and Mercurial repos. It ships an agent skill with a herdr wrapper (`tuicr-wrapper-herdr.sh`, needs `jq`), and the agent reads the comments itself with `tuicr review comments`, with no paste step. It also reviews GitHub PRs (`tuicr pr`).
  - Its install is simpler: Homebrew has a bottle (0.30.0 on 2026-11-26), so there is no herdr plugin, no plugin pin and no plugin build step.
  - On 2026-11-26 it had about 3.7k stars, MIT licence, last push that day.
- **Effort:** medium. Most of the work is removing reviewr cleanly: it is wired into bootstrap, validate, the herdr package, `herdr-plugins` pins and the docs.
- **Touches:**
  - `bootstrap.sh`: the brew list; the Linux release-binary block, the same `release_bin` pattern as jj and lazyjj, pinned with sha256 per architecture; the reviewr install line removed.
  - `validate.sh`: reviewr checks out, tuicr checks in.
  - `herdr/.config/herdr/config.toml`: the `prefix+alt+r` binding.
  - `herdr/.config/herdr/plugins/config/persiyanov.reviewr/`, removed.
  - The tuicr skill, vendored.
  - `docs/herdr.html`, `CLAUDE.md`, `README.md`.
  - `docs/plans/herdr-reviewr.md`, which stays as the record of what was built, with a note that this replaced it.
- **Needs the real machine:** yes.
- **Notes for the plan:**
  - **Depends on PR #11** (build-proposals 2026-11-17), which adds reviewr. Build this after #11 is merged.
  - **Removing reviewr:**
    - Its `--ref` line goes from `bootstrap.sh`, and with it `herdr-plugins`' pin for it.
    - Its key, stowed config, `REVIEWR_RULES_AT` and `check_reviewr_*` go.
    - Its install left `~/.local/bin/herdr-reviewr` and `~/.local/state/herdr/plugins/persiyanov.reviewr/` behind; the plan lists those for the user.
    - Uninstalling the plugin is the user's (`herdr plugin uninstall persiyanov.reviewr`; agents may not, per `CLAUDE.md`). Put it in the PR's hand steps.
  - **The skill is third-party agent instructions.** Vendor `skills/tuicr/` from agavra/tuicr at a pinned commit (`431347b` was HEAD on 2026-11-26) into the repo, not fetched at install time. Read all of it, and every wrapper script it runs, at that commit before vendoring. Decide where it lives: a global skill under `~/.claude/skills/` (it applies in any repo) or this repo only; the kernel's layer diagnostic applies. Its wrappers become scripts the agent runs, so they get the same review as plugin build scripts.
  - **Updating:**
    - tuicr itself updates with Homebrew. On Linux it moves with the pinned release and sha256 in `bootstrap.sh`.
    - The vendored skill moves by re-vendoring at a new commit. Say in the plan how a bump is reviewed, since the skill tells the agent what to run.
  - **A herdr key is optional.** The skill's normal flow has the agent open the pane. A `[[keys.command]]` that opens `tuicr -w` in the focused pane's directory (popup or split) is useful when you start a review yourself. `prefix+alt+r` becomes free when reviewr goes, and reusing it keeps the habit.
  - **validate.sh should prove it is live, not just installed:**
    - `tuicr` runs and reports a version;
    - `tuicr review list` works in a throwaway jj repo with no `.git` (the case reviewr could not do) and in a throwaway git repo;
    - the vendored skill matches its pinned commit;
    - a key, if bound, names a command that exists.
  - **Test suite:** the Linux guests get tuicr from the release binary. Check that `test/suite.sh`'s `local` mode, which refuses missing system packages, accepts the new brew entry.
  - **Left out:** keeping reviewr for git repos (the user wants one tool); colocating the jj-only repos (no longer needed).
- **Links:**
  - https://github.com/agavra/tuicr
  - https://github.com/agavra/tuicr/blob/main/skills/tuicr/SKILL.md
  - https://github.com/persiyanov/herdr-reviewr/issues/106
