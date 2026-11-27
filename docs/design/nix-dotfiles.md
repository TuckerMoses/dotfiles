# Design: the dotfiles as a Nix package set

Status: design, written 2026-11-27, before any of it is built. Branch `feat/nix-dotfiles`, stacked
on `feat/nixos-host` (PR #7).

## 1. Goal and limits

The repo configures a terminal environment with GNU Stow and `bootstrap.sh`. This design adds a
second delivery route through Nix, without removing the first.

What the owner asked for (2026-11-27):

- A. The dotfiles become a Nix package set.
- B. NixOS adds those packages to the system.
- C. A local overlay for personal additions.
- D. The repo's skills and docs are updated, and future behaviour tests (herdr above all) run in a
  sandbox instead of against the live herdr.
- E. CI runs Nix-based tests on pull requests.
- F. Research on packaging agent skills with Nix. Done: `docs/research/harness-skills-nix.md`.
  Nothing from it is built here.

Agreed amendments: Home Manager places the configs. A and C are one thing, an overlay. B is per
user through Home Manager, not system-wide. CI is GitHub Actions.

Limits for this change:

- **No machine's live environment changes.** Not the Mac (it has no Nix), and not `tucker` on
  homepc. homepc's built system must come out byte-identical to the one running now (section 9).
- **No flag day.** Stow, `bootstrap.sh`, `validate.sh` and `test/suite.sh` keep working as they do
  today. Nix reads the same files Stow links.
- **Nothing is merged.** The result is one pull request.

Out of scope, each listed in section 12 as follow-up: switching the Mac to Nix, switching `tucker`
on homepc, building herdr's third-party plugins with Nix, moving the plugin pins out of
`bootstrap.sh`, linking claude-materia through Home Manager, and Claude Code from nixpkgs.

## 2. Facts the design rests on

Checked on homepc on 2026-11-27 unless a file is named.

- homepc runs NixOS 26.05 with Nix 2.34.9, has `/dev/kvm`, 12 cores, 30 GB of memory.
- Home Manager has a `release-26.05` branch.
- nixpkgs 26.05 has atuin 18.15.2, starship 1.25.1, zoxide 0.9.9, fzf 0.72.0, neovim 0.12.4, tmux
  3.7b, lazygit 0.66.3, lazyjj 0.6.1, ghostty 1.3.1, oh-my-zsh, zsh-vi-mode, zsh-fzf-tab.
- nixpkgs 26.05 has **no herdr** and **no tuicr**, and its jujutsu is 0.41.0, older than the
  0.47.1 that `bootstrap.sh` pins. nixpkgs unstable has herdr 0.9.5, jujutsu 0.47.1 and tuicr
  0.29.0 (`bootstrap.sh` pins 0.30.0).
- nixpkgs 26.05 has `tmuxPlugins.sensible`, `.resurrect` and `.continuum`, and no `tpm`.
- `bootstrap.sh` is read as data by other tools. `validate.sh` and `herdr-plugins` take the Stow
  package list, the tool lists and the three herdr plugin pins out of it with sed and awk, and
  `herdr-plugins update` rewrites a pin in it.
- `/usr/bin/python3` is hard-coded in the `herdr-summarize` shebang, the summarizer plugin's
  `hook`, `herdr-summarizer/install.sh`, `herdr-plugins`, `validate.sh` (14 places) and
  `test/suite.sh`. NixOS has no such path.
- `herdr-summarize` finds `herdr`, `claude` and `jj` through its own fixed directory list, not
  through `$PATH`.
- Some things under `$HOME` must stay writable or be real directories: `lazy-lock.json` and
  `lazyvim.json` (rewritten by lazy.nvim and LazyVim), `~/.config/herdr` (sockets, logs, plugin
  installs), `~/.tmux/plugins`.
- `herdr-plugins` finds the repo by following its own symlink and going up three directories.

## 3. Shape

```
flake.nix
  inputs:   nixpkgs (26.05), nixpkgs-unstable, home-manager (release-26.05), disko
  outputs:  overlays.default            adds pkgs.dotfiles.*
            packages.<system>.*         the same set, per system
            apps.<system>.*             sandbox, herdr-sandbox
            homeManagerModules.default  places configs and tools for one user
            checks.<system>.*           build-sandbox checks and NixOS VM tests
            nixosConfigurations.*       as today
nix/
  overlay.nix
  packages/        one file per package in section 4
  home-manager/    the module in section 5
  checks/          section 7
  tests/           NixOS VM tests, section 7
nixos/modules/dotfiles-user.nix   turns the module on for named users of a host
```

Systems: `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`. The Darwin outputs are evaluated in
this change and not built, because no machine with Nix on macOS exists yet.

`home-manager` follows the flake's `nixpkgs`. `nixpkgs-unstable` is used for three packages only
(section 4), so one fast-moving tool does not move the kernel or Tailscale.

No file added under `nix/` or `nixos/` may contain a literal home directory. `validate.sh` fails
on one, and the existing modules already build the path from the user name.

## 4. The package set

Everything lives under `pkgs.dotfiles` and is exported as `packages.<system>`.

| Package | What it is |
|---|---|
| `home-tree` | A store directory laid out like `$HOME`: the union of the Stow packages `atuin`, `ghostty`, `herdr`, `nvim`, `starship`, `tmux`, `zsh`, minus the four scripts under `herdr/.local/bin`. Built with `lib.fileset` from those directories only, so a docs edit does not rebuild it. |
| `scripts` | `herdr-summarize`, `herdr-recent`, `herdr-login-warning`, `herdr-plugins`, with interpreters rewritten to store paths and their runtime commands (python 3.11 or later, fzf, git, gh, jq, coreutils, awk, sed) on a wrapped `PATH`. |
| `summarizer-plugin` | `herdr-summarizer/plugin` with `hook` rewritten to call the packaged `herdr-summarize`. |
| `oh-my-zsh-bundle` | nixpkgs `oh-my-zsh` with `custom/plugins/` holding `zsh-autosuggestions`, `fzf-tab`, `zsh-syntax-highlighting` and `zsh-vi-mode` from nixpkgs. Linked as `~/.oh-my-zsh`, it satisfies `zsh/.zshrc` unchanged. |
| `tmux-plugins` | `tpm`, `tmux-sensible`, `tmux-resurrect`, `tmux-continuum`, under the directory names TPM expects in `~/.tmux/plugins`. |
| `tools` | One environment with every program the configs call: zsh, tmux, neovim, starship, fzf, zoxide, atuin, jq, lazygit, lazyjj, jujutsu, tuicr, herdr, git, gh, python, a C compiler (nvim-treesitter builds parsers), go and cargo (herdr builds two of its plugins), and on Linux wl-clipboard. |
| `sandbox`, `herdr-sandbox` | The throwaway-HOME programs in section 6. |

Rules for where a tool comes from:

- From nixpkgs 26.05 unless that version is older than what `bootstrap.sh` requires or the
  package is missing there.
- From `nixpkgs-unstable`: **herdr** (0.9.5) and **jujutsu** (0.47.1).
- **tuicr**: unstable has 0.29.0, below the floor. On Linux it is the release binary
  `bootstrap.sh` already pins (0.30.0, a static musl build, with the two sha256 values listed
  there), fetched with `fetchurl`. The Darwin `tools` leaves tuicr out until nixpkgs carries
  0.30.0 or later.
- **tpm** is not in nixpkgs: `fetchFromGitHub` at a fixed commit. The other three tmux plugins
  come from nixpkgs `tmuxPlugins`.
- A check (`tool-versions`, section 7) fails when a tool is below the floor the repo depends on:
  herdr 0.9.0, jujutsu 0.47.1, tuicr 0.30.0, neovim 0.11, fzf 0.67.

The JetBrains Mono Nerd Font comes from nixpkgs through Home Manager's fontconfig support.

**Not packaged, on purpose:**

- **herdr's third-party plugins** (vim-herdr-navigation, herdr-plus, herdr-fingers). herdr
  installs and builds them into `~/.config/herdr/plugins` from the pins in `bootstrap.sh`. That
  stays. On a Nix machine the command `dotfiles-herdr-plugins-sync` (part of `scripts`) reads the
  same `herdr plugin install ... --ref` lines out of `bootstrap.sh` and runs them. It needs the
  network. The existing rule holds: on a live machine only the owner runs it; an agent may run it
  inside a sandbox.
- **lazy.nvim's plugins.** lazy.nvim fetches them on first start from `lazy-lock.json`.
- **Claude Code.** It stays the native install in `~/.local/bin`. herdr issue #803 (a
  Nix-wrapped Claude Code shown as `unknown`) therefore does not apply yet.

