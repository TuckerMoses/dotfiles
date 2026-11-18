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
  default branch's HEAD. Uninstall keeps a plugin's config dir (herdr-plus and reviewr READMEs say so).
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
   Keep `--yes` in bootstrap (the pin is the review; superseded, see As built). Extend validate.sh's cargo exception for fingers to the same
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
   - `herdr-plugins review <plugin> [<sha>]`: commits between the pin and `<sha>` (default upstream HEAD), then the
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
- Exit codes: 0 ok; 1 drift (`check`) or a plugin not updated (`update`); 2 setup error; 3 review incomplete, from
  `review` only (`update` reports a refused incomplete review as 1).
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
  - Every other changed text file gets its full patch, build-adjacent paths first, within a 600-line budget. That
    includes docs and licenses: a text file can be compiled in (`include_str!`, `go:embed`) from a file that did not
    change, which a review of the changed files alone cannot see. Only a binary image is listed by stats alone, meaning
    an image file name, no patch from GitHub, and 0 additions and 0 deletions; a file named `.png` that is really text,
    or any file GitHub gave no patch for that has line counts, falls to the code path, where a missing patch makes
    the review incomplete. `Cargo.lock` and `go.sum` changes list the added and removed `name version` pairs (40 lines
    at most per lock file); the dependencies' own source is not reviewed. A `go.sum` entry whose hash changes at an
    unchanged module version is marked and makes the review incomplete.
  - A build that downloads a release (`releases/download` or `releases/latest` in a `[[build]]` command or a script it
    runs) runs that binary, not the reviewed source. `review` says so, looks up the tag for the manifest version
    (annotated tags dereferenced) and requires it to point at the target commit. The binary is trusted to the release
    and not verified. reviewr's pin bb71050 is the `v0.52.2` tag's commit.
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
    install-time code fetches something the review does not cover (`npm`, `npx`, `pnpm`, `yarn`, `pip`, `pipx`,
    `go install`/`get`/`run`, `git clone`/`submodule`, or `curl`/`wget` outside a script that names a release URL or
    on a line that pipes into a shell; comment lines are skipped); or invisible characters appear as described.
  - The fetcher trigger was checked read-only on 2026-11-18 against all four current pins (`review` from each pin's
    parent to the pin): it fired on none. Before the release-URL exemption it fired on herdr-plus's and reviewr's
    download helpers (`curl`/`wget` on `$url`), which are the handled release-download case.
  - `update` refuses to pin an incomplete review unless the user sets `HERDR_PLUGINS_INCOMPLETE_OK` to 7 to 40 leading
    characters of the upstream HEAD that run reviews; the refusal message names it as the user's decision after reading
    the compare page, and says to review again if upstream moved. `review`'s own footer does not print the override,
    only that `update` will refuse and that agents stop and report the output. `CLAUDE.md` forbids agents from running
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
  build cannot be tried. A missing build tool moves nothing. If `herdr plugin list --json` fails, `update` stops before
  reviewing anything, because an unreadable list is not an empty one.
- A plugin installed at a commit other than its pin (a pull on another machine, a branch switch, a hand reinstall) is
  offered a reinstall at the pin first, with no review (the pin is the reviewed state), using the same
  uninstall/install/rollback code; bootstrap skips installed plugins, so nothing else converges it. `validate.sh`'s drift
  warning points at `herdr-plugins update <plugin>`.
- After an install, `update` checks that the plugin's stowed config folder (when this repo has one) is still linked
  in place, and says to run `stow --no-folding herdr` from the main checkout when it is not. Whether `herdr plugin
  uninstall` removes that folder was not tested (the plugins' READMEs say it keeps it).
- When `update` moves herdr-plus or reviewr it reminds the user to re-read that plugin's config rules at the new pin and
  update the matching `HERDR_PLUS_RULES_AT` or `REVIEWR_RULES_AT` in `validate.sh`.
- `update` edits the `bootstrap.sh` of the checkout the script is linked from while reinstalling plugins on the live
  machine, so the user runs it through the stowed `~/.local/bin/herdr-plugins` in the main checkout, on a branch created
  there, and commits the pin bump. This is the one exception to the worktree step in `CLAUDE.md`'s session workflow.
  `status`, `check` and `review` are safe anywhere, but report on the checkout the script is linked from.
- `validate.sh` records the commit each copied upstream rule set matches (`HERDR_PLUS_RULES_AT`, `REVIEWR_RULES_AT`)
  and warns when `bootstrap.sh` pins a different one. Plugin drift stays a warning because the plugin still works.
