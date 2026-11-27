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
  homepc. homepc's built system must come out identical to the section 9 baseline.
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
            checks.<system>.*           build-sandbox checks and NixOS VM tests (Linux only)
            nixosConfigurations.*       as today
nix/
  overlay.nix
  packages/        one file per package in section 4
  home-manager/    the module in section 5
  checks/          section 7
  tests/           NixOS VM tests, section 7
nixos/modules/dotfiles-user.nix   turns the module on for named users of a host
```

Systems: `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`. The Darwin packages are evaluated in this change and not built, because no machine with Nix on macOS exists
yet.

`home-manager` follows the flake's `nixpkgs`. `nixpkgs-unstable` is used for two packages only
(section 4), so one fast-moving tool does not move the kernel or Tailscale. `overlay.nix` takes the
flake inputs and reads `nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}` for
those two.

The new inputs are locked with plain `nix flake lock`, never `nix flake update` or `--update-input`
on an existing input. The `locked` entries (rev and narHash) of `nixpkgs` and `disko` must equal
those on `feat/nixos-host` (compare with `jq`); `nixpkgs-unstable` is locked at the current `nixos-unstable`.

No file added under `nix/` or `nixos/` may contain a literal owner home directory (`/Users/` or
`/home/tucker`); `validate.sh` fails on one (source change 5). Test paths such as `/home/test` and
`/test/checkout` pass, and the existing modules already build the path from the user name.

## 4. The package set

Everything lives under `pkgs.dotfiles` and is exported as `packages.<system>`.

| Package | What it is |
|---|---|
| `home-tree` | A store directory laid out like `$HOME`: the union of the Stow packages `atuin`, `ghostty`, `herdr`, `nvim`, `starship`, `tmux`, `zsh`, minus the four scripts under `herdr/.local/bin`. Built with `lib.fileset` from those directories only, so a docs edit does not rebuild it. |
| `scripts` | `herdr-summarize`, `herdr-recent`, `herdr-login-warning`, `herdr-plugins`, with interpreters rewritten to store paths and their runtime commands (python 3.11 or later, fzf, git, gh, jq, coreutils, awk, sed) on a wrapped `PATH`. Takes a `dotfilesDir` argument (default: `bootstrap-dir`, an overlay attribute made once with `lib.fileset.toSource` from `./bootstrap.sh` only); the `herdr-plugins` and `dotfiles-herdr-plugins-sync` wrappers set `DOTFILES_DIR` to it with `makeWrapper --set`. `dotfiles-herdr-plugins-sync`, a wrapper running `herdr-plugins sync`, is on `PATH` through the package only and is not one of the four linked scripts. |
| `summarizer-plugin` | `herdr-summarizer/plugin` with `hook` rewritten to call the packaged `herdr-summarize`. |
| `oh-my-zsh-bundle` | nixpkgs `oh-my-zsh` with `custom/plugins/` holding `zsh-autosuggestions`, `fzf-tab`, `zsh-syntax-highlighting` and `zsh-vi-mode` from nixpkgs. Linked as `~/.oh-my-zsh`. Its `oh-my-zsh.sh` is patched so that when `$ZSH` is not writable it sets `ZSH_CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh` and disables the update check; `zsh/.zshrc` stays unchanged. |
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
  stays. On a Nix machine `dotfiles-herdr-plugins-sync` runs the same `herdr plugin install ... --ref`
  lines, read by `herdr-plugins`' existing `bootstrap.sh` parser. It needs the network, exits
  non-zero on a missing pin line or a failed install, and refuses unless `DOTFILES_SANDBOX=1`
  (set by both sandbox programs) and `$HOME` differs from the passwd home (`getent passwd`), the test section 6
  uses. In this change it runs only inside a sandbox; live use belongs to the "switch tucker" follow-up.
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
   (`DOTFILES_DIR`); without it the symlink walk is used as today. It gains a `sync` subcommand
   (the sync behaviour in "Not packaged" above).
3. `validate.sh`, `herdr-plugins`, `test/suite.sh`: where `/usr/bin/python3` does not exist, use
   `python3` from `PATH`. Every call gets `-I`, so the interpreter ignores `PYTHON*` variables and does not put the working
   directory on `sys.path`.
4. `validate.sh`, "Stowed files": a file that resolves into `/nix/store` passes when its bytes
   equal the checkout's file, and fails with "rebuild" advice when they differ. The four
   `herdr/.local/bin` scripts are exempt from the byte comparison (their interpreters are
   rewritten): a store path passes for them. `lazy-lock.json` and `lazyvim.json` pass when they are
   regular files and `~/.local/share/dotfiles` exists (the module's signal).
5. `validate.sh` fails on a file under `nix/` or `nixos/` matching `/Users/` or `/home/tucker`
   (section 3).
6. Checks: source changes 1-5 each get a `validate.sh` check (run against a throwaway copy and shown
   to fail); the packages, module and sandbox get flake checks only, as they exist only on Nix
   machines.

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
- Passes `dotfilesDir` to `scripts.override`: the checkout in `checkout` mode, `bootstrap-dir` in
  `store` mode (where `update` refuses, as it already does in a worktree).
- Asserts that in `checkout` mode `dotfiles.checkout` is non-null and absolute.

It links config files one by one, so `~/.config/herdr`, `~/.config/nvim` and `~/.tmux/plugins`
stay real, writable directories; only the store bundles named above are linked as directories.

**`store` mode.** Each file of `home-tree` is linked from the store. Two files are the exception:
`lazy-lock.json` and `lazyvim.json` are copied into `~/.config/nvim` as writable files on each
activation, so the repo's pins win and lazy.nvim can still write. Editing a config means
rebuilding. This is the mode for test users, CI and any machine that only consumes the dotfiles.

**`checkout` mode.** Each config file is linked to the checkout through Home Manager's
out-of-store symlink. This is Stow's behaviour with Home Manager doing the linking: editing a
file in the checkout, or checking out another branch there, changes the live config at once. The linked paths
are fixed when the configuration is built, so adding or removing a config file needs a rebuild; edits to existing files do not.
`validate.sh`'s Stow check passes because each link resolves to the checkout; the four scripts come
from the store and the two nvim files are copied from it on activation, as in `store` mode (both pass
under source change 4), so changing any of them means rebuilding.

The module never sets a login shell, never writes `~/.zshrc.local`, `~/.zshenv` or `~/.zprofile`,
and never touches `~/.claude`.

`nixos/modules/dotfiles-user.nix` is added to `nixos/modules/default.nix`, so every host imports it
(section 9 covers it from stage b). It adds the option
`dotfiles.users.<name> = { linkMode = "store" | "checkout"; checkout = null or an absolute path; }`,
empty by default and set only by the VM test host and the VM tests, and passes each entry to the
module's options, setting `dotfiles.enable = true` for it. `mkHost` gains `specialArgs = { inherit inputs; }`; the file imports
`inputs.home-manager.nixosModules.home-manager` and `inputs.self.homeManagerModules.default`, sets
`home-manager.useGlobalPkgs = true` and `home.stateVersion = "26.05"` for each named user. The module
takes its packages from `self.packages.${pkgs.stdenv.hostPlatform.system}` (the flake exports it
closed over `self`), never from an overlay set inside Home Manager, which errors under `useGlobalPkgs`.

## 6. Sandboxed testing

This is the answer to D. Three levels, cheapest first. None of them reaches the running herdr unless deliberately pointed at it.

**1. Build-sandbox checks** (`nix flake check`). No network, no `$HOME`, no access to the user's
sockets. The checks that run programs copy `home-tree` into a temporary `HOME` and run them against it.
Section 7 lists them.

**2. A sandbox shell** (`nix run .#sandbox`, `nix run .#herdr-sandbox`). For looking at a change
by hand, and for anything that needs the network (herdr plugin installs, `Lazy restore`).
`nix run .#sandbox -- <command...>` runs the command in the sandbox and exits with its status;
`herdr-sandbox --no-attach -- <command...>` starts the server, runs the command and stops the server.
Unattended runs use these forms.

