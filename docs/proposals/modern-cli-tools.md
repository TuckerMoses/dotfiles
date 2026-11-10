---
created: 2026-11-10
source: plan PR #14 (2026-04-06)
---

# Modern CLI tools: eza and bat

- **What:** Install eza (ls) and bat (cat), with shell aliases that only apply when the tool is present.
- **Why here:** Day-to-day reading of files and directories in herdr panes, and bat is what the fzf preview in `fzf-enhancements` uses.
- **Effort:** small.
- **Touches:** `bootstrap.sh`, `zsh/.zshrc`, `validate.sh`.
- **Needs the real machine:** yes.
- **Notes for the plan:** The original plan also covered fd, ripgrep and delta. fd and ripgrep are already installed. delta belongs to `git-config`. Aliases must not shadow `ls` or `cat` for non-interactive shells: agents run commands through zsh and expect the plain tools.
