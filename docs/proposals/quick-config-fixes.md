---
created: 2026-11-10
source: plan PR #12 (2026-04-06)
---

# Quick config fixes

- **What:** Three small fixes: make the zsh-vi-mode line in `zsh/.zshrc` portable instead of calling `$(brew --prefix)`; add a Ghostty Shift+Enter binding for multiline input in Claude Code if it is still needed; add theme selection colours to Ghostty.
- **Why here:** `source $(brew --prefix)/...` on line 9 of `.zshrc` fails on Linux and spawns a subprocess on every shell start. The other two are small daily irritations.
- **Effort:** small.
- **Touches:** `zsh/.zshrc`, `ghostty/.config/ghostty/config`, `validate.sh`.
- **Needs the real machine:** yes.
- **Notes for the plan:** Two items from the original plan are already done or moot: tmux `allow-passthrough` landed in PR #38, and Ghostty's scrollback default was raised upstream. Check whether Shift+Enter already works through herdr before adding a binding; recent herdr releases changed how it passes that key.
