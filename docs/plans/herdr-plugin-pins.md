---
status: done
created: 2026-11-18
updated: 2026-11-19
proposal: "user, 2026-11-18, during /build-proposals: pin every third-party plugin, and an easy command to update them all"
---

# Plan: pin every herdr plugin, and one command to update them

## Goal
Every third-party herdr plugin `bootstrap.sh` installs is pinned to a chosen commit, and a single command
(`herdr-plugins update`) moves the pins forward, one plugin at a time, after showing what changed in the code
that runs at install.

## Context
- `herdr plugin install` takes `--ref`; `herdr plugin update [PLUGIN] [--yes]` has no `--ref` and moves to the
  default branch's HEAD. The herdr-plus and reviewr READMEs say uninstall keeps a plugin's config dir; that was not
  tested here, and the stowed links are what `update` checks (see As built).
- What a pin pins (read 2026-11-17/18):
  - reviewr: `herdr/install.sh` reads the version from the checkout's `herdr-plugin.toml` and downloads that
    release tag's binary + `.sha256`. Pinning the commit pins the binary version.
  - fingers: `cargo build --release --locked` from the pinned source.
  - herdr-plus: `scripts/build.sh` runs `go build` when Go is on PATH, else downloads the **latest** release binary
    (not tied to the commit). Go is installed here (go1.27.3), so the installed copy was built from source.
  - vim-herdr-navigation: shell scripts, no build download.
- Installed now (`herdr plugin list --json`, `source.resolved_commit`): herdr-plus `f38df3570bea8f7ca71dc1ba11bce3b123d14402`,
  vim-herdr-navigation `7873100eb47212269005c693effb2a844986b30f`; reviewr and fingers not yet installed
  (pins `bb71050caa5d3a0b1a414527783eb7a772447f9f`, `2d9fc997ce1a95976b975da758dccc7b6e011336`).
- `validate.sh` already has `check_plugin_pins` (reads `herdr plugin install <owner/repo> --ref <sha>` lines from
  `bootstrap.sh`, compares with `herdr plugin list --json`, warns on drift).

## Steps
1. `bootstrap.sh`: add `--ref <installed sha>` to the vim-herdr-navigation and herdr-plus installs. Guard herdr-plus
   on `command -v go` exactly like fingers is guarded on cargo (skip with a message naming Go), so no machine takes
   the latest-binary fallback. Keep every `if ! herdr plugin list 2>/dev/null | grep -q <name>; then` line shape.
   Keep `--yes` in bootstrap ("the pin is the review" is superseded: the pin is a reviewed source commit and a downloaded binary is trusted to the release, see As built). Extend validate.sh's cargo exception for fingers to the same
   rule for herdr-plus without go (warn, not fail), without duplicating the logic: one small table of
   plugin → required tool.
2. New `herdr/.local/bin/herdr-plugins` (bash, `set -euo pipefail`, bash 3.2 compatible; stowed by the herdr package
   to `~/.local/bin`, which is `--no-folding`). It finds the repo through its own resolved path (like the
   summarizer hook does), so it edits the checkout the links point at, never a hardcoded path. The pins' single
   source is the `--ref` lines in that repo's `bootstrap.sh`.
   - `herdr-plugins status`: for each pinned plugin, one row: plugin, pinned (7), installed (7 or "not installed"),
     upstream HEAD of the default branch (7, via `git ls-remote https://github.com/<owner>/<repo> HEAD`), and
     "N commits behind" (via `gh api repos/<o>/<r>/compare/<pin>...<head>` when `gh` is present; else "?").
   - `herdr-plugins check`: offline, no network: exit 0 when every installed pinned plugin is at its pin; print
     one line per drift and exit 1. Not-installed plugins are reported but are not drift.
   - `herdr-plugins review <plugin> [<ref>]`: commits between the pin and `<ref>` (default upstream HEAD), then the
     diff of `herdr-plugin.toml` and of every file the manifest's `[[build]]` commands name (resolve the script
     paths from the manifest at the new sha; e.g. `herdr/install.sh`, `scripts/build.sh` and any script they
     `sh`/`bash` in turn such as herdr-plus's `install.sh`), plus `Cargo.toml`/`Cargo.lock`/`go.mod`/`go.sum`
     changes summarized as a file-level stat (superseded, see As built). Via `gh api .../compare`; pager when stdout is a tty.
   - `herdr-plugins update [<plugin>...]`: for each named plugin (default: all pinned plugins behind upstream):
     run `review`, ask `Pin <plugin> at <sha7>? [y/N]`, on yes rewrite that plugin's `--ref` in bootstrap.sh
     (exact-match sed on that one line; verify afterwards that exactly one line changed), then reinstall at the
     new ref without `--yes` (`herdr plugin uninstall <id>` then `herdr plugin install <owner/repo> --ref <sha>`;
     herdr prompts the user). On a failed install, say so and leave the edited pin in place with the command to
     retry (superseded, see As built: the pin moves after the install). End by printing `git -C <repo> diff bootstrap.sh` and a reminder to commit and to update
     `validate.sh`'s reviewr config allowlist if reviewr moved (see its plan).
   - `herdr-plugins help`.
   - Plugin id ↔ owner/repo: from `herdr plugin list --json` when installed; for not-installed plugins, from the
     manifest `id` at the pinned sha (gh api contents).