**Changed from what was agreed.** The plan was to ship tmux and starship as wrapped packages with
the config baked in. This design does not. A wrapper that injects a config gives a second answer
to "which config is live", and `validate.sh` has a whole section that exists to catch exactly
that. The sandbox in section 6 gives the same ability to try a config without touching `$HOME`.

### Source changes the packages need

All are backward compatible and change nothing on the Mac.

1. `herdr-summarize`: its command lookup also searches `$PATH`, after the fixed list. On NixOS
   the fixed list finds nothing but `~/.local/bin`.
2. `herdr-plugins`: the repo location can be given by an environment variable
   (`DOTFILES_DIR`); without it the symlink walk is used as today.
3. `validate.sh`, `herdr-plugins`, `test/suite.sh`: where `/usr/bin/python3` does not exist, use
   `python3` from `PATH`. Every call gets `-I`, which also closes the finding that these calls
   could import a module from the working directory.
4. `validate.sh`, "Stowed files": a file that resolves into `/nix/store` passes when its bytes
   equal the checkout's file, and fails with "rebuild" advice when they differ.

`validate.sh` passing in full on a Nix-managed home is **not** a goal of this change. It reads
tool lists that assume brew or apt, and it requires herdr's plugins. The pull request records
what it reports for the test user.

## 5. The Home Manager module

