# Changelog

All notable changes to this dotfiles setup.

## [Unreleased]

Queued work lives in `docs/proposals/`.

## [2026-11-18]

### Added
- Every third-party herdr plugin is pinned in `bootstrap.sh`: vim-herdr-navigation at `7873100` and herdr-plus at `f38df35` join the two new pins. herdr-plus installs only when Go is present, because without Go its build step downloads the latest release binary rather than building the pin. `herdr-plugins` (stowed to `~/.local/bin`) handles updates:
  - `status` shows each plugin's pinned, installed and upstream commits
  - `review <plugin>` shows what changed and leaves the judgement to the user: the new commits, full diffs of the manifest and the scripts its build runs, the release tag when the build downloads a release, lock-file package changes and every other changed file by name; it exits 1 for a target that is not upstream's own commit
  - `update` is the user's: it needs a terminal and reads its confirmations from it. It steps through each plugin that is behind; on yes it reinstalls that plugin without `--yes`, then moves its pin. A plugin installed off its pin is reinstalled at the pin first. `update <plugin> <sha>` moves one plugin to that commit (a tagged release, on upstream's default branch or a tag's commit; a fork-only commit is refused) instead of upstream HEAD, and `update` refuses to run from a linked worktree
  - `update` moves the pin only after the new commit installs, and puts the old pin back if it does not
- `review` shows rather than judges: a fail-closed install-script scanner built first was removed before merge (2026-11-19; why: `docs/plans/herdr-plugin-pins.md`)
- `validate.sh`: installed plugins match their pins (through `herdr-plugins check`), `herdr-plugins` on PATH is this checkout's, and the copied herdr-plus and reviewr config rules are checked against the commit they were read at

## [2026-11-17]

