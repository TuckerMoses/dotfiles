---
status: pending
created: 2026-03-30
updated: 2026-03-30
---

# Plan: Jujutsu (jj) Adoption for Lock-Free Agent Workflows

## Goal
Migrate the dotfiles repo to use Jujutsu (jj) in colocated mode, eliminating the `.git/index.lock` collisions that occur when multiple Claude Code or Cowork agents operate on the same repo simultaneously.

## Problem
Git uses `index.lock` as a mutex for any operation that touches the staging area. When multiple agents (Claude Code sessions, Cowork, terminal workflows) run concurrently against the same repo, they collide on this lock and fail with:

```
fatal: Unable to create '.git/index.lock': File exists.
```

This is a fundamental limitation of Git's concurrency model.

## Why Jujutsu
Jujutsu uses an operation log instead of lock files. Concurrent writes are detected and merged automatically via 3-way merge of operation heads — the same way it handles remote conflicts. This means multiple agents can commit, rebase, and modify the repo simultaneously without collisions.

Additional benefits:
- **Auto-snapshotting**: Every file change is captured automatically (no `git add` needed)
- **Colocated mode**: Runs alongside Git invisibly — GitHub, CI, and teammates see standard Git
- **Undo everything**: `jj undo` works on any operation, not just commits
- **Sandbox revisions**: Agents can work in lightweight revisions, and you curate with `jj split`

## Context
- Dotfiles repo at `~/dotfiles`, managed with GNU Stow
- Multiple Claude Code sessions run concurrently in tmux panes
- Cowork sessions also write to the same repos
- Git + GitHub remain the remote/collaboration layer

## Implementation Steps

### 1. Install jj via bootstrap.sh

Add jj to the macOS and Linux install sections:

**macOS:**
```bash
brew install jj
```

**Linux (Ubuntu 22.04+):**
```bash
if ! command -v jj &>/dev/null; then
    sudo add-apt-repository -y ppa:jujutsu/jj
    sudo apt update && sudo apt install -y jj
fi
```

**Linux (Fedora):**
```bash
sudo dnf install -y jj
```

Add these to the appropriate platform blocks in `bootstrap.sh`, following the existing pattern of feature-detection guards.

### 2. Configure jj user identity

Add to bootstrap.sh after the install step:

```bash
if command -v jj &>/dev/null; then
    jj config set --user user.name "$(git config --global user.name)"
    jj config set --user user.email "$(git config --global user.email)"
fi
```

This pulls from existing git config so there's no duplication.

### 3. Colocate the dotfiles repo

From the repo root:

```bash
cd ~/dotfiles
jj git init --colocate
```

This creates a `.jj/` directory alongside `.git/`. Both coexist — `jj` commands and `git` commands both work. The `.jj/` directory is already in Git's default ignore patterns.

### 4. Add CLAUDE.md instructions for this repo

Add a version control section to the dotfiles repo's `CLAUDE.md`:

```markdown
## Version Control

This repo uses Jujutsu (jj) in colocated mode alongside Git. Use `jj` commands instead of `git` for all version control operations.

Key differences from git:
- No `git add` needed — jj auto-tracks all file changes
- `jj new` instead of creating commits manually — jj snapshots the working copy automatically
- `jj describe -m "message"` to set the current change's description
- `jj new` to finish a change and start a new one
- `jj log` instead of `git log`
- `jj diff` instead of `git diff`
- `jj bookmark set <name>` instead of `git branch`
- `jj git push` to push to GitHub (pushes bookmarks as git branches)
- Never run raw `git` commands — let jj manage the git backend

Common workflows:
- Start work: changes are auto-tracked, just edit files
- Describe what you did: `jj describe -m "your message"`
- Finish and start next change: `jj new`
- Push to remote: `jj bookmark set <name> && jj git push`
- See history: `jj log`
- Undo anything: `jj undo`
```

### 5. Verify colocated mode works

```bash
# Make a test change
echo "test" >> /tmp/jj-test
jj status          # should show working copy changes
jj log             # should show operation history
git status         # should still work (colocated)
git log --oneline  # should match jj's view
```

### 6. Test concurrent operations

Open two terminal panes, both in `~/dotfiles`:

**Pane 1:**
```bash
jj describe -m "pane 1 change"
```

**Pane 2 (simultaneously):**
```bash
jj describe -m "pane 2 change"
```

Both should succeed without lock errors. If the operations diverge, `jj log` will show forked operation heads and `jj op log` shows the full operation history.

### 7. Update the plans README

Mark this plan as `done` and note it in the changelog.

## What Changes for Daily Workflow

| Before (git) | After (jj) |
|--------------|------------|
| `git add . && git commit -m "msg"` | `jj describe -m "msg" && jj new` |
| `git status` | `jj status` |
| `git diff` | `jj diff` |
| `git log --oneline` | `jj log` |
| `git push` | `jj git push` |
| `git branch feature` | `jj bookmark set feature` |
| `git stash` | Not needed — jj auto-snapshots |
| `git rebase -i` | `jj rebase`, `jj squash`, `jj split` |
| Lock errors with concurrent agents | No locks — concurrent operations merge automatically |

## What Stays the Same

- GitHub as remote (jj pushes via git backend)
- `.github/workflows/` CI works unchanged
- Stow workflow is unaffected (it only cares about file paths, not VCS)
- Teammates/CI see standard git history

## Rollback

If jj doesn't work out:
```bash
rm -rf ~/dotfiles/.jj
```

Git is untouched. The colocated setup is fully reversible.

## Dependencies
- jj (via Homebrew on macOS, PPA on Ubuntu, dnf on Fedora)
- Existing git + GitHub setup (unchanged)