`homeManagerModules.default` defines:

| Option | Meaning |
|---|---|
| `dotfiles.enable` | Turn the module on. |
| `dotfiles.linkMode` | `"store"` (default) or `"checkout"`. |
| `dotfiles.checkout` | Absolute path of a git checkout of this repo. Required in `checkout` mode. |

What it does in both modes:

- Adds `tools` and `scripts` to the user's packages, and links the four scripts into
  `~/.local/bin`, because `herdr/config.toml` calls them by that path.
- Links `~/.oh-my-zsh` to `oh-my-zsh-bundle` and the four entries of `tmux-plugins` into a real
  `~/.tmux/plugins` directory.
- Links `summarizer-plugin` at `~/.local/share/dotfiles/herdr-summarizer-plugin`, a path that
  stays the same across rebuilds. Linking it into herdr stays opt-in and manual, as today.
- Installs the font.
- Sets `DOTFILES_DIR` for `herdr-plugins` and `dotfiles-herdr-plugins-sync`: the checkout in
  `checkout` mode, a store copy of the repo's `bootstrap.sh` in `store` mode (where `update`
  refuses, as it already does in a worktree).

It links files one by one, never a whole directory, so `~/.config/herdr`, `~/.config/nvim` and
`~/.tmux/plugins` stay real, writable directories.

**`store` mode.** Each file of `home-tree` is linked from the store. Two files are the exception:
`lazy-lock.json` and `lazyvim.json` are copied into `~/.config/nvim` as writable files on each
activation, so the repo's pins win and lazy.nvim can still write. Editing a config means
rebuilding. This is the mode for test users, CI and any machine that only consumes the dotfiles.

**`checkout` mode.** Each config file is linked to the checkout through Home Manager's
out-of-store symlink. This is Stow's behaviour with Home Manager doing the linking: editing a
file in the checkout, or checking out another branch there, changes the live config at once.
`validate.sh`'s Stow check passes unchanged, because each link still resolves to the checkout.
Scripts still come from the store in this mode, since the raw files name `/usr/bin/python3`.
Changing a script on a Nix machine means rebuilding.

The module never sets a login shell, never writes `~/.zshrc.local`, `~/.zshenv` or `~/.zprofile`,
and never touches `~/.claude`.

`nixos/modules/dotfiles-user.nix` adds a host option naming the users who get the module and the
mode for each. It is empty by default. Only the VM test host and the VM tests set it.

## 6. Sandboxed testing

This is the answer to D. Three levels, cheapest first. None of them can reach the running herdr.

**1. Build-sandbox checks** (`nix flake check`). No network, no `$HOME`, no access to the user's
sockets. Each check copies `home-tree` into a temporary `HOME` and runs programs against it.
Section 7 lists them.

**2. A sandbox shell** (`nix run .#sandbox`, `nix run .#herdr-sandbox`). For looking at a change
by hand, and for anything that needs the network (herdr plugin installs, `Lazy restore`).

- Creates a throwaway `HOME` under the temp directory, short enough for unix socket paths, and
  fills it from the `home-tree`, `scripts`, `oh-my-zsh-bundle` and `tmux-plugins` built from the
  working tree.
- Starts the program with `env -i` and a short allow-list, so no `HERDR_*`, `TMUX*`, `ZDOTDIR`,
  `XDG_*`, `STARSHIP_*`, `ATUIN_*` or `NVIM_APPNAME` value leaks in. It refuses to start if the
  `HOME` it is about to use is the real one. These are the guards `test/suite.sh local` already
  has.
- `herdr-sandbox` starts a herdr server whose socket, config, state and plugin registry are all
  inside the throwaway `HOME`, then attaches to it. `--with-plugins` runs
  `dotfiles-herdr-plugins-sync` first. `--summarizer` links the packaged summarizer plugin with
  `HERDR_SUMMARIZER_DRY=1`, so no model calls are made.
