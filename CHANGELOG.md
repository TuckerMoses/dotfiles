# Changelog

All notable changes to this dotfiles setup.

## [Unreleased]

### Planned
- tmux agent completion notifications ([plan](docs/plans/tmux-agent-notifications.md))
- Neovim ↔ Claude Code sync ([plan](docs/plans/neovim-claude-sync.md))
- tmux session persistence ([plan](docs/plans/tmux-session-persistence.md))

## [2026-03-27]

### Added
- Implementation plans for agent notifications and neovim sync

### Changed
- Moved zoxide init to end of .zshrc (fixes config warning)
- Merged system-agnostic dotfiles PR (portable paths, platform guards)

## [2026-03-26]

### Added
- Initial dotfiles repo with GNU Stow
- Ghostty config: Catppuccin Mocha theme, JetBrains Mono Nerd Font
- tmux config: Catppuccin status bar, vim-tmux-navigator, vi copy mode
- zsh config: Starship prompt, fzf, zoxide, autosuggestions, syntax-highlighting
- Bootstrap script for one-command setup on new machines

### Fixed
- Ghostty theme name (spaces not dashes)
- Removed invalid `repaint-after-input` from Ghostty config
- Cleaned up `.zshenv` self-replicating Android SDK exports (392KB → 2 lines)
