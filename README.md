# dotfiles

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## New machine setup

```bash
git clone git@github.com:TuckerMoses/dotfile-setup.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

## Structure

Each top-level directory is a Stow package that mirrors `$HOME`:

```
dotfiles/
├── atuin/.config/atuin/config.toml   → ~/.config/atuin/config.toml
├── ghostty/.config/ghostty/config    → ~/.config/ghostty/config
├── notification-sounds/               — custom game sound pack for Claude Code notifications
├── nvim/.config/nvim/                → ~/.config/nvim/
├── starship/.config/starship.toml    → ~/.config/starship.toml
├── tmux/.tmux.conf                   → ~/.tmux.conf
├── zsh/.zshrc                        → ~/.zshrc
├── bootstrap.sh                      — one-command setup
├── docs/plans/                       — implementation plans
├── CHANGELOG.md                      — project changelog
├── CLAUDE.md                         — AI assistant instructions
└── README.md
```

## What's included

| Package | Purpose |
|---------|---------|
| **atuin** | Shell history with fuzzy search and per-directory filtering |
| **ghostty** | Ghostty terminal emulator (Catppuccin Mocha theme, JetBrains Mono NF) |
| **notification-sounds** | Custom game sound pack for Claude Code event notifications |
| **nvim** | Neovim with Claude Code sync plugins (auto-reload, diffview.nvim, claudecode.nvim) |
| **starship** | Cross-shell prompt (minimal single-line, language detection) |
| **tmux** | Terminal multiplexer (vim-tmux-navigator, Catppuccin status bar, session persistence) |
| **zsh** | Zsh shell via Oh My Zsh (fzf-tab, autosuggestions, syntax-highlighting) |

## Adding a new config

```bash
mkdir -p ~/dotfiles/tool/.config/tool
mv ~/.config/tool/config ~/dotfiles/tool/.config/tool/config
cd ~/dotfiles && stow tool
```
