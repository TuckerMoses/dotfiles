---
status: done
created: 2026-11-27
updated: 2026-11-27
proposal: "user, 2026-11-27, during /build-proposals: replace herdr-reviewr with tuicr, one tool, not both"
---

# Plan: tuicr replaces herdr-reviewr

## Goal
Replace herdr-reviewr with tuicr (https://github.com/agavra/tuicr, MIT, v0.30.0) as the way the user reviews an
agent's diff: `prefix+alt+r` opens tuicr on the focused pane's uncommitted changes, in git and in jj repos, and the
agent reads the user's comments back through tuicr's agent skill.

## Context
- reviewr was built and installed live in this PR (`docs/plans/herdr-reviewr.md`). It needs git, so it cannot review
  the jj-only repos (`~/aios/lib`, `~/aios/containers/life`), which were the main use. Native jj support was asked for
  in persiyanov/herdr-reviewr#106, closed as not planned (2026-09-23).
- tuicr detects jj before git (`src/vcs/mod.rs`: `jj root`, then libgit2, then hg), so it reviews jj repos with no
  `.git`, colocated ones, and git repos. `-w` reviews the uncommitted working copy (jj: `@`) and skips the target
  selector.
- Read at tag v0.30.0:
  - `docs/REVIEW_CLI.md`, `docs/CLI.md`: `tuicr review list|comments|add|delete|clearc|clear`, all JSON. `review`
    touches no VCS (`src/review_cli.rs`): it reads the session store only.
  - `src/persistence/storage.rs`: the session store is `ProjectDirs::from("", "", "tuicr")`'s data dir:
    `~/Library/Application Support/tuicr/reviews` on macOS, `$XDG_DATA_HOME/tuicr/reviews` (default
    `~/.local/share/tuicr/reviews`) on Linux, both found through `$HOME`. Every `review` command, `list` included,
    creates that dir and takes a lock file in it, and may migrate or rebuild its manifest; the TUI writes a session file
    as soon as a target is active. Config is read from `$XDG_CONFIG_HOME` or `$HOME`.
  - `src/main.rs`: the TUI path detects the repo (`App::new`), writes the session file, prints
    `tuicr-session: <slug>` on stderr, and only then opens the terminal. Outside a repo it prints
    "Make sure you're in a git, jujutsu, or mercurial repository ..." and exits 1. A local slug is
    `<repo dir name>@<anchor>/<source>` when there is no `origin` (`src/slug.rs`).
  - `skills/tuicr/SKILL.md`: the agent's side (find the active session with `tuicr review list`, read the comments
    with `tuicr review comments`), plus wrapper scripts, one of them for herdr.
- Release assets carry no checksum file. GitHub lists a sha256 digest per asset, and the downloads matched them:
  `tuicr-0.30.0-x86_64-unknown-linux-musl.tar.gz` `bbd7a358c8450613177359bfbcc4bdbba68c98835311c5e424053a005610c9d2`,
  `tuicr-0.30.0-aarch64-unknown-linux-musl.tar.gz` `01ad73bfbfe957709c4e8d834d988f903159b94e0597cd14758110a0e3e89127`.
  Each tarball holds one file, `tuicr`, at its root. Homebrew has a bottle (`tuicr` 0.30.0, needs libgit2).
- herdr popups (`type = "popup"`): custom commands "run from the focused pane's working directory when Herdr can
  detect it" and get `HERDR_ACTIVE_PANE_CWD` (herdr 0.9.5 `docs/.../configuration.mdx`), the same as the lazygit and
  lazyjj popups.

## Steps (as built)
1. Remove reviewr: its install block in `bootstrap.sh` (three pins remain: vim-herdr-navigation, herdr-plus, fingers),
   its key and section in `herdr/.config/herdr/config.toml`, `herdr/.config/herdr/plugins/config/persiyanov.reviewr/`,
   `check_reviewr_binary`, `check_reviewr_config` and `REVIEWR_RULES_AT` in `validate.sh`, and the reviewr reminder in
   `herdr-plugins update`.
