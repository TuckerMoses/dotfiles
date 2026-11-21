---
status: done
created: 2026-11-17
updated: 2026-11-18
proposal: user
---

# Plan: Linux as a tested target, x86-64 and arm64

## Goal

Make the whole setup (bootstrap, every stowed package, herdr with its plugins and the summarizer,
`validate.sh`) work on Linux on x86-64 and arm64, prove it in a fresh VM of each architecture, and make
that proof a standing phase of `/build-proposals`: one test suite, run in three places (an isolated herdr
environment on the host, a Linux VM of the host's architecture, an emulated Linux VM of the other one).

## Context

Linux support is claimed and untested. Known gaps on `master` (7aefe6a):

- `zsh/.zshrc:9` sources zsh-vi-mode through `brew --prefix` unconditionally; `:27` aliases `launchctl`.
- `bootstrap.sh:47` (Linux package loop) omits zsh, git, curl, lazyjj, zsh-vi-mode, the Nerd Font, herdr and a
  clipboard tool; `:62` pipes the starship installer to `sh` with no `-y`; `:68` runs the atuin installer,
  which installs outside `PATH`.
- `tmux/.tmux.conf:51-53` assumes `xclip` on anything that is not Darwin.
- `validate.sh:173` (Ghostty) and `:267` (launchd) are macOS-only with no Linux counterpart or stated skip.

Facts checked on 2026-11-17:

- Host: arm64 Mac, 10 cores, 32 GB, `qemu-system-aarch64`, `qemu-system-x86_64`, `qemu-img`, firmware
  `edk2-aarch64-code.fd` and `edk2-x86_64-code.fd` in `$(brew --prefix)/share/qemu`.
- This session runs inside the user's live herdr: `HERDR_ENV`, `HERDR_SOCKET_PATH`, `HERDR_PANE_ID` and
  friends are set in the environment. Any herdr command that does not scrub them talks to the live session.
- herdr 0.9.5 publishes `herdr-linux-aarch64` and `herdr-linux-x86_64`; `https://herdr.dev/install.sh`
  installs to `${HERDR_INSTALL_DIR:-$HOME/.local/bin}`.
- starship, atuin and lazygit publish Linux release tarballs for both architectures. `lazyjj` (v0.6.1) lists
  no asset with "linux" in its name: find out in the guest what is available (differently named asset, distro
  package, `cargo-binstall`, `cargo install`).
- Ubuntu 26.04 is the newest LTS on `cloud-images.ubuntu.com/releases/`.
- Baseline `./validate.sh` from the integration worktree: 31 passed, 4 warnings, 23 failed. All 23 are "not
  linked to this checkout" (the worktree is not the stowed checkout). That is the number macOS must still show.

## Steps

### 1. The suite: `test/suite.sh <environment>`

One entry point; the environment is an argument. `test/` is not a stow package and is not referenced by
`bootstrap.sh`. Bash strict mode, section-comment style, `command -v`.

| Environment | What it does |
|---|---|
| `local` | Builds a throwaway `$HOME`, isolates the environment (below), runs the core there |
| `vm-native` | Boots a fresh Ubuntu guest of the host's architecture with hardware acceleration, runs `here` inside |
| `vm-emulated` | Boots a fresh Ubuntu guest of the other architecture under emulation (TCG), runs `here` inside |
| `here` | Runs the core against the real `$HOME` of a disposable Linux machine (a guest, a CI runner). Refuses unless `DOTFILES_TEST_DISPOSABLE=1` and `uname` is Linux |

**The core** is the same in every environment:

1. `./bootstrap.sh` (first run: installs, stows).
2. Start a herdr server for this `$HOME` without a terminal attached (find the supported way; if herdr has no
   headless start, run it inside a detached tmux on its own `-L` socket).
3. `./bootstrap.sh` again (installs what needs a running server: herdr plugins, the Claude integration).
4. `./bootstrap.sh` a third time. This is the idempotence proof: exit 0 and no `==> Installing` line.
5. Install nvim plugins headlessly (`validate.sh` must not, so the suite does), then assert nvim starts clean.
6. Link the herdr-summarizer plugin directly with `herdr plugin link` and `HERDR_SUMMARIZER_STATE` under the
   test `$HOME` (not through `install.sh`, which calls a model), trigger one subscribed event, and require the
   hook run to be logged as succeeded.
7. Assert an interactive zsh starts with nothing on stderr and with zsh-vi-mode, starship, fzf, atuin and
   zoxide loaded.
8. `./validate.sh` must exit 0.
9. Tear down: stop the test herdr server, kill the test tmux servers.

**Isolation for `local`** (all of it, enforced by the suite, not by convention):

- `HOME` is a fresh directory; every `HERDR_*`, `TMUX`, `TMUX_PANE`, `ZDOTDIR`, `XDG_*`, `STARSHIP_CONFIG`,
  `ATUIN_*` and `NVIM_APPNAME` variable is unset before anything runs; `TMUX_TMPDIR` points inside the test
  `$HOME` (`bootstrap.sh:142` reloads any tmux server it can reach, and tmux's socket is not under `$HOME`).
- Before starting a server and again before any herdr write, the suite resolves the socket herdr would use
  and aborts unless it is inside the test `$HOME`. It never runs `herdr` with the inherited environment.
- Stowing into the throwaway `$HOME` from a worktree is allowed (it is the one exception to "never stow from
  a worktree"); the suite asserts `$HOME` is not the invoking user's real home before `bootstrap.sh` runs.
- On macOS `bootstrap.sh` would `brew install` a missing tool. That is a machine change outside `$HOME`, so
  `local` first checks every brew tool is present and stops with a clear message if one is not.

**Exit codes:** 0 passed, 1 the suite failed, 3 the environment could not be started (image download, QEMU,
guest never reachable). The caller must be able to tell "failed" from "could not run".

**Output:** each run writes `test/.runs/<env>-<timestamp>/` (gitignored): the full log, a `result` file with
one line per core step (`pass`/`fail`/`skip` and why), and the `validate.sh` output. `test/suite.sh report
<run-dir>...` prints the side-by-side table used in the PR.

### 2. The VM harness: `test/lib/vm.sh`

- Image: Ubuntu 26.04 cloud image (`arm64` and `amd64`), downloaded once to
  `${DOTFILES_TEST_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-test}` and verified against the published
  `SHA256SUMS`. Each run boots a fresh qcow2 overlay on top, so the guest is always a fresh image.
- Boot: `qemu-system-<arch>`, UEFI firmware from the QEMU share dir, `-accel hvf` (macOS) or `kvm` (Linux) for
  the native guest and `-accel tcg` for the emulated one, user-mode networking with SSH forwarded to a free
  local port, no display. A cloud-init NoCloud seed creates one user with passwordless sudo and a per-run SSH
  key. Nothing in the guest is shared with the host filesystem.
- Code under test: `git bundle` of `HEAD` copied in over SSH and cloned to `~/dotfiles` in the guest. No push
  is needed, nothing is stowed from the host into the guest.
- Unattended and resumable: core steps record completion in the guest; `--resume <run-dir>` reboots the kept
  overlay and continues. `--keep` leaves the guest for inspection. Timeouts are generous for the emulated
  guest and configurable.
- Teardown always powers the guest off and removes the overlay unless `--keep`.

### 3. Linux fixes (found with the harness, not assumed)

- `bootstrap.sh`: complete the Linux branch (zsh, git, curl, unzip, fontconfig, a clipboard tool, lazyjj,
  herdr via its installer, zsh-vi-mode as an Oh My Zsh custom plugin, JetBrains Mono Nerd Font into
  `~/.local/share/fonts`), make every installer non-interactive, install user-level binaries to
  `~/.local/bin`, and for neovim, fzf and lazygit check the distro version in the guest: use the package when
  it is new enough for this config (`fzf --zsh`, LazyVim's minimum nvim), otherwise the upstream release for
  the machine's architecture. Every download selects by `uname -m`. Keep the two `for pair in` loops in the
  shape `validate.sh` parses, and keep it idempotent. `dnf` gets the same package names where they exist and
  is not tested.
- `zsh/.zshrc`: source zsh-vi-mode from brew when brew has it, else from the Oh My Zsh custom plugin; put
  `~/.local/bin` (and atuin's bin dir if its installer uses one) on `PATH` only when missing; guard the
  `launchctl` alias to macOS.
- `tmux/.tmux.conf`: copy with `pbcopy` on macOS, else `wl-copy`, else `xclip`, else tmux's own clipboard.
- `ghostty/`: Linux cannot be exercised headless. If a `ghostty` binary can be had cheaply in the arm64 guest,
  run `+validate-config` against the repo config there once and record the result; otherwise say untested.
- `herdr/`, `herdr-summarizer/`: fix whatever the guests show (the hook's `/usr/bin/python3`, `SEARCH_PATH`,
  the `lazyjj` popup).
- macOS must not change: the diff to configs is additive or guarded by OS.

## Validation

New `validate.sh` checks (read-only, each shown to fail against a broken copy):

1. **zsh starts clean and zsh-vi-mode is loaded**, on both OSes. Fails today on Linux (`brew: command not
   found`); fails on either OS if the plugin is missing.
2. **Linux tools**: the second `for pair in` loop now lists everything bootstrap installs on Linux, so the
   existing loop at `validate.sh:70` covers lazyjj, zsh and the clipboard tool. Fails when one is not on `PATH`.
3. **Nerd Font present** (Linux: `fc-list`; macOS: the brew cask). Fails when the font is not installed.
4. **tmux copy binding resolves to an installed command** on this OS.
5. `validate.sh:173` gains the Linux counterpart that applies (a running Ghostty older than its config), and
   `:267` an explicit "launchd: macOS only" skip line on Linux.

The suite's own proof is the three runs: `local`, `vm-native` (arm64, HVF) and `vm-emulated` (x86-64, TCG) each
end with `validate.sh` exiting 0, and `validate.sh` from the integration worktree on macOS still shows the
baseline's failures and no new ones.

## Outside the repo

- `${DOTFILES_TEST_CACHE:-${XDG_CACHE_HOME:-~/.cache}/dotfiles-test}`: two Ubuntu cloud images (about 900 MB each), kept between
  runs.
- Nothing is stowed into the real `$HOME`, nothing is installed on the host, no entry in `~/.zshrc.local`.

## The `/build-proposals` change (last unit)

`.claude/skills/build-proposals/SKILL.md` gains a phase between today's Phase 5 (integrate) and Phase 6 (live
validation):

- run `test/suite.sh local`, `vm-native` and `vm-emulated` against the integration branch, in parallel;
- the live machine is touched only after all three pass;
- exit 3 (an environment could not be started) is reported and stops the run before the live phase; it is
  never skipped silently;
- the three results go side by side in the PR body (`test/suite.sh report`);
- "Rules that hold throughout" states the one exception to "never stow from a worktree": the suite's throwaway
  `$HOME`;
- later phases are renumbered and every cross-reference to a phase number is updated.

## Optional unit: CI

`.github/workflows/linux-test.yml`: `test/suite.sh here` on the hosted `ubuntu-latest` and `ubuntu-24.04-arm`
runners (free for this public repo), on pull requests that touch bootstrap, validate, the packages or `test/`.
It cannot run until a PR exists, so it ships untested by this run and the PR says so.

## Edge cases

- A guest that never comes up, or an image that fails its checksum, is exit 3, not a failure of the branch.
- The emulated guest is several times slower: nothing may wait on a terminal, and the run must survive being
  resumed.
- `validate.sh` fails on `HERDR_CONFIG_PATH` and `XDG_CONFIG_HOME` pointing elsewhere, so isolation is by
  `$HOME` and socket path, not by redirecting config variables.
- Running `here` on a real machine would bootstrap it: hence the `DOTFILES_TEST_DISPOSABLE=1` gate.

## Deliberately left out

- Fedora/`dnf` guest: best-effort code path, untested.
- Changing the login shell to zsh on Linux: bootstrap prints the `chsh` command and does not run it.
- Anything a headless guest cannot show: Ghostty rendering, clipboard round-trips, font rendering, herdr
  sounds and toasts.
- Model calls: the summarizer's `claude -p` path is not exercised in any environment (no login in the guests,
  no spend in the suite).

## Differences from the proposal

- "`./bootstrap.sh` twice" becomes three runs: herdr's plugins and Claude integration can only install once a
  server is running, so the second run still installs. The third is the idempotence proof.
- The suite has a fourth environment name, `here`, which is what runs inside a guest and on a CI runner. The
  three the proposal names are unchanged.
- `validate.sh:70` already has a Linux branch; what was missing was the Linux package list behind it.

## As built (differences from this plan)

- `local` does not stow from the worktree. It clones the committed `HEAD` (the same git bundle the guests get)
  into the throwaway `$HOME` and stows from that clone, so all three environments test one commit and no link
  ever points at a worktree. Uncommitted changes are therefore not tested.
- `local` isolates with `env -i` (a fresh environment) and then refuses if any `HERDR_*`, `TMUX*`, `XDG_*`,
  `ZDOTDIR`, `STARSHIP_*`, `ATUIN_*` or `NVIM_APPNAME` variable is present, where the plan unset a list.
- herdr has a headless mode, `herdr server`; no tmux wrapper was needed. Plugin hooks run with
  `HERDR_SUMMARIZER_DRY=1`.
- The suite creates an empty `~/.claude` to stand in for an installed Claude Code, so herdr's Claude
  integration is installed and checked. There is no `claude` binary and no login in any environment.
- nvim plugins are installed with `Lazy! restore` (from `lazy-lock.json`).
- Ubuntu 26.04 packages neovim 0.11.6, fzf 0.67.0 and lazygit 0.57.0, all new enough, so no upstream-release
  fallback was written for them.
- `lazyjj` 0.6 publishes no binaries. Linux gets `lazyjj` 0.5.0 (static musl build from cargo-quickinstall) and
  `jj` 0.47.1 (official release), both pinned by sha256. macOS keeps the brew formula.
- atuin is installed from its release tarball, not its setup script, which edits `~/.zshrc`.
- Ghostty: Ubuntu 26.04 packages 1.3.0. `ghostty +validate-config` was run once by hand in the arm64 guest
  against the repo config and passed (and failed on a copy with a bogus key). Bootstrap does not install it.
- Found by the guests and fixed for both OSes: the Oh My Zsh installer's template `~/.zshrc` blocked stow on a
  machine with none; `herdr plugin list | grep -q` and `fc-list | grep -q` failed under `pipefail` (SIGPIPE)
  and caused reinstalls; herdr's Claude integration needs `~/.claude` to exist.
- The CI job runs the suite inside an `ubuntu:26.04` container on both hosted runners, not on the runner image:
  the runners are Ubuntu 24.04, which has no lazygit package and an fzf without `--zsh`. `here` writes no `meta`
  file, so the workflow writes one for `report`.
- In a guest run, the `commit` in `meta` is read when the run starts and the bundle is taken after the guest
  boots. The skill tells the orchestrator not to commit in between; the suite does not enforce it.
- Two problems surfaced when the orchestrator re-ran the suite on the integration branch. `local` raised macOS
  "Keychain Not Found" dialogs: under `env -i` git still read Xcode's gitconfig (`credential.helper=osxkeychain`)
  and the throwaway `$HOME` has no keychain; `local` now sets `GIT_CONFIG_NOSYSTEM=1` and an empty helper. And an
  emulated guest hung for six hours in a `curl` with no stall timeout; bootstrap's Linux downloads now go
  through `fetch`, which gives up under 1 KB/s for a minute and retries.
- The throwaway `$HOME` must be at most 72 characters long (macOS limits unix socket paths to 104 bytes); the
  suite exits 3 otherwise.
- `nvim/.config/nvim/lazy-lock.json` on `master` is stale (lazy.nvim rewrites it on first install), which
  shows as the one `validate.sh` warning in every environment. Left alone: it is not a Linux issue.

## Not tested

- The `dnf` path and any distro other than Ubuntu 26.04.
- A Linux host for the harness (KVM, `cloud-localds`/`genisoimage`/`xorriso`) and `local` on a Linux host.
- `--resume` after a real interruption (only `--keep` and a hand reboot of a kept overlay were exercised).
- The CI workflow: it cannot run until a pull request exists.
- Anything on screen: Ghostty rendering, clipboard round-trips, font rendering, herdr's TUI (popups, sidebar,
  the `lazyjj` popup), sounds and toasts.
- Model calls: the summarizer's `claude -p` path and `herdr-summarizer/install.sh`.
- A fresh macOS bootstrap: `local` refuses to run when a brew tool is missing, so the brew branch only ran
  with everything already installed.
