# CLAUDE.md

This repository manages personal dotfiles using [GNU Stow](https://www.gnu.org/software/stow/). It configures a terminal development environment across macOS and Linux.

## Repository Structure

```
dotfiles/
├── .github/workflows/claude-pr-review.yml  # Claude Code Action for PR reviews
├── bootstrap.sh                     # One-command setup (idempotent)
├── validate.sh                      # Read-only check: everything linked, installed, loading cleanly
├── atuin/.config/atuin/config.toml  # Shell history config
├── ghostty/.config/ghostty/config   # Terminal emulator config
├── herdr/.config/herdr/             # Herdr config + .local/bin/herdr-{summarize,recent}
├── herdr-summarizer/                # Opt-in herdr plugin (not stowed)
├── nvim/.config/nvim/               # Neovim config with Claude Code sync
├── starship/.config/starship.toml   # Prompt engine config
├── tmux/.tmux.conf                  # Terminal multiplexer config
├── zsh/.zshrc                       # Shell configuration
├── docs/herdr.html                  # Guide to the herdr setup
├── docs/plans/                      # Implementation plans
├── .claude/skills/execute-plans/    # /execute-plans project skill
├── CHANGELOG.md                     # Project changelog
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
| **atuin** | `.config/atuin/config.toml` | Atuin shell history (SQLite-backed, fuzzy search, per-directory filtering) |
| **ghostty** | `.config/ghostty/config` | Ghostty terminal emulator (Catppuccin Mocha theme, JetBrains Mono NF) |
| **nvim** | `.config/nvim/` | Neovim with Claude Code sync (auto-reload, diffview.nvim, claudecode.nvim) |
| **starship** | `.config/starship.toml` | Starship cross-shell prompt (minimal single-line, language detection) |
| **tmux** | `.tmux.conf` | Tmux multiplexer (vim-tmux-navigator, Catppuccin status bar, TPM plugins) |
| **herdr** | `.config/herdr/config.toml`, `.local/bin/herdr-{summarize,recent}` | Herdr terminal workspace manager (tmux-style keys, vim-herdr-navigation, sounds, pane descriptions + `prefix+a` recent-sessions picker) — stowed with `--no-folding` |
| **herdr-summarizer** | *(not stowed)* `install.sh`, `plugin/` | Opt-in herdr plugin: on agent turn-end, agent-detected, pane-moved and pane-focused events it runs `herdr-summarize` (labels, status, stale reviews, descriptions). No timer. `install.sh` links it; never run by `bootstrap.sh` |
| **zsh** | `.zshrc` | Zsh shell via Oh My Zsh (plugins: git, wd, fzf-tab, autosuggestions, syntax-highlighting) |

### Notifications

Claude Code notifications and sounds are handled by **Herdr** (toasts, `prefix+o` jump-to-agent, and
`[ui.sound]` in `herdr/.config/herdr/config.toml`, which plays herdr's built-in sounds). The former
claude-notifications-go and game-sounds plugins were removed on 2026-11-03, and the `notification-sounds/`
pack on 2026-11-12.

### Auto-installed dependencies (via bootstrap.sh)

- **Homebrew** (macOS) / **apt**/**dnf** (Linux) for system packages
- **GNU Stow** for symlink management
- **Oh My Zsh** with custom plugins (zsh-autosuggestions, zsh-syntax-highlighting)
- **Neovim**, **fzf**, **zoxide**, **Starship**, **Atuin**

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
- **atuin**: `Ctrl+R` (shell history search), Up arrow (per-directory history)
- **fzf**: `Ctrl+T` (files)
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
./bootstrap.sh    # ends by running ./validate.sh -q
```

### Proposals, plans and execution
Work flows one way: proposal, then plan, then change.

- **Proposals** are short statements of something worth doing, one file each in `docs/proposals/`. **Every proposal on
  `master` is approved**; merging it is the approval, and closing its PR with a comment is the rejection. They come
  from the scheduled cloud routine "dotfiles scout" (monthly, Opus; at most three proposal PRs open at a time, from
  `claude/proposal/*` branches), from the user, or from any session. Format: `docs/proposals/README.md`.
- **Plans** are written only by the project skill `/build-proposals`, at the moment it executes a proposal, against
  the repo and machine as they are then. `docs/plans/` is the record of what was built, not a queue.
- **Execution** is `/build-proposals` (`.claude/skills/build-proposals/SKILL.md`), run locally because dotfiles can
  only be validated on the real machine: parallel worktrees with Opus agents, a new `validate.sh` check per unit, one
  integration branch validated live, an adversarial review, then one PR. That PR deletes the executed proposals and
  adds their plans.

To queue something yourself, add a proposal file. Do not write a plan by hand and do not add a status field.

A second routine, "dotfiles tidy" (weekly, Sonnet), keeps `CHANGELOG.md`, `README.md` and the plans index in sync with
the repo and opens a PR when something is off. Neither routine pushes to `master` or deletes branches.

### Herdr guide
`docs/herdr.html` is the README for everything this repo adds to herdr (sidebar rows, the `prefix+a` picker,
the summarizer plugin, key bindings, plugins, troubleshooting). Its terminal figures are hand-drawn with
made-up sessions, not captures. Update it in the same change whenever `herdr/` or `herdr-summarizer/` changes
behaviour a reader would see.

### Validating
`./validate.sh` (or `-q` for warnings and failures only) checks that every stowed file links back
to this checkout, bootstrap's tools are installed, each config parses (tmux, ghostty, starship, atuin,
nvim and zsh, using throwaway instances where needed), herdr's plugins and Claude integration are healthy,
and the opt-in herdr-summarizer has no failed hook runs. It also checks what programs *actually* load, since
a correctly stowed file can still not be live: another file on a program's search path (tmux reads every
file in the list built into its binary; Ghostty also reads its Application Support config), an environment
variable pointing elsewhere (`ZDOTDIR`, `STARSHIP_CONFIG`, `NVIM_APPNAME`, ...), config-like files in nvim's
`site` dir, zsh startup files outside the repo, or a running tmux server, nvim, Ghostty or herdr that loaded
its config before the last change (with the command to fix it). It reads package, tool and plugin lists from
`bootstrap.sh`, so new packages are covered automatically. Run it after any change; it exits 1 on failure.

