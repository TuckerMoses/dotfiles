---
created: 2026-11-10
source: plan PR #34 (2026-08-10)
---

# fzf: fd as the finder, previews, theme colours

- **What:** Configure fzf to use fd for finding files and directories, bat for file previews, eza for directory previews, and colours that match the terminal theme.
- **Why here:** There is no fzf configuration at all today; `zsh/.zshrc` only sources `fzf --zsh`. The herdr `prefix+a` picker and fzf-tab both run on fzf.
- **Effort:** small.
- **Touches:** `zsh/.zshrc`, `validate.sh`.
- **Needs the real machine:** yes.
- **Notes for the plan:** Leave out the original plan's tmux popup; herdr is the multiplexer. fzf is initialised inside `zvm_after_init` because zsh-vi-mode overrides keybindings, so settings must work from there. Previews depend on bat and eza from `modern-cli-tools`; guard them so fzf still works without those tools. Do not change the colours the `herdr-recent` picker sets for itself.
