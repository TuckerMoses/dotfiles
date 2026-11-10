---
created: 2026-11-10
source: plan PR #33 (2026-08-03)
---

# Starship: named palette, OS and container modules

- **What:** Replace inline colour names in the prompt config with a named palette, and add the OS and container modules.
- **Why here:** Cosmetic consistency, and the OS and container markers show at a glance which machine or container a pane is on, which matters once herdr remote machines are in use.
- **Effort:** small.
- **Touches:** `starship/.config/starship.toml`, `validate.sh`.
- **Needs the real machine:** no for the config; a look at the prompt to confirm.
- **Notes for the plan:** Installed version is Starship 1.26.0. Keep the prompt's current information and order; this changes colours and adds two modules, nothing else.