## CI / GitHub Actions

A GitHub Actions workflow (`.github/workflows/claude-pr-review.yml`) runs the `anthropics/claude-code-action@v1` action. It triggers when the repo owner writes an inline PR review comment containing `/claude`; comments from anyone else are ignored. Claude reads the comment, implements the requested change (following this file's conventions), and replies.

**Requirements**: The Claude GitHub App must be installed on this repo, and an `ANTHROPIC_API_KEY` repository secret must be set.

## Git Workflow for Sessions

Each Claude session should follow this workflow at the start:

1. **Check for unstaged/uncommitted changes.** If the tree is dirty, flag it before doing anything — it likely means a previous session or manual edit left things in a bad state.
2. **Check the current branch.** If it clearly matches the task (e.g., you're on `feat/tmux-keybinds` and the user asks to tweak tmux keybinds), stay on it. Otherwise, switch to `master`.
3. **Determine if the task modifies files.** If read-only (explaining code, answering questions), no further setup needed. If changes are required, propose a branch name and use `EnterWorktree` to isolate the work. **Exception:** light Claude config changes (skill edits, CLAUDE.md tweaks, agent updates, settings changes) can bypass the worktree process and commit/push directly to master. These are small, low-risk config updates that don't warrant branch isolation.
4. **Assume a clean git tree.** Each task should start from a clean state on its branch or on `master`. If it's not clean, ask — the user may have made a mistake.

### Branch naming

- **Local sessions**: use plain descriptive names — `feat/add-nvim-config`, `fix/zsh-path-order`. Do **not** prefix with `claude/`.
- **`claude/` prefix** is reserved for automated and scheduled branches (GitHub Actions, Claude Code Actions).

### Worktree testing

Stow symlinks point to absolute paths in the main repo directory. **Never run `stow` or `bootstrap.sh` from a worktree** — it will repoint symlinks to the worktree, and they'll break when the worktree is cleaned up.

To test changes made in a worktree:

1. Commit and push the branch from the worktree.
2. Remove the worktree (`git worktree remove .worktrees/<name>`) — git won't allow checking out a branch that's active in another worktree.
3. In the main repo, check out the branch and pull (`git checkout <branch> && git pull`). **Claude should do this automatically** — don't make the user type the branch name.
4. Symlinks now serve the branch's version of configs — prompt the user with testing instructions.
5. If changes need fixing, check out `master` in the main repo and create a new worktree for further work.

Similarly, `source`-testing a worktree's `.zshrc` gives false confidence — all paths in `.zshrc` are absolute (`$HOME/.oh-my-zsh`, brew prefix, etc.), so it loads the live system's plugins regardless of which copy of `.zshrc` was sourced.

### Worktree cleanup

Worktrees should be removed before testing (see above). In general, remove a worktree once its branch has been pushed — there's no reason to keep it around.

## Rules for AI Assistants

- **Never hardcode usernames or home directory paths** in configs — use `$HOME` or `~` where possible. (Exception: conda/nvm blocks that are auto-generated.)
- **Preserve the section comment style** (`# ── Section ──────────`) when adding to config files.
- **Maintain Catppuccin Mocha consistency** — use the palette when adding new UI elements.
- **Keep bootstrap.sh idempotent** — guard installations with existence checks (`command -v`, `[[ -d ... ]]`).
- **Don't add unnecessary complexity** — this is a personal dotfiles repo, not a framework.
- **Test cross-platform** — any bootstrap changes must work on both macOS and Linux.
- **Stow structure must mirror `$HOME`** — files must be placed exactly where they'd live under `~`.
- **Prefer appending to existing config sections** over creating new files when possible.
