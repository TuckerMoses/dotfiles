---
status: done
created: 2026-11-18
updated: 2026-11-18
proposal: "user, 2026-11-18, during /build-proposals: pin every third-party plugin, and an easy command to update them all"
---

# Plan: pin every herdr plugin, and one command to update them

## Goal
Every third-party herdr plugin `bootstrap.sh` installs is pinned to a reviewed commit, and a single command
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

## As built (2026-11-18)
- There is no separate plugin → tool table. `validate.sh` (`plugin_needs`) and `herdr-plugins` (`needs_tool`) both
  read the required tool from the `if command -v <tool>` guard in that plugin's block of `bootstrap.sh`, so
  `bootstrap.sh` remains the only source.
- `herdr-plugins check` prints one line per pinned plugin (`ok`, `drift` or `absent`). It exits 1 on drift and 2 when
  herdr can't list plugins.
- Exit codes: 0 ok; 1 drift (`check`) or an update that failed (unreadable upstream HEAD, a `<sha>` that does not
  resolve or is not upstream's own, refused or failed review, failed install or pin write; a plugin the user declines is
  not a failure); 2 setup error; 3 review incomplete, from `review` only (`update` reports a refused incomplete review
  as 1).
- `herdr-plugins` pins come only from lines that begin (after whitespace) with `herdr plugin install <owner/repo> --ref
  <sha>` in `bootstrap.sh`, so a quoted command in a comment adds no pin. `status`, `check`, `review` and `update`
  read the `bootstrap.sh` of the checkout the invoked script is linked from, not the current directory's; the help's
  last line names it.
- `review` parses manifests with `tomllib` when a Python 3.11+ is on the machine. The system Python here
  (`/usr/bin/python3`, 3.9) lacks it, so there a line parser reads single-line `[[build]]` `command`/`platforms` arrays
  only and the review is marked incomplete. The `[[build]]` schema is strict: a list of tables, `command` a non-empty
  list of strings, `platforms` a list of strings; anything else, and any platform name other than
  macos/linux/windows, makes the review incomplete (such a step is still shown).