- Creates a throwaway `HOME` with `mktemp -d` under `/tmp` (at most 40 characters, for unix socket
  paths) and fills it from the working tree's build: copies `home-tree` in as writable files, links
  `oh-my-zsh-bundle` as `~/.oh-my-zsh`, the four `tmux-plugins` entries into a real `~/.tmux/plugins`
  and the four scripts into `~/.local/bin`.
- Starts the program with `env -i` and exactly: `HOME`, `PATH` (store paths only), `TERM=xterm-256color`, `LANG=C.UTF-8`,
  `COLORTERM=truecolor`, `DOTFILES_SANDBOX=1`, `SSL_CERT_FILE` and `NIX_SSL_CERT_FILE` (both the `cacert`
  bundle's store path, so https fetches work), and `TMUX_TMPDIR`, `TMPDIR` and `XDG_RUNTIME_DIR` all
  inside the throwaway `HOME`; `--summarizer` adds `HERDR_SUMMARIZER_DRY=1`. It refuses to start if the new `HOME` equals the passwd home or the caller's `$HOME`
  (captured before `env -i`), or if `TMUX_TMPDIR` is outside it. These are the guards
  `test/suite.sh local` has.
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

Build-sandbox checks, for every Linux system:

| Check | Asserts |
|---|---|
| `configs` | `zsh -n` on `.zshrc`; the tmux config loads in a throwaway server and TPM's four plugins are sourced; `starship print-config`; atuin resolves `auto_sync` to `false`; `herdr config check`; `ghostty +validate-config` (ghostty comes from nixpkgs as a check-only input on Linux, not in `tools`); every nvim Lua file compiles; every TOML file parses. |
| `zsh-interactive` | A real interactive zsh in a pty prints nothing on stderr and has `zvm_init`, the starship prompt hook, `^T` bound to fzf, `^R` bound to atuin and zoxide's `cd`. This is step 7 of `test/suite.sh`. |
| `scripts` | `herdr-summarize` compiles, prints help and passes its `jj-status` cases against throwaway repos; `herdr-login-warning` gives the right output for a fake `claude` near and far from expiry; `herdr-recent` and `herdr-plugins help` run; no packaged script's interpreter line or python invocation resolves to `/usr/bin/python3`. |
| `herdr-headless` | A herdr server starts in the temporary `HOME`; the summarizer plugin links; creating a workspace produces hook runs that all succeed and a non-empty state file, with `HERDR_SUMMARIZER_DRY=1` exported before the server starts. Steps 2 and 6 of `test/suite.sh`. |
| `tool-versions` | The floors in section 4; the tuicr version and both sha256 values in the `fetchurl` equal those parsed from `bootstrap.sh`. |
| `lifeline-guard` | Pure evaluation, no VM: each of the nine config changes that `nixos/test/drills.sh` expects the lockout guard to refuse does fail an assertion, and the unmodified host passes. |
| `link-modes` | Home Manager's activation package builds for a test user in each mode. In `store` mode the files Home Manager places under the test user's HOME (the `home-tree` links other than the two nvim files, the four script links in `~/.local/bin` and the two copied nvim files), compared as sorted lists, equal the file list of the Stow packages named on `bootstrap.sh`'s `for pkg in` line plus every `--restow <name>` (as `validate.sh` lines 50-51 read them), so a new package fails the check until `home-tree` names it; `link-modes` and `tool-versions` both read `bootstrap.sh` through `nix/lib/bootstrap-data.nix`, written in stage b with the package list and extended in stage c with the tuicr values. The test user comes from `home-manager.lib.homeManagerConfiguration` (user `test`, home `/home/test`, stateVersion `"26.05"`, pkgs from the flake); the placed set is the `config.home.file` targets plus the two nvim names, found by their copy commands in the activation script. In `checkout` mode `dotfiles.checkout` is `/test/checkout` and each config link targets `<checkout>/<package>/<relative path>`, with the scripts and nvim files as in `store` mode; with it unset, `builtins.tryEval` of the activation package fails. In both modes the `herdr-plugins` wrapper carries the expected `DOTFILES_DIR`. |

Each check must be shown to fail: the builder breaks its input in the working tree, runs that one
check, reverts, and never commits the break. The PR description gets a table of check, break and
failing line.

NixOS VM tests (`x86_64-linux` only in this change; attribute names start with `vm-`):

| Test | Asserts |
|---|---|
| `vm-home` | A machine with a user in `store` mode and one in `checkout` mode boots; both Home Manager units succeed; each user logs in over SSH with a key into zsh; the interactive shell is clean; in `checkout` mode an edit to a config in the checkout is live without a rebuild; an interactive login (`ssh -tt user@host`, `exit 0` on stdin) still connects and returns 0 after the user's `.zshrc` is deliberately broken. The test host sets `programs.zsh.enable`, each user's shell to zsh, and the global prompt and `compinit` off (`dotfiles-user.nix` does not enable zsh), and copies the flake source to a fixed path in the checkout user's HOME, owned by that user, in a oneshot unit ordered before that user's Home Manager unit. |
| `vm-lifeline` | A machine with the `lifeline` module boots with sshd answering on ports 22 and 2222, the firewall up with both ports open, and sleep targets masked. |

**What is not ported.** The remaining drills in `nixos/test/drills.sh` (`safe-switch` confirmed
and rolled back, `trial-boot`, power pull) rebuild and reboot an installed system with a real
bootloader. Running them inside a NixOS test needs the target systems pre-built into the guest
and `safe-switch` taking a built system instead of a flake. That is its own piece of work
(section 12). Until then those drills stay in `nixos/test/` and on the real machine.

**What no check covers:** `Lazy restore` and herdr plugin installs (network), Ghostty rendering,
fonts on screen, clipboard, sounds, model calls. The first two are run in stage b through the non-interactive sandbox forms (section 6).

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
  1. `eval`: `nix flake check --all-systems --no-build`, plus evaluating the derivation of every host,
     including homepc, without building it.
  2. `checks`: the seven build-sandbox checks, built by attribute name, on `ubuntu-latest` and `ubuntu-24.04-arm`.
  3. `vm`: the `vm-*` checks on `ubuntu-latest` only, after a KVM udev rule step
     (`KERNEL=="kvm", GROUP="kvm", MODE="0666"`, reload, trigger).
- **Nix** is installed with `cachix/install-nix-action` (Nix 2.34.9, no third-party
  cache), with `experimental-features = nix-command flakes` and, in `vm`, `system-features = kvm`.
- **homepc's system is not built in CI.** The NVIDIA driver is unfree, so the public cache does
  not carry it and every run would compile kernel modules. Evaluation catches option and
  assertion errors; the build is done on homepc.
- **Cache:** `cache.nixos.org` only. No Cachix account, because that needs the owner to create
  one. If runs are too slow, caching the store with GitHub's own cache is the first thing to try.

`linux-test.yml` is unchanged.

## 9. homepc in this change

- homepc's configuration imports nothing new that changes its output. The acceptance test: the
  baseline is the path printed by `nix build .#nixosConfigurations.homepc.config.system.build.toplevel --no-link --print-out-paths`
  in the detached worktree of `origin/feat/nixos-host` at `~/dotfiles-nix/.worktrees/base`, its path written to `~/dotfiles-nix/.git/homepc-baseline` (never committed) by stage 0. Every later build of that
  command prints the same path; `/run/current-system` is informational only. A differing path is a
  failure: remove the newest import first to bisect. If importing the Home Manager NixOS module changes the path even with no
  users named, the import moves to the hosts that name users.
- Nothing is activated on homepc. No `safe-switch`, no `trial-boot`.
- homepc is used as a build and test machine: `nix build`, `nix flake check`, the VM tests, and
  the sandbox shell under a throwaway `HOME`.
- The work happens in a **separate clone**, `~/dotfiles-nix` on homepc, not `~/dotfiles`, so
  the checkout the rebuild tools point at stays on `feat/nixos-host`. Stage 0 makes it with
  `git clone` from `origin`, after the orchestrator pushes `feat/nix-dotfiles` from the Mac.
  Builders work on `feat/nix-dotfiles` in it.

## 10. Docs and skills

- `CLAUDE.md`: a "Nix package set" section (the outputs, the two link modes, how to run the
  checks and the sandbox), the herdr testing rule from section 6, the structure tree, and a line
  in "Rules for AI Assistants" that new behaviour which can be tested without a network also gets
  a flake check. The `validate.sh` rule gains a clause: behaviour existing only on Nix machines is covered by a flake check instead. The "Agents never ...
  `herdr plugin install`" bullet gains an exception shaped like its `test/suite.sh` one: agents may
  run the flake checks and `nix run .#sandbox` / `.#herdr-sandbox` with any flag, and the plugin
  installs and links those do, because they touch only a throwaway HOME and its own herdr server;
  direct `herdr plugin ...` commands stay forbidden.
- `.claude/skills/build-proposals/SKILL.md`: the smallest edit that is true. Its phases run on the
  Mac, which has no Nix, so the skill cannot run `nix flake check` there. It gains: units add a
  flake check under the rule above; CI runs the checks on the pull request; herdr behaviour is
  tried in `herdr-sandbox` on a machine with Nix, never on the live server.
- `README.md`, `test/README.md`, `nixos/README.md`, `CHANGELOG.md`: what exists and how to run it.
- `docs/herdr.html`: a short section on testing a herdr change in the sandbox.

## 11. Build order and acceptance

Each stage is built by a delegated agent and then checked by the orchestrating session, which
re-runs that stage's Done-when items itself, before the next starts. The orchestrator runs
every Done-when item except stage e in the clone over `ssh -p 2222 tucker@homepc`. Builder agents run there in the
clone from section 9 and commit on `feat/nix-dotfiles`; every new file is `git add`ed (`-N` is enough)
before any `nix` command, since flake evaluation sees only tracked files. Stages run in the table's
order, 0 to d, then f. Then, on the Mac, the orchestrator runs
`git fetch ssh://tucker@homepc:2222/home/tucker/dotfiles-nix feat/nix-dotfiles:refs/remotes/homepc/feat/nix-dotfiles`
(a ref no worktree has checked out), pushes it with
`git push origin refs/remotes/homepc/feat/nix-dotfiles:refs/heads/feat/nix-dotfiles` and opens the one
pull request with base `feat/nixos-host` (`master` if `gh pr view 7 --json state` says merged). Stage e is checked
from the Mac with `gh pr checks`; a fix is a new commit on homepc, brought over the same way. Builders may run `nix build`, `nix flake check`, `nix run .#sandbox`,
`nix run .#herdr-sandbox` and the VM tests. They never run `home-manager switch`, `nix profile`,
`nix-env`, `nixos-rebuild`, `safe-switch`, `trial-boot`, `nix flake update`, `stow` or `bootstrap.sh`,
and never create, modify or delete anything under tucker's real HOME except inside the clone and Nix's
caches (`~/.cache/nix`, `~/.local/state/nix`); the sandbox's directories are under /tmp.

| Stage | Done when |
|---|---|
| 0. Clone and baseline (orchestrator) | `~/dotfiles-nix` is a clone of `origin` on `feat/nix-dotfiles`; `~/dotfiles-nix/.worktrees/base` is a detached worktree of `origin/feat/nixos-host`, where the section 9 command ran; `grep -q '^/nix/store/' ~/dotfiles-nix/.git/homepc-baseline` succeeds. |
| a. Inputs, overlay, packages, source changes | Every package except `sandbox` and `herdr-sandbox` (stage b) builds on homepc for `x86_64-linux`; `nix flake check --all-systems --no-build` passes (Darwin and aarch64 evaluate); the `nixpkgs` and `disko` `locked` entries equal feat/nixos-host's (section 3); `bash -n` passes on `validate.sh` and `test/suite.sh`; each new `validate.sh` check from source changes 1-5 passes on the repo and was seen to fail on a broken throwaway copy (rows in the PR table); homepc's system path equals the section 9 baseline. |
| b. Home Manager module, `dotfiles-user.nix`, sandbox apps, the `link-modes` check | `link-modes` passes; `nix run .#sandbox -- zsh -ic exit` exits 0 with empty stderr (the pty assertion is the `zsh-interactive` check, stage c); through the non-interactive forms, `tmux display -p '#{socket_path}'` (after starting a sandbox tmux server) and `herdr status server`'s `socket:` line both resolve inside the throwaway `HOME`; a run of `herdr-sandbox --no-attach -- true` made after `touch` of a stamp file leaves `find "$(getent passwd tucker | cut -d: -f6)" -newer <stamp>`, excluding `~/dotfiles-nix`, `~/.cache/nix` and `~/.local/state/nix`, printing nothing; `herdr-sandbox --with-plugins --no-attach -- true` exits 0; after `nix run .#sandbox -- nvim --headless '+Lazy! restore' +qa`, each plugin in `lazy-lock.json` has a directory under the throwaway `HOME`'s `.local/share/nvim/lazy` whose `git rev-parse HEAD` equals the lock's commit; `git ls-remote` of a public https repo succeeds inside the sandbox (the PR gets exit codes and last output lines of these network items; if the network is unavailable it says so); homepc's system path still equals the baseline. |
| c. The other build-sandbox checks | All seven build-sandbox checks, `link-modes` included, built by attribute name, pass on homepc, and each was seen to fail on a broken input. |
| d. VM tests | `vm-home` and `vm-lifeline` pass on homepc. |
| f. Docs, skill, proposals | Section 10 is done and the three proposals listed in section 12 exist in `docs/proposals/`. |
| e. CI | `linux-test.yml` is green on the pull request; `nix.yml` runs green, or the pull request says which of its jobs is red and why. |

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