### Added
- herdr-plus is wired up. Its config is stowed from the herdr package into `~/.config/herdr/plugins/config/cloudmanic.herdr-plus/`: four project templates (dotfiles, claude-materia, Vault, aios), worktree auto-layouts for the two git repos, and three quick actions (validate dotfiles, reload herdr, summarizer pass). `prefix+t` opens projects and `prefix+space` opens quick actions, both as popups
- herdr-reviewr, pinned at `bb71050` (v0.52.2): `prefix+alt+r` toggles a pane with the agent's diff, where line comments are collected and sent to the agent. Its stowed config turns `auto_open` off, so it does not open in every new worktree
- herdr-fingers (trial), pinned at `2d9fc99`: `prefix+f` puts hints over paths, URLs, SHAs and numbers in the focused pane, and typing a hint copies the match through OSC 52. Bootstrap builds it only when cargo is present. To remove the trial, remove the targets listed in `docs/plans/herdr-fingers-trial.md`
- `$jj_status` in the spaces sidebar row: a space whose first pane is in a jj repo shows its bookmark (else the parent's bookmark, else the short change id), with `*` when `@` has changes. herdr-summarize reads it without snapshotting (`jj --ignore-working-copy`) during the passes it already runs. It is empty in other repos. `herdr-summarize jj-status DIR` prints it
- `validate.sh`:
  - every `plugin_action` key binding must name an action herdr lists, for all plugins
  - herdr-plus templates and quick actions load
  - reviewr's config is valid and `auto_open` is off
  - reviewr's and fingers' binaries run
  - `$jj_status` is computed correctly on a throwaway repo and shown on open jj spaces

## [2026-11-14]

### Fixed
- herdr-summarizer: a session's name no longer follows its latest turns. Asking a top-level session to start another agent used to rename that session, its tab and its space after the side task. Each session now has a fixed identity (short name, topic, purpose) worked out from its whole history and from names it already has; the label is that short name plus what the session is doing now, and a space is summarized from its sessions' identities
- Identity is reconsidered at 1k, 10k, 30k and 100k tokens of conversation and then every 100k, only when the owner has said something since the last check; each rename is logged with its reason
- A session that started or instructed three or more agents is named as their orchestrator, counted from its commands; pane IDs such as `w3:p1` are no longer mistaken for agent names
- No two open sessions share a short name or topic: clashes are resolved in code
- Model output is filtered before it is shown or fed back: printable characters only, length caps, no colon inside a name or state, and quoted when reused in a prompt

### Changed
- On upgrade, each session is named once and its label rewritten once (about two small model calls per open session, at most three sessions named per pass). Tabs the summarizer named earlier may be renamed once, since topics from before this change are not kept

## [2026-11-12]

### Changed
- atuin: `auto_sync = false` is set explicitly and `sync_address` points at the reserved `https://sync-disabled.invalid`, so nothing syncs in the background (atuin 18.24 rejects an empty address); `validate.sh` checks both
- The `/claude` PR review workflow runs only for comments by the repo owner, and the README clones over HTTPS from the new repo name

## [2026-11-11]

### Added
- herdr-summarizer names tabs: a tab still on herdr's default name (a number) is named after the session in it, two or three words for its subject. Tabs you named are never touched; rename one to a number to hand it back. The topic changes only with the session's subject, not its status

## [2026-11-10]

### Changed
- Work now flows proposal → plan → change. `docs/proposals/` is the queue: every file there on `master` is approved, and merging a proposal is the approval. `docs/plans/` becomes the record of what was built
- `/execute-plans` is renamed `/build-proposals`, after what it does (takes a proposal, writes its plan, builds it): it reads only `docs/proposals/` on `master`, writes each plan at execution time against the repo as it is then, and its PR deletes the executed proposals and adds their plans. It no longer reads open plan PRs or takes idea names
- The two pending plans (Jujutsu adoption, herdr-summarizer for other harnesses) moved to `docs/proposals/`, each with a "Needs decision" section
- "dotfiles scout" routine: besides keeping `ideas.md`, it submits its best ideas as proposal PRs, at most three open at a time

## [2026-11-09]

### Added
- `/execute-plans` project skill (`.claude/skills/execute-plans/`): reviews the pending plans and open plan PRs, implements independent units in parallel worktrees with Opus agents, requires a new `validate.sh` check from each, merges into one integration branch, validates it live, runs `claude-materia:adversarial-review`, and opens a single PR
- `/execute-plans` also writes plans, for ideas the user names (from the scout's `ideas.md`, the Planned list, or their own words); `--plan-only` stops at a plans-only PR
- Cloud routines restructured: "dotfiles scout" (monthly, discovery only, keeps `ideas.md` on `claude/research`) replaces the researcher and planner; "dotfiles tidy" (weekly, opens a PR) replaces the daily manager; plan execution moved out of the cloud to `/execute-plans`
- `docs/herdr.html`: guide to the whole herdr setup (sidebar, picker, statuses and herdr's dots, how event-driven updates work, key bindings, plugins, install, troubleshooting, limits), replacing the outdated annotated page from the first version

### Changed
- `bootstrap.sh` ends by running `validate.sh -q`; failures are reported but never fail the bootstrap
- herdr sidebar: a session that needs you *and* has a turn you haven't seen (herdr's `done`) gets an orange label instead of a second dot under herdr's state icon; it returns to normal when you focus the pane
- Picker: the summarizer's `done` status is shown as `finished`, since herdr uses `done` for an unseen turn; the `?` guide explains each herdr state dot and the orange label

### Added
- `validate.sh`: read-only check that every stowed file links back to this checkout, bootstrap's tools are installed, configs parse (tmux via a throwaway server, ghostty, starship, atuin, nvim, zsh), herdr plugins and the Claude integration are healthy, and the herdr-summarizer has no failed hook runs; lists come from `bootstrap.sh`
- `validate.sh` checks what programs actually load: shadow config files on tmux's built-in search path and Ghostty's Application Support config, redirecting environment variables, config-like files in nvim's `site` dir, zsh startup files outside the repo, and tmux servers, nvim instances, Ghostty and herdr still running a config from before the last change

## [2026-11-08]

### Added
- herdr-summarize v2: summaries change only after a turn ends with new conversation, and only when the model judges the change material; statuses (needs-you, working, idle, done) plus stale (untouched a week longer than the newest session) with a one-time Opus review of each stale session; links resolve through remembered and transcript-harvested agent names, so moved or renamed agents stay nested
- herdr pane descriptions: `herdr-summarize` writes a label, heat (time since the transcript changed), whose move it is, and a full description for each Claude pane and space, from transcripts on disk via Haiku; nothing is sent to running agents
- `prefix+a` recent-sessions popup (`herdr-recent`, fzf): decisions first, then hottest, with the description previewed; sessions an orchestrator drives by name are nested under it
- `herdr-summarizer/`: opt-in herdr plugin driven by herdr events (turn ended, agent detected, pane moved or focused) instead of a timer; the hook hands off to a detached worker so herdr never waits on a model; `install.sh` links it, removes the launchd job used by the first version, and is never run by `bootstrap.sh`
- `prefix+a` picker: `?` shows a guide to the statuses, columns and update rules

### Changed
- herdr sidebar: width 26 → 34; agent rows show heat and whose-move with the label below (agent-kind row dropped); space rows add a summary row
- ghostty: `macos-non-native-fullscreen = visible-menu`, so the menu-bar reveal no longer swallows clicks on the herdr tab row

## [2026-06-24]

### Fixed
- Removed stale `claude-config` references from `.gitignore` and `bootstrap.sh` (leftover from the package removal)

## [2026-06-23]

### Fixed
- Corrected README description of game-sounds plugin — bootstrap configures the custom sound pack but doesn't install the plugin itself

## [2026-06-20]

### Changed
- Removed `claude-config` stow package from dotfiles — Claude Code config migrated to a standalone private repo (`~/claude-config`). Bootstrap no longer stows claude-config.

## [2026-05-17]

### Changed
- Updated CLAUDE.md and README.md structure descriptions to include `plans/` in the `claude-config` stow package listing

## [2026-04-14]

### Fixed
- Removed stale `.claude/` directory references from CLAUDE.md and README.md structure trees (replaced by `claude-config` stow package in PR #18)

## [2026-04-12]

### Added
- adversarial-review skill for multi-reviewer plan verification with iterative refinement loops
- Structured discussion mode and stuck protocol in global interaction contract
- DOM pattern documentation for telescopius-research skill

### Fixed
- Triage agent: prospective precondition evaluation when gate is blocked

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
- Adversarial verify loop in workspace-manager and project-manager facelift subcommands

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
