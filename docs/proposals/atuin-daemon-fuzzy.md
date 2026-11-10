---
created: 2026-11-10
source: plan PR #13 (2026-04-06)
---

# Atuin daemon mode

- **What:** Turn on Atuin's background daemon and its faster fuzzy search.
- **Why here:** History search is used constantly and is configured as plain `search_mode = "fuzzy"` today. The daemon keeps the index in memory.
- **Effort:** small.
- **Touches:** `atuin/.config/atuin/config.toml`, `validate.sh`.
- **Needs the real machine:** yes.
- **Notes for the plan:** Confirm the option names against the installed version (atuin 18.16.1) before writing them; the original plan was written in April. The daemon is a long-running background process, so the plan must say how it starts and stops, and `validate.sh` should report whether it is running.
- **Links:** https://docs.atuin.sh/