- Deletes the directory on exit unless `--keep` is given.

It isolates files and sockets. It is not a security boundary: the process runs as the user and
can read the rest of the disk.

**3. NixOS VM tests.** Used only for what needs a whole machine: a user logging in over SSH and
Home Manager activating at boot. They need KVM, so they run on homepc and in CI, not on the Mac.

**The rule that goes into `CLAUDE.md`:** a change to `herdr/`, `herdr-summarizer/` or a herdr
script is tested with a flake check or in `herdr-sandbox`. An agent never tests against the
owner's running herdr, and never runs the plugin sync outside a sandbox.

## 7. Checks

Build-sandbox checks, for every Linux system (and Darwin once it can be built):

| Check | Asserts |
|---|---|
| `configs` | `zsh -n` on `.zshrc`; the tmux config loads in a throwaway server and TPM's four plugins are sourced; `starship print-config`; atuin resolves `auto_sync` to `false`; `herdr config check`; `ghostty +validate-config`; every nvim Lua file compiles; every TOML file parses. |
| `zsh-interactive` | A real interactive zsh in a pty prints nothing on stderr and has `zvm_init`, the starship prompt hook, `^T` bound to fzf, `^R` bound to atuin and zoxide's `cd`. This is step 7 of `test/suite.sh`. |
| `scripts` | `herdr-summarize` compiles, prints help and passes its `jj-status` cases against throwaway repos; `herdr-login-warning` gives the right output for a fake `claude` near and far from expiry; `herdr-recent` and `herdr-plugins help` run; no packaged script still names `/usr/bin/python3`. |
| `herdr-headless` | A herdr server starts in the temporary `HOME`; the summarizer plugin links; creating a workspace produces hook runs that all succeed and a non-empty state file, in dry mode. Steps 2 and 6 of `test/suite.sh`. |
| `tool-versions` | The floors in section 4. |
| `lifeline-guard` | Pure evaluation, no VM: each of the nine config changes that `nixos/test/drills.sh` expects the lockout guard to refuse does fail an assertion, and the unmodified host passes. |
| `link-modes` | Home Manager's activation package builds for a test user in each mode, and in `store` mode the generated file list equals the Stow package file list. |

Each check must be shown to fail: the builder breaks its input once and records that the check
went red.

NixOS VM tests (`x86_64-linux`; `aarch64-linux` where the runner has KVM):

| Test | Asserts |
|---|---|
| `vm-home` | A machine with a user in `store` mode and one in `checkout` mode boots; both Home Manager units succeed; each user logs in over SSH with a key into zsh; the interactive shell is clean; in `checkout` mode an edit to a config in the checkout is live without a rebuild; `ssh user@host true` still works after the user's `.zshrc` is deliberately broken. |
| `vm-lifeline` | A machine with the `lifeline` module boots with sshd answering on ports 22 and 2222, the firewall up with both ports open, and sleep targets masked. |

**What is not ported.** The remaining drills in `nixos/test/drills.sh` (`safe-switch` confirmed
and rolled back, `trial-boot`, power pull) rebuild and reboot an installed system with a real
bootloader. Running them inside a NixOS test needs the target systems pre-built into the guest
and `safe-switch` taking a built system instead of a flake. That is its own piece of work
(section 12). Until then those drills stay in `nixos/test/` and on the real machine.

**What no check covers:** `Lazy restore` and herdr plugin installs (network), Ghostty rendering,
fonts on screen, clipboard, sounds, model calls. The first two are run once by hand in the
sandbox shell on homepc for this change, and the result goes in the pull request.

### How the test harnesses relate

Nothing is merged between them; they test different things. `test/README.md` gets this table.

| Harness | Tests | Runs on |
|---|---|---|
| `test/suite.sh` | The Stow and `bootstrap.sh` route on Ubuntu | Mac, Linux, CI |
| `nix flake check` | The Nix route: packages, module, VM login | homepc, CI |
| `nixos/test/` | Installing NixOS and the destructive lockout drills | Mac (QEMU), by hand |
| `validate.sh` | What is live on this machine | any machine |

## 8. CI

A new workflow, `.github/workflows/nix.yml`.

- **Triggers:** `pull_request` when `flake.nix`, `flake.lock`, `nix/**`, `nixos/**`, a Stow
  package directory, `herdr-summarizer/**`, `bootstrap.sh`, `validate.sh` or the workflow itself
  changes; and `workflow_dispatch`. Never `pull_request_target`.
