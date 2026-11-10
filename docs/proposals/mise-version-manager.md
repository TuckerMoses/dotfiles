---
created: 2026-11-10
source: plan PR #36 (2026-09-21)
---

# mise replaces nvm

- **What:** Manage Node (and optionally Python) versions with mise instead of nvm.
- **Why here:** nvm takes 0.37s of a 0.8s interactive shell start (measured 2026-11-09 on this machine). Every herdr pane and every restored agent starts a shell. mise uses shims and adds almost nothing.
- **Effort:** medium.
- **Touches:** `bootstrap.sh`, `zsh/.zshrc`, `validate.sh`; `~/.zshrc.local` on this machine.
- **Needs the real machine:** yes.
- **Notes for the plan:** The nvm init is not in the repo; it lives in `~/.zshrc.local`, which is machine-local and untracked, so removing it is a step outside the repo. Node versions installed under nvm today: v16.13.0, v17.1.0, v25.8.2; carry over whichever is in use. Conda (0.14s) is separate and stays. The agent venv at `~/.claude/venv` is built on the python.org 3.8 install and must keep working.
- **Links:** https://mise.jdx.dev/
