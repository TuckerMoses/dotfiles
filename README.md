# dotfiles

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## New machine setup

```bash
git clone git@github.com:TuckerMoses/dotfile-setup.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
./validate.sh    # checks everything is linked, installed and loading cleanly
```

## Structure

Each top-level directory is a Stow package that mirrors `$HOME`:

```
dotfiles/
├── .github/workflows/                — CI (Claude Code Action for PR reviews)
├── atuin/.config/atuin/config.toml   → ~/.config/atuin/config.toml
├── ghostty/.config/ghostty/config    → ~/.config/ghostty/config
├── herdr/.config/herdr/config.toml   → ~/.config/herdr/config.toml (plus herdr-summarize, herdr-recent → ~/.local/bin)
├── herdr-summarizer/                 — opt-in herdr plugin (not stowed; herdr-summarizer/install.sh)
├── nvim/.config/nvim/                → ~/.config/nvim/
├── starship/.config/starship.toml    → ~/.config/starship.toml
├── tmux/.tmux.conf                   → ~/.tmux.conf
├── zsh/.zshrc                        → ~/.zshrc
├── bootstrap.sh                      — one-command setup
├── validate.sh                       — read-only check that everything here is live and working
├── docs/herdr.html                   — guide to the herdr setup: sidebar, picker, summarizer, keys (open in a browser)
├── docs/plans/                       — implementation plans
├── .claude/skills/execute-plans/     — /execute-plans project skill
├── CHANGELOG.md                      — project changelog
├── CLAUDE.md                         — AI assistant instructions
└── README.md
```

## What's included

| Package | Purpose |
|---------|---------|
| **atuin** | Shell history with fuzzy search and per-directory filtering |
| **ghostty** | Ghostty terminal emulator (Catppuccin Mocha theme, JetBrains Mono NF) |
| **herdr** | Herdr terminal workspace manager (tmux-style keys, sounds, pane descriptions, `prefix+a` recent-sessions picker); stowed with `--no-folding` |
| **nvim** | Neovim with Claude Code sync plugins (auto-reload, diffview.nvim, claudecode.nvim) |
| **starship** | Cross-shell prompt (minimal single-line, language detection) |
| **tmux** | Terminal multiplexer (vim-tmux-navigator, Catppuccin status bar, session persistence) |
| **zsh** | Zsh shell via Oh My Zsh (fzf-tab, autosuggestions, syntax-highlighting) |

Claude Code notifications and sounds are handled by Herdr (toasts, `prefix+o` jump-to-agent, and its built-in sounds via `[ui.sound]`). The opt-in `herdr-summarizer/` plugin is not stowed; `herdr-summarizer/install.sh` links it.

## Adding a new config

```bash
mkdir -p ~/dotfiles/tool/.config/tool
mv ~/.config/tool/config ~/dotfiles/tool/.config/tool/config
cd ~/dotfiles && stow tool
```