- `validate.sh` checks that the `herdr-plugins` on PATH is this checkout's and reads this checkout's `bootstrap.sh`.
- Hardened after an automated security review (2026-11-18) and the adversarial review of this branch before merge:
  - The manifest and every build file are diffed from their contents at both commits, not from the compare API's file
    list, which can be truncated or leave out patches. Scripts the build ran at the old pin are diffed as well. Both
    refs are resolved to full SHAs first, because the contents API 404s on a short SHA. API paths are percent-encoded.
    Each `gh` call times out after 90 s, and `git ls-remote` runs with `GIT_TERMINAL_PROMPT=0`.
  - Every other changed text file gets its full patch within a 1000-line budget (it was 600: measured against real
    history, a bump of ten or so commits to herdr-reviewr needs about 800 lines for its source alone). That includes
    docs and licenses: a text file can be compiled in (`include_str!`, `go:embed`) from a file that did not change,
    which a review of the changed files alone cannot see. Patches are shown in three tiers, smallest first within
    each: build-adjacent paths (the `SUSPECT` pattern in the script: `scripts/`, `build/`, `herdr/`, `*.sh`, `*.bash`, `*.ps1`, `build.rs`, `Makefile`, `justfile`); then the plugin's
    source and build manifests (`.rs`, `.go`, `Cargo.toml`, `go.mod`, `rust-toolchain.toml`, not tests) and any changed
    file a changed source file embeds (the source files are read at the target, at most 60); then everything else
    (tests, docs, README/CHANGELOG, CI, formulas, website, assets). Order only: a file over the budget is not shown, in
    any tier, and makes the review incomplete; the reason says how many lines over the budget and how many dropped
    files are in each tier. Measured read-only on 2026-11-18 by pinning scratch copies N commits behind upstream HEAD:
    herdr-plus 15 back, before: exit 3 with `project.go`, `herdr.go`, `projects.go` and others not shown while `www/`
    layouts, a formula and tests were; after: all source shown, only 6 test/doc files dropped. reviewr 10 back (before
    `src/markdown.rs` dropped): exit 0; 15 back: `src/markdown.rs` and 6 tests/docs dropped; 30 back: 4 source
    files and 11 others dropped (a long review stays incomplete). Only a binary medium is listed by stats alone: an image, audio,
    video, PDF or font file name (png, jpg, gif, ico, webp, avif, bmp, tiff, mp4, m4v, mov, webm, mkv, avi, mp3, m4a,
    ogg, wav, flac, pdf, woff, woff2, ttf, otf, eot), no patch from GitHub, 0 additions and 0 deletions, AND not a
    renamed file whose old name was not media too (a text file renamed to a media name has no patch to show) AND not a
    build-adjacent path (an image under `scripts/`, `build/` or `herdr/` makes the review incomplete); a file named
    `.png` that is really text, an archive, an executable, a wasm file, or any file GitHub gave no patch for that has
    line counts, falls to the code path, where a missing patch makes the review incomplete. `Cargo.lock` and `go.sum`
    changes list the added and removed `name version` pairs (40 lines at most per lock file); the dependencies' own
    source is not reviewed. A `go.sum` entry whose hash changes at an unchanged module version is marked and makes the
    review incomplete.
  - A build that downloads a release (`releases/download` or `releases/latest` in a `[[build]]` command or a script it
    runs) runs that binary, not the reviewed source. `review` says so, looks up the tag for the manifest version
    (annotated tags dereferenced) and requires it to point at the target commit; when the tag's commit is ahead of the
    pin the reason prints the command to move to it, and otherwise says the tag is not ahead of the pin, so there is no
    tagged release ahead of it to move to (review c-6; before, it printed a command `update` would refuse as a
    downgrade). The binary is trusted to the release and not verified. reviewr's pin bb71050 is the `v0.52.2`
    tag's commit. The tag is almost never upstream HEAD, so `update <plugin> [<sha>]` takes the commit to move one
    plugin to (review, pin and install all use that sha). herdr-plus builds from source when Go is present, which the
    review cannot see, so its release-tag reason is kept anyway.
  - Output from GitHub is shown with every control character and invisible Unicode character replaced by a visible
    `<U+XXXX>` marker, not removed, and the pager runs without `-R`. Invisible characters make the review incomplete
    only in install-time code (the manifest, build files and the patches shown) or when they are bidi controls
    anywhere; in commit messages and file names they are marked and noted. In install-time code every other non-ASCII
    character is marked too, without blocking.
  - A review is incomplete (exit 3) when: the commit list is shorter than `ahead_by`; the compare API lists 300 files;
    a tree is truncated; a patch is missing or a file is over the patch budget; the manifest or a build file is in the
    tree but cannot be read; the manifest does not parse, there is no `tomllib`, or the `[[build]]` schema or platform
    names are off (above); the target is not a fast-forward from the pin (status diverged or behind); a release-binary
    build has no manifest version or no tag for it, or the tag points elsewhere; a `cargo build`/`install` has no
    `--locked`; a `Cargo.lock` adds a package from outside crates.io, or a `go.sum` hash changes at the same version;
    install-time code fetches code the review cannot see (below); the build names more than 40 files, or a file at the
    third level names another one (above); a build unit holds `\r`, `\v` or `\f`; or invisible characters appear as
    described.
  - Which files are the build (as of review c-6). The `[[build]]` steps name files; so does every
    file they name. Every token of a step or of a followed file that is a path in the tree is followed, whatever its
    type (`.sh`, `.py`, `.js`, a binary named in the build): resolved against the repo root and against the naming
    file's own directory (so `. "$(dirname "$0")/lib.sh"` and `python3 tools/dl.py` are followed), and a bare script
    name (`get.sh`, after a `cd`) against the one file of that name in the tree when nothing else resolved. Images and
    other media, `Cargo.lock`/`go.sum` and the manifest are not followed. A build tool also runs files no step names, so
    when a step's program is `cargo`, `make`/`gmake`, `just`, or `npm`/`pnpm`/`yarn`/`bun` (directly, or after `env`,
    `sudo` or `command`), the implicit inputs of that tool that exist in the tree are build files too (added in review
    c-6): `build.rs` in the repo root and in every directory that has a `Cargo.toml`; `Makefile`, `GNUmakefile`,
    `makefile`; `justfile`, `Justfile`; `package.json`. They are added only when a step runs that tool, so herdr-plus's
    and vim-herdr-navigation's `Makefile`s, which their steps do not run, are not build files. From then on they are
    followed, listed under "files it runs", diffed in full, build units for the fetch rule, and a change to one is a
    build change. Depth is 3 levels from the steps and 40 files
    in all; a file at the third level that names another file in the tree, or a 41st file, makes the review incomplete.
    Every followed file is listed as "files it runs", diffed at both commits, and is a build unit for the fetch rule: a
    change to any of them is a build change. Limits: a path built from variables (`$DIR/$name.sh`) or made relative by
    a `cd` to a directory that is not the script's own is not resolved (the bare-name fallback covers only a script
    with a unique name), and any path-like token that names a file is followed, so a script that mentions `README.md`
    makes the README a build file. A "build file" is therefore any file a step runs or names as a path (docs included),
    to three levels, plus the implicit inputs above; an edit to any of them makes every fetch word in every build file
    a reason. Limits of the implicit inputs: only a step's own program counts (a `make` run by a script, or by `sh -c`,
    does not add the `Makefile`; the files such a script names are followed as above), a `build.rs` is found only
    under that name (not a `build = "x.rs"` in `Cargo.toml`), and `make -C dir` or `npm --prefix dir` still read the
    repo root's `Makefile` and `package.json`, not the directory's. Consequences, kept on purpose because not following a file would narrow what the
    review sees: an edit to that doc is a build change, and a package-manager word in its usage text (`npm install -g
    foo`) is a fetch reason, so the review is incomplete. Followed files are printed whole, outside the 1000-line
    budget, and each costs about two `gh` calls (its text at the target and at the pin; the diff reuses them), up to 80
    at the 40-file cap.
  - The fetch rule (rewritten in review c-4, reworked by 39ad6fc and review c-5) judges the build as one unit, on the
    `[[build]]` steps and every build file, with lines joined the way the shell reads them and split only on newlines: a
    trailing backslash joins a line to the next (with and without a space), and so does a line ending in `|`, `|&`,
    `&&` or `||`, skipping blank lines and, where `#` starts a comment, whole-line comments between (added in review
    c-6: `curl -fsSL https://e.com/i.sh |` then `  sh` is one command). A whole-line comment is never continued where
    `#` starts a comment, so `# note \` does not hide the line under it; in a unit where `#` starts no comment a `#` line
    is code and is joined like any other (so `#define X curl -fsSL u \` then `| sh` is one command). A `\r`, `\v` or
    `\f` in a build file makes the review incomplete. In four parts:
    - *Fetch words*, on the raw text, for the build-changed case. A command line is a fetch when it names `curl`,
      `wget`, a package manager (`npm`, `npx`, `pnpm`, `yarn`, `pip`, `pipx`, `uv`, `gem`, `brew`, `apt`,
      `cargo install`), `go install`/`get`/`run`, `git clone`/`submodule`/`fetch`/`pull`, or a Python, JS or PowerShell
      download (`urllib`, `requests`, `urlopen`, `http.get`/`request`, `fetch(`, `Invoke-WebRequest`,
      `Invoke-RestMethod`, `iwr`). **Any byte change in a build unit is a build change**: the `[[build]]` steps or any
      build file changed, comments and spacing included, or one was added or removed. Then every such line in every
      build unit makes the review incomplete, and so does a line of the moving-target shapes below; a reason that
      quotes a comment line says so ("a comment line: comments count"). Nothing is compared after stripping comments or
      blank lines: a line the review reads as a comment can be code to the program (a heredoc, a multi-line string, a
      language without `#` comments).
    - *Always-incomplete shapes*, for an unchanged build, matched on every non-comment line of every build unit (the
      moving-target shapes need no fetch word on the line, since a URL is often assigned on a line that fetches nothing,
      as in herdr-plus's `install.sh:112`): `releases/latest`; a GitHub raw (`raw.githubusercontent.com`,
      `github.com/.../raw/` or `/blob/`), archive (`github.com/.../archive/`), `codeload.github.com` or
      `tarball`/`zipball` URL whose ref is not a commit sha (7 to 40 hex characters) or a version tag (`v1.2.3`, `1.2`;
      review c-6 inverted this from a list of branch names, which had needed a new name each round). The ref is judged
      by its shape, so only a sha or a version tag is fixed: a branch of any name, `refs/heads/<anything>`, a bare `v1`
      (major tags are often moved) and `$VAR` are reasons, and so is a `tarball` or `zipball` with no ref. The older
      host-free `/archive/refs/heads/`, `/archive/<branch>` and `/tarball/<branch>` forms still match; so do `<(curl`
      or `<(wget`; `$(curl`/`$(wget` or a backtick before them; and `eval` with `curl` or `wget` on the line. And, on a
      line that fetches: a pipe into one of these shells and interpreters (`sh`, `bash`, `zsh`, `dash`, `ksh`, `fish`,
      `pwsh`, `python`, `perl`, `ruby`, `node`, `deno`, `bun`, `php`, `lua`, `$SHELL`, `source /dev/stdin`), through a
      path or a wrapper: `| /bin/sh`, `| env bash`, `| sudo -E bash -s`, `| /usr/bin/env python3`, or into a group,
      `| (cd /tmp && sh)` (`&&` is allowed inside `(...)` and `{...}` for this scan, and `|&` counts as a pipe); or one
      of the listed package managers and tools, `go install`/`get`/`run`/`mod download` or `git clone`/`submodule`,
      named **anywhere on the line**: `npm`, `npx`, `pnpm`, `yarn`, `pip`, `pipx`, `uv`, `gem`, `brew`, `apt`,
      `cargo install`/`add`, `bun add`/`install`/`x`, `bunx`, `uvx`, `deno run`/`install`, `bundle install`, `dnf`,
      `yum`, `apk`, `nix`, `conda`, `mamba`, `rustup`, `docker pull`, `gh release download`, `gh repo clone`. The
      lists were extended once, in review c-6, and `rsync`, `scp` and `ssh` joined the fetch words (they matter in a
      changed build only); they are a heuristic and are not extended further by rounds of review. A package-manager
      word is itself a fetch word, so that second family applies on any line that names one, with no `curl` needed.
      Where on the line only changes the reason's wording: at command position (start of the line, after `;` `&` `|`
      `(` `!` `{` a backtick or `$(`, `then`/`do`/`else`/`elif`/`if`/`while`/`until`/`sudo`/`exec`/`time`/`nohup`/
      `env`/`xargs`, `-c` or `eval` and a quote, `VAR=value`, a path, `python3 -m`) the reason names the word
      matched; elsewhere it adds "named off command position, which still counts". So an `echo` or usage message, an
      argv list (`["npm", "install"]`), `timeout 30 npm install` and `command pip install` are reasons. The
      interpreter word of a pipe must stand alone, so `| tee install.sh` and `| grep shell` are not. A reason is built
      from the match: the pipe case quotes the pipe, the other case quotes the word.
    - *Comments.* A line is a whole-line comment only when it starts with ASCII spaces or tabs and `#` (a non-ASCII
      blank such as U+00A0, or a control character such as U+001C, is not a blank to the shell, so such a line is a
      command), and only in a unit where `#` starts a comment: files ending `.sh`, `.bash`, `.zsh`, `.ksh`, `.py`,
      `.rb`, `.pl`, `.toml`, `.yml`, `.yaml` or `.mk`, `Makefile`, `justfile`, or a file whose first line is a
      `#!` shell, python, ruby or perl shebang. In any other unit (a `.c` file with `#define`, a `.js` file, a script
      with no such name or shebang) every line is code. In an unchanged build a comment line is skipped, so usage text
      does not make a plugin permanently incomplete; in a changed build comment lines count.
    - *History.* In review c-4 (9c90994) the decision was narrower: a change that only added, dropped or reworded
      whole-line `#` comments or blank lines was not a build change, and package managers, `go` and `git clone` counted
      only at command position. The automated security review of that commit reversed it in 39ad6fc (f-c-4-5a, the one
      loosening allowed in c-4, is gone): the review is fail-closed, so a false positive is read and, if right,
      overridden, while a miss is not seen at all. The narrow form dropped `command pip install`,
      `arch -arm64 brew install`, `timeout 60 npm install` and a Python helper's `subprocess.check_call(["pip", ...])`.
      Matching changes after that only add matches (review c-5: non-ASCII blanks, wrapped pipes, github.com raw/blob
      and `/archive/stable|nightly`; review c-6: pipes wrapped across lines, `#` lines joined by a backslash in units
      without `#` comments, the ref test on GitHub URLs, implicit build inputs, longer tool lists). Shown for c-6 on a
      scratch corpus: 5,850 URL lines (every host shape against branch, tag and sha refs and ten endings), and 71
      command lines joined in pairs by 14 separators plus 20,000 random triples (322,296 unit texts, each with and
      without `#` comments and in a changed and an unchanged build). Every reason at 9044517 is still a reason, and
      its command text is inside a reason command: the lost set is empty.
    Each reason names the file and line, and which shape matched.
    What "covered by the review that set the pin" covers: as trusted as the pin was. The initial pins were set at wire-up,
    and herdr-plus's can only move by the override; "unchanged since the pin" does not mean someone read the fetch.
    The rule is fail-closed on the listed tools and shapes, a heuristic text match and not a shell parse: a fetch by
    a tool or interpreter that is not on the lists, from a variable-built command, or from a `#` line inside a
    multi-line string, is not seen; neither is a fixed-URL fetch in a non-shell helper (`spawnSync("curl", ...)`,
    `urlopen(url)`), covered by the pin's review like a fixed `curl`, a limit. What the shapes cover: a pipe, `eval` or
    `<(...)` is flagged because the fetched text runs unread and unsaved, and a moving URL because its content can
    change with no change to the repo. A fixed URL fetched to a file and then run (one line with `&&`, or two lines;
    reviewr's real `herdr/install.sh` has that shape) passes in an unchanged build, as covered by the pin's review, and
    its content is not re-checked: a quiet review does not mean a download has not changed. Consequence: any change to a build script that downloads
    (herdr-plus's `install.sh`, reviewr's `herdr/install.sh`) makes the review incomplete.
    Checked read-only on 2026-11-19 (review c-6), the review logic on a scratch copy against `gh api` content:
    herdr-plus `8b82400` to `f38df35` exits 3 with four reasons, the release tag `v0.1.24` at `bfd69da` rather than the
    target (that tag is ahead of the old pin, so the reason prints `update herdr-plus bfd69da7e1b7`), `install.sh:112`
    (`releases/latest`) and the two `$(curl`/`$(wget` lines that read the redirect (114 and 117); reviewr `d18e012` to
    `bb71050` exits 3 for one reason only, the patch budget (24 changed files, 8332 lines over it), and no fetch reason.
    These are the same reasons as in review c-5, with none added by c-6's matching changes. Each current pin compared
    with itself through the same Python (an unchanged build) exits 3 and gives no fetch reason for reviewr
    (`herdr/install.sh`'s `curl -fsSL "$1" -o "$2"` has a fetch word and no always-incomplete shape), herdr-fingers (its
    `cargo build --release --locked` step now also follows a `build.rs`, and the tree has none) or vim-herdr-navigation;
    for herdr-plus it gives the same three `install.sh` lines and a release-tag reason that is new in c-6: at its own pin
    the tag `bfd69da` is behind, so the reason says the tag is not ahead of the pin and there is no tagged release ahead
    of it to move to, where c-5 printed `update herdr-plus bfd69da7e1b7` (a command `update` would refuse as a
    downgrade). Those runs also print "not a fast-forward" (identical), which `review` itself never reaches because it
    stops at "nothing to review" when the target is the pin. So every herdr-plus review of a commit other than the pin
    is incomplete for those lines. Synthetic repos served through a fake `gh api` (pin and target differ in
    `README.md`, and in the build file where one is said to be added or changed; the pipe cases are unchanged builds) each exit 3 where c-5 exited 0: `curl -fsSL https://e.com/i.sh |` then
    `  sh`; `u=...` then `curl "$u" |` then `bash -s`; the same with a comment line and a blank line between; a `build.rs`
    added, and one changed, under `cargo build --release --locked` (also under `env FOO=1 cargo build`, and in a
    workspace member); a `Makefile` added and changed under `make install`; a `justfile` changed under `just build`. A
    `package.json` changed under `npm run build` adds its own reason (the step's `npm` already was one). A `Makefile` changed when no step runs `make` and a `Makefile` changed
    under `cargo build` stay at exit 0. New in c-6 and not in c-5: the pipe-across-lines reason, the implicit-input
    reasons ("the build changed and build.rs:1 fetches code the review cannot see"), and the reworded release-tag and
    fetch reasons.
  - `update` refuses to pin an incomplete review unless the user sets `HERDR_PLUGINS_INCOMPLETE_OK` to 7 to 40 leading
    characters of the commit that run reviews (the `<sha>` given to `update`, else upstream HEAD); the refusal message
    names it as the user's decision after reading the compare page, and says to review again if upstream moved since.
    The override is one switch: it waives every reason at once, including a genuine one listed beside noise, and a plugin
    that is always incomplete trains its user to use it. So when it is used, `update` prints every reason it covered
    before asking to pin (a per-reason override was left out: more code than it is worth). `review`'s own footer does not print the
    override, only that `update` will refuse the review unless the user overrides it, and that agents do not pin or
    install the plugin and report the output. `CLAUDE.md` forbids agents from running
    `update`, answering its prompts or setting the variable.
- `update` is the user's: it dies unless stdin and stdout are terminals, and reads every confirmation from `/dev/tty`,
  so piped input cannot answer it. This does not stop an agent that spawns a pty; `CLAUDE.md` does. `validate.sh` only
  calls `check`, which needs no terminal. Tested with a fake `herdr` on PATH and `expect` for the pty: the non-tty
  refusal, a failing plugin list, declining and accepting the reinstall at the pin, a failed install with rollback,
  and a `bootstrap.sh` that cannot be written.
- `update` installs before it pins: `herdr plugin uninstall`, `herdr plugin install <repo> --ref <new>` (no `--yes`),
  and only on success the `bootstrap.sh` line moves. If the install fails, it reinstalls the old commit and leaves
  `bootstrap.sh` alone. If the pin line cannot be rewritten after a successful install, it says so with the full sha to
  set by hand and counts the plugin as failed. A plugin that is not installed here only gets its pin moved, since its
  build cannot be tried: `update` proves a build only for installed plugins, so a commit that does not build is pinned
  and fails later under bootstrap's `--yes`. An unreadable upstream HEAD counts as a failed update (exit 1). A missing build tool moves nothing. If `herdr plugin list --json` fails, `update` stops before
  reviewing anything, because an unreadable list is not an empty one.
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
  there, and commits the pin bump. This is the one exception to the worktree step in `CLAUDE.md`'s session workflow.
  `update` refuses to run when the checkout is a linked worktree (git's dir and common dir differ), before any prompt,
  review or install; it does not refuse on `master`. `status`, `check` and `review` are safe anywhere, but report on
  the checkout the script is linked from. The main checkout is the first entry of `git worktree list`.
- `update <plugin> <sha>` (one plugin only; the sha is the last argument, 7 to 40 lowercase hex characters; a tag name
  is not accepted, give the commit it points at) moves that plugin to the commit instead of upstream HEAD, for example a
  tagged release. The sha is resolved to a full sha first, then reviewed, installed and pinned as that commit. It must be
  upstream's own: an ancestor of (or equal to) the default branch, or the commit a tag points at. GitHub also resolves
  commits that exist only in a fork (an unmerged pull request), so resolving is not enough: anything else is refused
  and counts as a failed update, as does one that does not resolve (the `upstream_commit` helper, added out of loop in
  3fe52dc). A last argument that is neither a pinned plugin nor hex is reported with that hint. The `<sha>` rules are
  `update`'s: `review <plugin> [<ref>]` is read-only and takes any ref GitHub resolves (a branch, a tag, a fork's
  commit) without the upstream-own check, and says "nothing to review" only for a target that starts with the pin's
  full sha, so `review herdr-plus main` (or a short sha) at the pin's own commit exits 3 (identical, not a fast-forward).
- `validate.sh` records the commit each copied upstream rule set matches (`HERDR_PLUS_RULES_AT`, `REVIEWR_RULES_AT`)
  and warns when `bootstrap.sh` pins a different one. Plugin drift stays a warning because the plugin still works.
