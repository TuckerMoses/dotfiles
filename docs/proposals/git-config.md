---
created: 2026-11-10
source: plan PR #32 (2026-08-03)
---

# Git config as a stow package, with delta

- **What:** A `git` stow package that manages `~/.gitconfig`: delta as the pager, a few aliases (graph log, branches by date, undo), and sensible defaults (histogram diffs and similar).
- **Why here:** Git is the one core tool with no config in this repo. `~/.gitconfig` exists on this machine but is unmanaged, with no pager and no aliases, so `validate.sh` cannot say whether it is what git uses.
- **Effort:** medium.
- **Touches:** new `git/` package, `bootstrap.sh` (package list, install delta), `validate.sh`.
- **Needs the real machine:** yes.
- **Notes for the plan:** `~/.gitconfig` already exists, so stow will refuse to link until its content (name, email, credential helper, anything else) is carried into the package or into an included machine-local file. Identity should not be hardcoded in the repo. delta is not installed. This overlaps `modern-cli-tools` (which also installs delta) and `fzf-enhancements`; build them as one unit.
- **Links:** https://github.com/dandavison/delta