3. `validate.sh`: replace the body of `check_plugin_pins` with a call to `herdr-plugins check` (one source of pin
   logic), keeping its pass/warn wording. Add a check that `herdr-plugins` is executable on PATH from the stow
   link and its `help` runs. If `herdr-plugins` is missing, fall back to a fail saying so.
4. Nothing in `herdr/.config/herdr/config.toml` unless a key is wanted (none).

## Validation
- `herdr-plugins check` against a fake `herdr` on PATH that reports a drifted `resolved_commit` exits 1 with that
  plugin named; against the real one (herdr-plus and vim-herdr-navigation installed at their pins) exits 0.
- validate.sh's pin check fails/warns when the fake reports drift and passes on the real machine.
- `herdr-plugins update` tested with a fake `herdr` and a temp copy of the repo (bootstrap.sh edited there only):
  answering N changes nothing; answering y changes exactly one `--ref` line and calls uninstall + install without
  `--yes`.
- Missing Go: with go hidden from PATH, bootstrap's herdr-plus block skips and validate warns.

## Outside the repo
None at build time. In Phase 6 the user can run `herdr-plugins status`.

## Left out
Automatic scheduled checks; updating herdr itself; the local herdr-summarizer plugin (not pinned: it is this repo).

## As built (2026-11-18, review rewritten 2026-11-19)
- Bootstrap's `--yes` trusts a commit that was read before it was pinned: a moved pin in `review`. The first pins were
  set at wire-up, read by the agents that set them (recorded in `docs/plans/`) and approved by merging that PR; review
  diffs from a pin, so it never shows a first pin's code (read it at `github.com/<owner>/<repo>/tree/<sha>`).
- There is no separate plugin → tool table. `validate.sh` (`plugin_needs`) and `herdr-plugins` (`needs_tool`) both
  read the required tool from the `if command -v <tool>` guard in that plugin's block of `bootstrap.sh`, so
  `bootstrap.sh` remains the only source.
- `herdr-plugins check` prints one line per pinned plugin (`ok`, `drift` or `absent`). It exits 1 on drift and 2 when
  herdr can't list plugins.
