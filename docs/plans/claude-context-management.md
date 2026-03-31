---
status: in-progress
created: 2026-03-30
updated: 2026-03-31
---

# Plan: Claude Context Management via Stow

## Goal
Make CLAUDE.md (working memory) and supporting context files available globally so every Claude Code session — regardless of which repo you're in — picks up your people, projects, terms, and preferences automatically.

## Problem
Today, CLAUDE.md only works if it lives in the repo you're currently working in, or in `~/.claude/`. If you manage context in a separate repo (like `agent_management`), none of that context is available when you start a Claude Code session in another project. Cowork sessions have the same issue — they only see what's in the selected workspace folder.

## Context
- Dotfiles repo at `~/dotfiles`, managed with GNU Stow
- Stow packages mirror `$HOME` — a `claude/` package would symlink files into `~/.claude/`
- Claude Code reads `~/.claude/CLAUDE.md` as global context for all sessions
- `agent_management` repo currently holds CLAUDE.md, TASKS.md, and a `memory/` directory

## Implementation Steps

### 1. Create the Stow package structure

```
dotfiles/
└── claude/
    └── .claude/
        └── CLAUDE.md
```

This mirrors `$HOME/.claude/CLAUDE.md` when stowed.

### 2. Write the global CLAUDE.md

Move the working memory content from `agent_management/CLAUDE.md` into `dotfiles/claude/.claude/CLAUDE.md`. This becomes the single source of truth for global context.

Start with the current content:

```markdown
# Memory

## Me
Tucker, Engineer. Prefers terminal workflows. Uses Claude Code, Cowork, and chat sessions.

## People
| Who | Role |
|-----|------|

## Terms
| Term | Meaning |
|------|---------|

## Projects
| Name | What |
|------|------|
| **agent_management** | Repo for managing agent context across Claude sessions |
| **dotfiles** | Terminal environment config managed with GNU Stow |

## Preferences
- Terminal-first; prefers CLI over GUI
- Wants better session tracking across Claude Code, Cowork, and chat
- Catppuccin Mocha theme, JetBrains Mono NF, vim-style keybindings
```

### 3. Add `claude` to bootstrap.sh

Add `claude` to the Stow package loop:

```bash
for pkg in tmux zsh ghostty starship claude; do
```

### 4. Stow the package

```bash
cd ~/dotfiles && stow claude
```

Verify the symlink:

```bash
ls -la ~/.claude/CLAUDE.md
# Should point to ~/dotfiles/claude/.claude/CLAUDE.md
```

### 5. Handle per-repo overrides

Claude Code merges context: it reads the global `~/.claude/CLAUDE.md` AND any `CLAUDE.md` in the current repo. This means:

- **Global context** (people, terms, preferences) → lives in `dotfiles/claude/.claude/CLAUDE.md`
- **Repo-specific context** (project conventions, architecture, code style) → stays in each repo's own `CLAUDE.md`

No changes needed to existing repos. They keep their own CLAUDE.md for repo-specific instructions, and the global file layers underneath.

### 6. Test

- `cd ~/dotfiles && stow claude`
- Open a Claude Code session in a random repo (not `dotfiles` or `agent_management`)
- Ask Claude something that requires context from the global CLAUDE.md (e.g., "what theme do I use?")
- Verify it knows the answer from the global context

### 7. Ongoing maintenance

Edit `~/dotfiles/claude/.claude/CLAUDE.md` directly (the symlink means changes apply immediately, just like all other Stow-managed configs). Use the productivity skill's `/productivity:memory-management` command in Cowork sessions to update it interactively.

## What This Doesn't Solve

- **Cowork sessions** don't read `~/.claude/CLAUDE.md` — they only see the selected workspace. For Cowork, you'd still want to select the `agent_management` or `dotfiles` folder, or manually point to the relevant context.
- **Chat sessions** (claude.ai) have no access to local files at all. Chat remains stateless unless you paste context in.
- **TASKS.md** is intentionally left out of the global scope. Tasks are typically project-specific. If you want a global task list, you can add it to the Stow package later.

## Dependencies
- GNU Stow (already installed via bootstrap.sh)
- Claude Code (reads `~/.claude/CLAUDE.md` automatically)