- **Permissions:** `contents: read`. No secrets.
- **Actions** are pinned by commit SHA.
- **Jobs:**
  1. `eval`: `nix flake check --no-build`, plus evaluating the derivation of every host,
     including homepc, without building it.
  2. `checks`: the build-sandbox checks, on `ubuntu-latest` and `ubuntu-24.04-arm`.
  3. `vm`: the NixOS VM tests on `ubuntu-latest`, with `/dev/kvm` opened to the runner user.
- **homepc's system is not built in CI.** The NVIDIA driver is unfree, so the public cache does
  not carry it and every run would compile kernel modules. Evaluation catches option and
  assertion errors; the build is done on homepc.
- **Cache:** `cache.nixos.org` only. No Cachix account, because that needs the owner to create
  one. If runs are too slow, caching the store with GitHub's own cache is the first thing to try.

`linux-test.yml` is unchanged.

## 9. homepc in this change

- homepc's configuration imports nothing new that changes its output. The acceptance test: after
  the change, building `nixosConfigurations.homepc` on homepc gives the same store path as
  `/run/current-system`. If importing the Home Manager NixOS module changes the path even with no
  users named, the import moves to the hosts that name users.
- Nothing is activated on homepc. No `safe-switch`, no `trial-boot`.
- homepc is used as a build and test machine: `nix build`, `nix flake check`, the VM tests, and
  the sandbox shell under a throwaway `HOME`.
- The branch is fetched into a **separate clone** on homepc, not `~/dotfiles`, so the checkout
  the rebuild tools point at stays on `feat/nixos-host`.

## 10. Docs and skills

- `CLAUDE.md`: a "Nix package set" section (the outputs, the two link modes, how to run the
  checks and the sandbox), the herdr testing rule from section 6, the structure tree, and a line
  in "Rules for AI Assistants" that new behaviour which can be tested without a network also gets
  a flake check. The `validate.sh` rule stays as it is.
- `.claude/skills/build-proposals/SKILL.md`: the smallest edit that is true. Its phases run on the
  Mac, which has no Nix, so the skill cannot run `nix flake check` there. It gains: units add a
  flake check under the rule above; CI runs the checks on the pull request; herdr behaviour is
  tried in `herdr-sandbox` on a machine with Nix, never on the live server.
- `README.md`, `test/README.md`, `nixos/README.md`, `CHANGELOG.md`: what exists and how to run it.
- `docs/herdr.html`: a short section on testing a herdr change in the sandbox.

## 11. Build order and acceptance

Each stage is built by a delegated agent and then checked by the session on homepc before the
next starts.

| Stage | Done when |
|---|---|
| a. Inputs, overlay, packages, source changes | Every package builds on homepc for `x86_64-linux`; Darwin and aarch64 evaluate; `test/suite.sh`'s own files still pass `bash -n`; homepc's system path is unchanged. |
| b. Home Manager module, `dotfiles-user.nix`, sandbox apps | `link-modes` passes; `nix run .#sandbox` gives a clean interactive zsh on homepc; `herdr-sandbox` starts and stops without touching anything outside its directory. |
| c. Build-sandbox checks | All pass on homepc, and each was seen to fail on a broken input. |
| d. VM tests | `vm-home` and `vm-lifeline` pass on homepc. |
| e. CI | The workflow runs green on the pull request, or the pull request says which job is red and why. |
| f. Docs, skill, proposals | Section 10 is done and the follow-ups in section 12 exist as proposals. |

## 12. Follow-ups

Proposals added by this change (merging the pull request approves them, so each that needs a
decision says so):

- **Switch `tucker` on homepc to the module.** Needs the owner present. Recommended shape: keep
  bash as the login shell and start zsh from the terminal and from herdr, so SSH access never
  depends on `.zshrc`; activate with `safe-switch`.
- **Switch the Mac.** Install Nix, then `stow -D` each package before the first activation
  (Home Manager refuses to replace files it does not own), with `stow` as the way back.
- **herdr plugins as Nix builds, and the pins in a data file** read by `bootstrap.sh`,
  `validate.sh`, `herdr-plugins` and Nix alike.

Recorded here only:

- The remaining lockout drills as NixOS tests (section 7).
- claude-materia linked through Home Manager (`docs/research/harness-skills-nix.md`).
- `validate.sh` passing in full on a Nix-managed home.
- Claude Code from nixpkgs, with a test for herdr issue #803.
- A binary cache for CI.

## 13. Known departures

- This work did not go through `docs/proposals/` and `/build-proposals`; the owner scoped it
  directly.
- Wrapped tmux and starship packages were agreed and are not built (section 4).
- "Port the lockout drills to NixOS tests" is done in part (section 7).
