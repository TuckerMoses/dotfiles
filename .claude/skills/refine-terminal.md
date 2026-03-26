# Refine Terminal Setup

Use this skill to add, modify, or improve terminal tool configurations in this dotfiles repository.

## When to use

Invoke with `/refine-terminal` followed by a description of what you want to change. Examples:
- `/refine-terminal add bat (cat replacement) with Catppuccin theme`
- `/refine-terminal add a new tmux keybinding for session switching`
- `/refine-terminal add lazygit config with Catppuccin theme`
- `/refine-terminal add neovim config managed by stow`
- `/refine-terminal add eza (modern ls) aliases to zsh`

## Instructions

When refining the terminal setup, follow this workflow:

### 1. Understand the request
- Identify which tool or config is being added/modified.
- Determine if this is a new Stow package or a modification to an existing one.

### 2. Follow repository conventions
- **Catppuccin Mocha** is the universal theme — use it for any new UI-facing tool.
- **Section headers** use the `# ── Section ──────────` format in all config files.
- **Stow package structure** must mirror `$HOME`. For XDG configs: `toolname/.config/toolname/config`. For home-level dotfiles: `toolname/.toolrc`.
- **JetBrains Mono Nerd Font** is the standard font — reference it when tools need font config.
- **Vim-style keybindings** are preferred wherever a tool supports them.

### 3. For new tools (new Stow package)
1. Create the directory structure: `mkdir -p toolname/.config/toolname`
2. Write the config file with proper section headers and Catppuccin Mocha theme.
3. Add the package name to the `for pkg in ...` loop in `bootstrap.sh` (line 58).
4. If the tool needs to be installed, add install commands to `bootstrap.sh`:
   - macOS: Add to the `brew install` line (line 21) or add a new brew command.
   - Linux: Add to both the `apt install` and `dnf install` lines (lines 28-30), or use a cross-platform installer with a `command -v` guard.
5. If the tool needs shell integration (eval/source), add it to `zsh/.zshrc` in the appropriate section.
6. Update `CLAUDE.md` — add the tool to the "Tools and Their Configs" table and any relevant keybindings.

### 4. For modifications to existing configs
1. Read the current config file first.
2. Place new settings under the correct existing section, or create a new section with the standard header style.
3. Do not rearrange or reformat unrelated sections.

### 5. For new aliases or shell functions
- Add them to the `# ── Aliases ──────────` section at the bottom of `zsh/.zshrc`.
- If the alias depends on a tool, guard it: `command -v toolname &>/dev/null && alias ...`

### 6. Validate
- Ensure `bootstrap.sh` remains idempotent (guard with `command -v` or `[[ -d ... ]]`).
- Ensure no hardcoded usernames or home paths (use `$HOME` or `~`).
- Verify the Stow directory structure mirrors `$HOME` exactly.
- Confirm cross-platform support in any bootstrap changes.

## Catppuccin Mocha Palette Reference

Use these colors when configuring new tools:

| Name      | Hex       | Usage                     |
|-----------|-----------|---------------------------|
| Base      | `#1e1e2e` | Background                |
| Surface0  | `#313244` | Elevated surfaces         |
| Surface1  | `#45475a` | Borders, subtle elements  |
| Overlay0  | `#6c7086` | Muted text                |
| Subtext0  | `#a6adc8` | Secondary text            |
| Text      | `#cdd6f4` | Primary text              |
| Blue      | `#89b4fa` | Accents, active elements  |
| Green     | `#a6e3a1` | Success, confirmations    |
| Red       | `#f38ba8` | Errors, warnings          |
| Yellow    | `#f9e2af` | Caution, highlights       |
| Mauve     | `#cba6f7` | Purple accent             |
| Peach     | `#fab387` | Orange accent             |
| Teal      | `#94e2d5` | Secondary accent          |
| Lavender  | `#b4befe` | Subtle accent             |