2. `bootstrap.sh`: `tuicr` joins the macOS brew loop. On Linux it joins the `pkg:cmd` list as a release binary
   (skipped by `missing+=`, like jj and lazyjj, and in `test/suite.sh`'s `env_local` list), installed with
   `release_bin tuicr <v0.30.0 musl URL for $arch> "$tuicr_sum" tuicr`.
3. `herdr/.config/herdr/config.toml`: a `# ── tuicr ──` section after the lazyjj popup, `[[keys.command]]`
   `prefix+alt+r`, `type = "popup"`, `command = "tuicr -w"`, `description = "review diff"`, 90% by 90%.
4. The agent skill is installed by hand, the way the environment's other third-party skills were:
   `npx skills add agavra/tuicr` (it links `~/.claude/skills/tuicr`). Bootstrap does not run it.
5. `validate.sh`, below. Docs: `CLAUDE.md` (herdr row, key list, one line on reading comments), `README.md`,
   `docs/herdr.html`, `CHANGELOG.md`, `docs/plans/README.md`; `herdr-reviewr.md` marked `superseded`.

## Validation
New checks, each shown failing:
- **tuicr runs**: `tuicr --version` prints `tuicr ...`. Fails when tuicr is not on PATH ("tuicr not on PATH, so
  prefix+alt+r opens an error"), and when it exits non-zero (a fake `tuicr` that exits 1: "tuicr --version failed:
  ...").
- **tuicr reads a git repo and a jj repo with no `.git`** (`check_tuicr_repo`): one `mktemp -d` under `$TMPDIR` holds a
  throwaway git repo (one commit, then an uncommitted edit; git runs with `GIT_CONFIG_GLOBAL=/dev/null` and
  `GIT_CONFIG_NOSYSTEM=1`), a jj repo made with `jj git init --no-colocate` (checked to have no `.git`; plain
  `jj git init` colocates), and a throwaway `HOME`. tuicr runs with `HOME` and every `XDG_*_HOME` pointed into it, so
  the real session store is never opened. In each repo: `tuicr review list --repo .` must print a JSON array, and
  `tuicr -w --no-update-check`, started in a new session with stdin `/dev/null` (no controlling terminal, so it cannot
  draw and exits; a 20 s timeout kills it otherwise), must print `tuicr-session: <repo dir name>@...`. The temp dir
  is removed afterwards. Fails when: `review list` errors; tuicr says the directory is not a repository (a fake tuicr
  that does not see jj-only repos: "tuicr -w does not see a throwaway jj (no .git) repo as a repository"); no session
  is announced. Without jj, the jj half is an info line.
- **The skill is installed**: `~/.claude/skills/tuicr/SKILL.md` exists. A warning, with the `npx` command, when it
  does not (it is a one-time hand step).
- **Popup and pane keys run something** (`check_bound_commands`): `herdr config check` accepts any command string, and
  the key-binding check covered `plugin_action` only. Every `popup` and `pane` binding's first word (after `exec`,
  with `$VAR` and `~` expanded) must be on PATH. With tuicr absent it fails with "key prefix+alt+r (popup) runs tuicr,
  which is not on PATH".

Not run live when this was built: tuicr was not installed on the machine, and the downloaded release binary was not
executed, so the pass paths of the repo check were exercised with a fake `tuicr` that mimics the stderr and JSON the
source above produces. The first live `./validate.sh` after `brew install tuicr` is the real test of them.

## Outside the repo
The user, on the live machine:
1. `herdr plugin uninstall persiyanov.reviewr`.
2. Remove reviewr's leftovers: `~/.local/bin/herdr-reviewr` (a symlink its install script made),
   `~/.local/state/herdr/plugins/persiyanov.reviewr/`, and the stale stow link
   `~/.config/herdr/plugins/config/persiyanov.reviewr/config.toml` (a restow does not remove a link whose file left the
   package), then that empty folder.
3. `brew install tuicr` (or `./bootstrap.sh`, which installs it).
4. `npx skills add agavra/tuicr`.
5. Reload herdr (`prefix+shift+r`) once the branch is checked out in the main checkout, then `./validate.sh`.

## Left out
- Colocating the jj-only repos so reviewr would work: it changes those repos to suit a tool.
- Keeping reviewr for git repos next to tuicr: two review tools, two key bindings and two ways for the agent to read
  comments, for no gain tuicr does not cover.
