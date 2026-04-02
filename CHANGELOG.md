# Changelog

All notable changes to this dotfiles setup.

## [Unreleased]

### Planned
- tmux agent completion notifications ([plan](docs/plans/tmux-agent-notifications.md))
- Jujutsu adoption for lock-free agent workflows ([plan](docs/plans/jujutsu-adoption.md))

### In Progress
- Claude context management via Stow ([PR #7](https://github.com/TuckerMoses/dotfile-setup/pull/7), [plan](docs/plans/claude-context-management.md))

## [2026-04-01]

### Added
- Atuin shell history stow package with bootstrap support ([PR #10](https://github.com/TuckerMoses/dotfile-setup/pull/10))
- fzf-tab plugin and tuned autosuggestions strategy ([PR #9](https://github.com/TuckerMoses/dotfile-setup/pull/9))

### Changed
- Removed vim keybinding support from atuin config (reverted after testing)

## [2026-03-31]

### Added
- Neovim stow package with Claude Code sync plugins (auto-reload, diffview.nvim, claudecode.nvim) ([PR #8](https://github.com/TuckerMoses/dotfile-setup/pull/8), [plan](docs/plans/neovim-claude-sync.md))
- tmux session persistence with resurrect + continuum ([PR #6](https://github.com/TuckerMoses/dotfile-setup/pull/6), [plan](docs/plans/tmux-session-persistence.md))
- `.worktrees/` added to `.gitignore`
- Worktree testing guidance for stow-based repos in CLAUDE.md

## [2026-03-30]

### Added
- Claude context management plan
- Jujutsu adoption plan for lock-free agent workflows
- Claude Code Action workflow for PR reviews (`.github/workflows/claude-pr-review.yml`)
- Git worktree session workflow guidelines in CLAUDE.md

### Changed
- Refined Claude Code Action workflow configuration (permissions, triggers)

## [2026-03-29]

### Added
- tmux session persistence plan

### Fixed
- Suppress zoxide false positive in non-interactive shells

## [2026-03-27]

### Added
- Implementation plans for agent notifications and neovim sync
- Custom Claude Code agents (plan-executor, terminal-brainstorm)
- zsh-vi-mode plugin

### Changed
- Moved zoxide init to end of .zshrc (fixes config warning)
- Merged system-agnostic dotfiles PR (portable paths, platform guards)
- Moved machine-specific config to `~/.zshrc.local`

## [2026-03-26]

### Added
- Initial dotfiles repo with GNU Stow
- Ghostty config: Catppuccin Mocha theme, JetBrains Mono Nerd Font
- tmux config: Catppuccin status bar, vim-tmux-navigator, vi copy mode
- zsh config: Starship prompt, fzf, zoxide, autosuggestions, syntax-highlighting
- Bootstrap script for one-command setup on new machines
- CLAUDE.md project instructions and refine-terminal skill

### Changed
- Enhanced refine-terminal skill with suggest/research modes and agentic workflow focus

### Fixed
- Ghostty theme name (spaces not dashes)
- Removed invalid `repaint-after-input` from Ghostty config
- Cleaned up `.zshenv` self-replicating Android SDK exports (392KB → 2 lines)
