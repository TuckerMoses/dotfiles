# highwind

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## New machine setup

```bash
git clone https://github.com/TuckerMoses/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
./validate.sh    # checks everything is linked, installed and loading cleanly
```

Works on macOS and on Linux (x86-64 and arm64; tested on Ubuntu 26.04, `dnf` distros are best-effort).
On Linux, bootstrap installs system packages with `sudo apt-get` and everything else into `~/.local/bin`,
and prints the `chsh` command for making zsh your login shell without running it.

## Structure

Each top-level directory is a Stow package that mirrors `$HOME`:

```
dotfiles/
├── .github/workflows/                — CI (Claude Code Action for PR reviews, Linux test on x86-64 and arm64, Nix checks)
├── flake.nix, flake.lock, nix/       — the Nix package set, Home Manager module and checks (not stowed; see Nix below)
├── nixos/                            — NixOS machines (not stowed; see nixos/README.md)
├── atuin/.config/atuin/config.toml   → ~/.config/atuin/config.toml
├── ghostty/.config/ghostty/config    → ~/.config/ghostty/config
├── herdr/.config/herdr/config.toml   → ~/.config/herdr/config.toml (plus herdr-summarize, herdr-recent, herdr-plugins, herdr-login-warning → ~/.local/bin)
│   └── .config/herdr/plugins/config/ → herdr-plus templates and quick actions
├── herdr-summarizer/                 — opt-in herdr plugin (not stowed; herdr-summarizer/install.sh)
├── nvim/.config/nvim/                → ~/.config/nvim/
├── starship/.config/starship.toml    → ~/.config/starship.toml
├── zsh/.zshrc                        → ~/.zshrc
├── bootstrap.sh                      — one-command setup
├── validate.sh                       — read-only check that everything here is live and working
├── test/                             — one test suite for three environments: isolated local, Linux VM, emulated Linux VM (see test/README.md)
├── docs/herdr.html                   — guide to the herdr setup: sidebar, picker, summarizer, keys (open in a browser)
├── docs/proposals/                   — the approved queue (see docs/proposals/README.md)
├── docs/plans/                       — record of what was built
├── .claude/skills/build-proposals/   — /build-proposals project skill
├── CHANGELOG.md                      — project changelog
├── CLAUDE.md                         — AI assistant instructions
└── README.md
```

## What's included

| Package | Purpose |
|---------|---------|
| **atuin** | Shell history with fuzzy search and per-directory filtering |
| **ghostty** | Ghostty terminal emulator (Catppuccin Mocha theme, JetBrains Mono NF) |
| **herdr** | Herdr terminal workspace manager (tmux-style keys, sounds, pane descriptions, `prefix+a` recent-sessions picker, `$jj_status` for jj repos, tuicr diff review popup `prefix+alt+r` for git and jj repos; plugins herdr-plus `prefix+t`/`prefix+space`, herdr-fingers trial `prefix+f`); stowed with `--no-folding` |
| **nvim** | Neovim with Claude Code sync plugins (auto-reload, diffview.nvim, claudecode.nvim) |
| **starship** | Cross-shell prompt (minimal single-line, language detection) |
| **zsh** | Zsh shell via Oh My Zsh (fzf-tab, autosuggestions, syntax-highlighting) |

Claude Code notifications and sounds are handled by Herdr (toasts, `prefix+o` jump-to-agent, and its built-in sounds via `[ui.sound]`). The opt-in `herdr-summarizer/` plugin is not stowed; `herdr-summarizer/install.sh` links it.

## Nix

The same configs also build as a Nix package set (`flake.nix`, `nix/`). Nix builds each package from
pinned sources into a read-only store, and Home Manager (a Nix tool that places files and packages in a
user's home) links the configs and installs the tools. Stow and `bootstrap.sh` remain the way the Mac is
set up, and no machine uses the Nix route for its live environment yet. The design is
`docs/design/nix-dotfiles.md`.

On a machine with Nix (Linux; the macOS outputs are only evaluated so far), from a checkout:

```bash
nix build .#tools                 # every program the configs call, as one environment
nix flake check                   # build-sandbox checks and NixOS VM tests (see test/README.md)
nix run .#sandbox                 # an interactive zsh in a throwaway HOME filled from this build
nix run .#sandbox -- <command>    # run one command there and exit with its status
nix run .#herdr-sandbox           # a herdr server and client in a throwaway HOME (see docs/herdr.html)
```

The Home Manager module (`homeManagerModules.default`) links configs either from the build (`store`
mode: an edit needs a rebuild) or into a checkout (`checkout` mode: edits are live, as with Stow).
NixOS hosts turn it on per user with `highwind.users` (see `nixos/README.md`).

## Adding a new config

```bash
mkdir -p ~/dotfiles/tool/.config/tool
mv ~/.config/tool/config ~/dotfiles/tool/.config/tool/config
cd ~/dotfiles && stow tool
```
