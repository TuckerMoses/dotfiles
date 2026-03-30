# CLAUDE.md

This repository manages personal dotfiles using [GNU Stow](https://www.gnu.org/software/stow/). It configures a terminal development environment across macOS and Linux.

## Repository Structure

```
dotfile-setup/
├── .github/workflows/claude-pr-review.yml  # Claude Code Action for PR reviews
├── bootstrap.sh                     # One-command setup (idempotent)
├── ghostty/.config/ghostty/config   # Terminal emulator config
├── tmux/.tmux.conf                  # Terminal multiplexer config
├── zsh/.zshrc                       # Shell configuration
├── starship/.config/starship.toml   # Prompt engine config
├── CLAUDE.md                        # This file
└── README.md                        # User-facing docs
```

Each top-level directory is a **Stow package** that mirrors `$HOME`. Stow creates symlinks from the package contents to the corresponding location under `~`.

## How Stow Packages Work

To add a new tool's config:
1. Create a directory: `mkdir -p toolname/.config/toolname`
2. Move the config: `mv ~/.config/toolname/config toolname/.config/toolname/config`
3. Add the package name to the `for pkg in ...` loop in `bootstrap.sh`
4. Run `stow toolname` or re-run `./bootstrap.sh`

## Tools and Their Configs

| Package | Config File | Purpose |
|---------|------------|---------|
| **ghostty** | `.config/ghostty/config` | Ghostty terminal emulator (Catppuccin Mocha theme, JetBrains Mono NF) |
| **tmux** | `.tmux.conf` | Tmux multiplexer (vim-tmux-navigator, Catppuccin status bar, TPM plugins) |
| **zsh** | `.zshrc` | Zsh shell via Oh My Zsh (plugins: git, wd, autosuggestions, syntax-highlighting) |
| **starship** | `.config/starship.toml` | Starship cross-shell prompt (minimal single-line, language detection) |

### Auto-installed dependencies (via bootstrap.sh)

- **Homebrew** (macOS) / **apt**/**dnf** (Linux) for system packages
- **GNU Stow** for symlink management
- **Oh My Zsh** with custom plugins (zsh-autosuggestions, zsh-syntax-highlighting)
- **Neovim**, **fzf**, **zoxide**, **Starship**

## Design Conventions

- **Theme**: Catppuccin Mocha everywhere (ghostty, tmux status bar, starship accents)
- **Font**: JetBrains Mono Nerd Font
- **Navigation**: Vim-style keybindings throughout (tmux, neovim, fzf)
- **Section headers**: Use `# ── Section ──────────` style comments in all config files
- **Idempotent bootstrap**: `bootstrap.sh` is safe to re-run; it checks before installing
- **Cross-platform**: Support both macOS and Linux in bootstrap logic
- **Bash strict mode**: `set -euo pipefail` in all shell scripts
- **Feature detection**: Use `command -v` to check tool availability, not `which`

## Key Bindings Reference

- **Tmux prefix**: `Ctrl+b`
- **Pane navigation**: `Ctrl+h/j/k/l` (shared with Neovim via vim-tmux-navigator)
- **Splits**: `prefix + |` (horizontal), `prefix + -` (vertical)
- **Resize**: `prefix + Shift+H/J/K/L`
- **Reload tmux config**: `prefix + r`
- **fzf**: `Ctrl+R` (history), `Ctrl+T` (files)
- **zoxide**: `cd` is aliased to zoxide's smart directory jumper

## Common Tasks

### Adding a new Stow package
```bash
mkdir -p newpkg/.config/newpkg
# place config files inside, mirroring $HOME structure
# add "newpkg" to the for loop in bootstrap.sh
stow newpkg
```

### Editing configs
Edit files in this repo (not in `~`), then changes apply immediately via symlinks.

### Testing bootstrap on a fresh system
```bash
./bootstrap.sh
```

## CI / GitHub Actions

A GitHub Actions workflow (`.github/workflows/claude-pr-review.yml`) runs the `anthropics/claude-code-action@v1` action. It triggers when a reviewer submits "changes requested" on a PR whose branch starts with `claude/`. Claude reads the review comments, implements the requested changes (following this file's conventions), and replies to each comment.

**Requirements**: The Claude GitHub App must be installed on this repo, and an `ANTHROPIC_API_KEY` repository secret must be set.

## Rules for AI Assistants

- **Never hardcode usernames or home directory paths** in configs — use `$HOME` or `~` where possible. (Exception: conda/nvm blocks that are auto-generated.)
- **Preserve the section comment style** (`# ── Section ──────────`) when adding to config files.
- **Maintain Catppuccin Mocha consistency** — use the palette when adding new UI elements.
- **Keep bootstrap.sh idempotent** — guard installations with existence checks (`command -v`, `[[ -d ... ]]`).
- **Don't add unnecessary complexity** — this is a personal dotfiles repo, not a framework.
- **Test cross-platform** — any bootstrap changes must work on both macOS and Linux.
- **Stow structure must mirror `$HOME`** — files must be placed exactly where they'd live under `~`.
- **Prefer appending to existing config sections** over creating new files when possible.