- Exit codes: 0 ok (for `review`: it ran); 1 drift (`check`), a `review` target GitHub shows is not upstream's own
  commit, or an update that failed (unreadable upstream HEAD, a `<sha>` that does not resolve or is not upstream's own, a
  failed review, a failed install or pin write; a no at the `Pin ...? [y/N]` prompt is not a failure); 2 setup or other error. For
  `review`, 2 is anything other than "ran" or "not upstream's own": a GitHub or `git ls-remote` call that failed (so
  upstream's own could not be checked) or any error in the review itself. `review` writes to a temporary file and pages
  it afterwards, so its exit code is its own: quitting the pager early changes nothing, and `update`'s `y/N` always
  follows the whole review. Exit 1 comes only from that upstream check: any other exit of the review's Python, one
  that cannot compile or start included, is 2; a review that fails partway prints what it had, then a line (the pager's
  last) saying it stopped early and the rest was not shown. Ctrl-C stops `review` and `update` (130); it is not a failed review.
  There is no exit 3.
- `herdr-plugins` pins come only from lines that begin (after whitespace) with `herdr plugin install <owner/repo> --ref
  <sha>` in `bootstrap.sh`, so a quoted command in a comment adds no pin. `status`, `check`, `review` and `update`
  read the `bootstrap.sh` of the checkout the invoked script is linked from, not the current directory's; the help's
  last line names it.
- `validate.sh` checks that the `herdr-plugins` on PATH is this checkout's and reads this checkout's `bootstrap.sh`.
- **`review` shows the change; it does not judge it.** In order:
  - Pin and target are resolved to full SHAs (`gh api repos/<repo>/commits/<ref>`; the contents API 404s on a short
    SHA, which would read as "file absent"). The target must be upstream's own commit (`upstream_commit`): an ancestor
    of (or equal to) the default branch, or the commit a tag points at. GitHub also resolves commits that exist only in
    a fork (an unmerged pull request), so resolving is not enough. It exits 1 with one line saying so, and shows no review, only when the
    compare call says the default branch does not contain the target and the tag list has no match; when any of those
    calls fails it exits 2. "Nothing to review" (exit 0) is said when the target resolves to the pin's commit (a short
    sha, a branch or a tag at the pin included).
  - A header with the compare status, ahead and behind counts and the GitHub compare URL. A target whose compare status
    is neither `ahead` nor `identical` gets a `!!` line saying the commit list does not describe the whole change.
  - The commit list from the compare API. When it lists fewer commits than `ahead_by`, the output says so and points
    to the compare page.
  - The macOS/Linux `[[build]]` steps, read with `tomllib` (the first Python 3.11+ on PATH; the system
    `/usr/bin/python3` here is 3.9) under a strict schema: a list of tables, `command` a non-empty list of strings,
    `platforms` a list of strings. A step for an unknown platform name is kept, so it is shown. When the manifest does
    not parse, does not fit the schema, or there is no `tomllib`, the review says so, says the files the steps name are
    not diffed (the list reads "unknown (steps not read)") and that whether the build downloads a release was checked
    only in the build-tool files listed, and shows the manifest to read the steps in: its diff, or
    the whole file when it is unchanged.
  - Diffs (difflib unified diffs with 3 lines of context, from the files' contents at both commits, not from the
    compare API's patches, which can be truncated or missing; an added file is shown whole) of `herdr-plugin.toml`, of
    every in-repo file whose path appears in a step's words (a word, or a path-like token in one, that is a path in the
    tree, such as `scripts/build.sh` or the `./scripts/install.sh` in `sh -c "./scripts/install.sh --prefix bin"`), of
    every file such a script names after `sh`, `bash`, `source` or `.` (one level; the same path-like tokens of the
    argument, against the repo root and the script's own directory, so herdr-plus's `sh install.sh` and
    `. "$(dirname "$0")/lib.sh"` are found), and of any changed build-tool file (`build.rs`, `Cargo.toml`, `Makefile`,
    `GNUmakefile`, `justfile`, `.justfile`, `package.json`, `go.mod`, `setup.py`, `pyproject.toml`,
    `build.gradle[.kts]`), display only. Files named at the pin but no longer at the target are diffed too. Unchanged
    ones are listed as unchanged. The section is titled "build steps and the files diffed", and one fixed line after the
    list says what is not diffed: other files the build compiles or reads (listed under other changed files), scripts
    those scripts run (one level is followed), dependencies' code and downloaded binaries; other changed files include
    the plugin's own code, which runs whenever herdr calls it. Text is split into lines on `\n` only, so `\r`, `\x0c`,
    U+2028 and the other separators Python's `splitlines()` would drop reach the sanitizer.
  - When a step or one of those files mentions a release download, the release-tag section. For `releases/latest`: a
    fixed line that the build downloads the release that is latest at install time, which is not tied to the commit or
    the manifest version (herdr-plus's fallback; bootstrap installs herdr-plus only with Go, so it builds from source).
    For `releases/download`: which tag (`v<version>` or `<version>`, annotated tags dereferenced) exists for the
    manifest's top-level `version` (read with `tomllib` when there is one) and whether it points at the target, or that
    the tags could not be read (a failed dereference of a found tag included). The line names the tag as the manifest
    version's; when the build also reads `releases/latest`, it adds that the build file at the target shows which one it
    downloads. That is a fact about the tag; the downloaded binary is not in the diff, and the output
    says so.
  - `Cargo.lock` and `go.sum` package changes: one `+ name version` or `- name version` line each, with a Cargo
    package whose source is not crates.io marked with its source. A lock file that changed with no package name,
    version or source changing (checksums or hashes) gets a line saying so. The packages' own code is not shown.
  - Every other changed file by name, status and +/- counts, so nothing changes silently; their patches are on the
    compare page. When the compare API's 300-file limit is reached, the output says so.
  - A diff-size note when the diffs shown exceed 600 lines, pointing to the compare URL (information, not a gate).
  - It ends with: "This shows what changed; it does not judge it. Read it (and the compare page) before pinning."
- Output sanitizing (`clean()`): everything printed comes from GitHub, so control characters and invisible, format
  and bidi Unicode (categories Cc, Cf, Zl, Zp, Mn, Me, Cn, Co, Cs, plus blank filler letters and variation selectors)
  are shown as `<U+XXXX>`, never removed. In install-time code (the steps, the diffs of the files above, lock-file
  lines) every other non-ASCII character is shown that way too, so a look-alike letter is visible. When invisible or
  bidi characters appear in install-time code, one `!! Invisible or direction-changing characters ...` line says so,
  as information. The pager is `less -FX`, without `-R`, and only when stdout is a terminal; it reads the finished
  review from a temporary file. Each `gh` call times out
  after 90 s, API paths are percent-encoded, and `git ls-remote` runs with `GIT_TERMINAL_PROMPT=0`.
- **Why review shows rather than judges.** Between 2026-11-18 and 2026-11-19 `review` grew from a diff viewer into a
  pattern scanner that tried to decide whether other people's install scripts fetch code it could not see: fetch
  words and package managers, moving-target URLs, implicit build inputs (`build.rs`, `Makefile`, `justfile`,
  `Cargo.toml` and others), comment and line-continuation parsing per language, follow depth and file limits, a patch
  budget, reasons carried over from the pin, and an "incomplete" verdict (exit 3) with an override variable. Each of
  14+ automated review findings extended the scanner, and none could make it complete: a heuristic text match on
  shell, make and other languages always has another form it does not see, while an exit 0 read like "safe". The
  script went from 324 to 1,115 lines. The repo is moving to Nix, whose sandboxed builds make hidden install-time
  fetches impossible, which makes the detection moot. The user decided on 2026-11-19 that `review` shows the change
  and leaves the judgement to the reader; the scanner, the "incomplete" verdict and its override were removed. What
  was removed for implicit inputs is their detection: since `b7e2aa6` the build-tool files listed above are diffed when
  they change, with no verdict. Do not add analysis back.
- `update <plugin> [<sha>]` runs `review` against the target (the `<sha>`, else upstream HEAD), refuses on exit 1 or 2,
  and otherwise asks `Pin <repo> at <sha7>? [y/N]`.
- `update` is the user's: it dies unless stdin and stdout are terminals, and reads every confirmation from `/dev/tty`,
  so piped input cannot answer it. This does not stop an agent that spawns a pty; `CLAUDE.md` does. `validate.sh` only
  calls `check` and `help`, which need no terminal. Tested with a fake `herdr` on PATH and `expect` for the pty: the
  non-tty refusal, a failing plugin list, declining and accepting the reinstall at the pin, a failed install with
  rollback, a no at herdr's prompt (at the target and at the pin: one prompt, the old commit back with `--yes`, exit 1),
  and a `bootstrap.sh` that cannot be written.
- `update` installs before it pins: `herdr plugin uninstall`, `herdr plugin install <repo> --ref <new>` (no `--yes`),
  and only on success the `bootstrap.sh` line moves (`set_pin` rewrites exactly one `--ref` line). herdr's own prompt
  comes after the uninstall. If the install does not complete (a no at herdr's prompt, or a failed build or download),
  it reinstalls the old commit with `--yes` (no second prompt), leaves `bootstrap.sh` alone and counts the plugin as not
  updated (exit 1); Ctrl-C at herdr's prompt leaves the plugin uninstalled until `./bootstrap.sh`. If the pin line cannot be rewritten after a
  successful install, it says so with the full sha to set by hand and counts the plugin as failed. A plugin that is not
  installed here only gets its pin moved, since its build cannot be tried: `update` proves a build only for installed
  plugins, so a commit that does not build is pinned and fails later under bootstrap's `--yes`. An unreadable upstream
  HEAD counts as a failed update (exit 1). A missing build tool moves nothing. If `herdr plugin list --json` fails,
  `update` stops before reviewing anything, because an unreadable list is not an empty one.
- A plugin installed at a commit other than its pin (a pull on another machine, a branch switch, a hand reinstall) is
  offered a reinstall at the pin first, with no review (the pin is the reviewed commit), using the same
  uninstall/install/rollback code; bootstrap skips installed plugins, so nothing else converges it. `validate.sh`'s drift
  warning points at `herdr-plugins update <plugin>`.
- After an install, `update` checks that the plugin's stowed config folder (when this repo has one) is still linked
  in place, and says to run `stow --no-folding herdr` from the main checkout when it is not, and to move the file stow names in a
  conflict (under `~/.config/herdr/plugins/config/<plugin id>/`) aside (a reinstall may have written defaults where a link was; untested). Only
  herdr-plus and reviewr have stowed config, so only they get the hint. Whether `herdr plugin uninstall` removes that
  folder was not tested (the plugins' READMEs say it keeps it).
- When `update` moves herdr-plus or reviewr it reminds the user to re-read that plugin's config rules at the new pin and
  update the matching `HERDR_PLUS_RULES_AT` or `REVIEWR_RULES_AT` in `validate.sh`.
- `update` edits the `bootstrap.sh` of the checkout the script is linked from while reinstalling plugins on the live
  machine, so the user runs it through the stowed `~/.local/bin/herdr-plugins` in the main checkout, on a branch created
  there, and commits the pin bump: the user runs it in the main checkout (`CLAUDE.md`'s pin rule), not in a worktree.
  `update` refuses to run when the checkout is a linked worktree (git's dir and common dir differ), before any prompt,
  review or install; it does not refuse on `master`. `status`, `check` and `review` are safe anywhere, but report on
  the checkout the script is linked from. The main checkout is the first entry of `git worktree list`.
- `update <plugin> <sha>` (one plugin only; the sha is the last argument, 7 to 40 lowercase hex characters; a tag name
  is not accepted, give the commit it points at) moves that plugin to the commit instead of upstream HEAD, for example a
  tagged release (the release-tag line in `review` names the tag's commit). The sha is resolved to a full sha first,
  then reviewed (which applies the upstream-own check), installed and pinned as that commit. A last argument that is
  neither a pinned plugin nor hex is reported with that hint.
- Measured read-only on 2026-11-19 with the script at `daaae65`, through a scratch `bootstrap.sh` (herdr-plus pinned
  at `487b1e3`, fingers at `590d48b`), exit codes taken directly: `review herdr-fingers 2d9fc99...` exits 0 with three
  commits, no files diffed and eight `Cargo.lock` package bumps; `review herdr-plus f38df35...` (82 commits) exits 0
  with diffs of the manifest, `scripts/build.sh`, the `install.sh` it runs, `Makefile`, `go.mod` and the removed
  `old/Makefile` (668 diff lines, so the 600-line size note), the release-tag section (the build downloads the latest
  release, not tied to the commit; tag `v0.1.24`, the manifest version, at `bfd69da`, not the target, with the clause
  that the build also reads `releases/latest`), 30 added `go.sum` packages and 123
  other files listed; `review herdr-reviewr 7b020de...` (a fork-only pull request commit) exits 1 from the upstream
  check; `review herdr-fingers 590d48b` (the pin's short sha) says nothing to review.
- `validate.sh` records the commit each copied upstream rule set matches (`HERDR_PLUS_RULES_AT`, `REVIEWR_RULES_AT`)
  and warns when `bootstrap.sh` pins a different one. Plugin drift stays a warning because the plugin still works.
