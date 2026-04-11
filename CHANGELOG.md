# Changelog

All notable changes to this dotfiles setup.

## [Unreleased]

### Planned
- Jujutsu adoption for lock-free agent workflows ([plan](docs/plans/jujutsu-adoption.md))

## [2026-04-09]

### Added
- `claude-config` stow package: migrated `~/.claude` authored config (agents, skills, kinds, settings) into version-controlled dotfiles ([PR #18](https://github.com/TuckerMoses/dotfile-setup/pull/18), [plan](docs/plans/claude-context-management.md))
  - Global CLAUDE.md with interaction contract and layered system philosophy
  - 7 custom agents (architect, debugger, expert, house-cleaner, house-wrecker, researcher, teacher)
  - 20+ skills (consult, disco, kind-bootstrapper, level-up, project-manager, skill-creator, and more)
  - Kind system (`kinds/index.md`, `workspace.md`, `project.md`) for organizing work artifacts
  - Global settings.json with permission and tool policies
- Global BACKLOG.md and CHANGELOG.md at `~/.claude` for cross-session tracking
- Backlog and Changelog as container-scoped kinds in the kind system

### Changed
- Bootstrap stows `claude-config` with `--no-folding` to create file-level symlinks inside `~/.claude/` (preserves Claude Code's skill discovery and sandbox)
- Removed old `.claude/agents/` and `.claude/skills/` files (replaced by `claude-config` package)
- CLAUDE.md: light Claude config changes (skill/agent/settings edits) can bypass the worktree workflow and commit directly to `master`

## [2026-04-08]

### Added
- Expanded Top Gun sound pack with ~50 new clips across all event types ([PR #17](https://github.com/TuckerMoses/dotfile-setup/pull/17))

### Changed
- Reorganized notification-sounds into franchise subdirectories (`batman/`, `mario/`, `metal-gear-solid/`, `top-gun/`, etc.) — previously flat `<event>/` structure ([PR #17](https://github.com/TuckerMoses/dotfile-setup/pull/17))
- Bootstrap builds custom sound pack from selected themes via `--sounds=` flag, with `--all` as default and `--list-sounds` to enumerate available themes ([PR #17](https://github.com/TuckerMoses/dotfile-setup/pull/17))
- Re-enabled all event sounds (session-start, task-acknowledge, error) — reverting the limit from PR #16 ([PR #17](https://github.com/TuckerMoses/dotfile-setup/pull/17))

### Fixed
- Use hardlinks instead of symlinks for custom sound pack (BSD `find -type f` skips symlinks) ([PR #17](https://github.com/TuckerMoses/dotfile-setup/pull/17))

## [2026-04-06]

### Changed
- Limit game-sounds plugin to `task-complete` and `permission` events only; disabled `session-start`, `task-acknowledge`, and `error` so notifications only fire when Claude is waiting for user input ([PR #16](https://github.com/TuckerMoses/dotfile-setup/pull/16))

### Fixed
- Claude Code plugin marketplace and config path issues in `bootstrap.sh`: use `Citedy/claude-plugins` marketplace, correct `game-sounds@citedy` install syntax, write notifications config to the plugin's actual cache path, and bump `find` maxdepth to match versioned cache directories ([PR #15](https://github.com/TuckerMoses/dotfile-setup/pull/15))

## [2026-04-02]

### Added
- Claude Code notification system with custom game sound pack ([PR #11](https://github.com/TuckerMoses/dotfile-setup/pull/11), [plan](docs/plans/tmux-agent-notifications.md))
  - Desktop banners via claude-notifications-go plugin (click-to-focus tmux pane switching)
  - Game sound effects via game-sounds plugin with curated `notification-sounds/` pack
  - Bootstrap installs both plugins and configures custom sound pack

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
