# Refine Terminal Setup

Use this skill to add, modify, improve, or research terminal tool configurations in this dotfiles repository. This skill can both implement changes and provide suggestions, research, and recommendations — with a focus on optimizing for agentic AI-assisted development workflows.

## When to use

Invoke with `/refine-terminal` followed by a description. Supports three modes:

**Implement** — make a specific change:
- `/refine-terminal add bat (cat replacement) with Catppuccin theme`
- `/refine-terminal add a new tmux keybinding for session switching`
- `/refine-terminal add lazygit config with Catppuccin theme`

**Suggest** — get recommendations for improving the setup:
- `/refine-terminal suggest improvements for agentic coding workflows`
- `/refine-terminal suggest modern replacements for standard unix tools`
- `/refine-terminal what tmux plugins would improve my workflow?`
- `/refine-terminal suggest ways to make my terminal more AI-friendly`

**Research** — look up the latest tools, options, or best practices:
- `/refine-terminal research the latest Ghostty features I'm not using`
- `/refine-terminal research best zsh plugins for developer productivity`
- `/refine-terminal what are the trending terminal tools right now?`
- `/refine-terminal compare alacritty vs ghostty vs wezterm`

## Instructions

### Determine the mode

Read the user's prompt and classify it:
- **Implement**: The user wants a concrete change made to config files. Proceed to the implementation workflow below.
- **Suggest**: The user wants recommendations. Analyze the current configs, identify gaps or improvements, and present actionable suggestions ranked by impact. Do not make changes unless asked.
- **Research**: The user wants information about tools, features, or best practices. Use web search to find current information, then summarize findings with relevance to this specific setup.

For suggest and research modes, always frame recommendations through the lens of this repo's conventions (Catppuccin Mocha, Stow-managed, vim-keybindings, cross-platform).

---

## Agentic Workflow Focus

When suggesting or researching, prioritize improvements that enhance AI-assisted and agentic development workflows. Key areas:

### Terminal multiplexing for agents
- Tmux session/window management that supports running multiple AI agents in parallel
- Named sessions and windows for context switching between agent tasks
- Easy pane inspection and scrollback for reviewing agent output

### Fast navigation and context gathering
- Tools that help AI agents quickly find files, search code, and navigate projects (fzf, ripgrep, fd, zoxide, tree, eza)
- Shell history optimization for agent workflows (longer history, better search, deduplication)
- Directory bookmarking and project switching (tmux-sessionizer, wd plugin, zoxide)

### Output readability
- Tools that make terminal output more parseable: bat (syntax-highlighted cat), delta (better git diffs), glow (terminal markdown), jq (JSON), yq (YAML)
- Pager configuration for long outputs
- Log tailing and filtering tools

### Git workflow acceleration
- lazygit or similar TUI for fast git operations
- Git aliases for common agentic patterns (quick commits, branch management, diff review)
- Pre-commit hooks and CI feedback in the terminal

### Environment management
- Fast environment switching (direnv, mise/asdf for runtime versions)
- Project-local tool configuration
- Container and devcontainer integration from the terminal

### Monitoring and observability
- Process monitoring (btop/htop)
- Disk usage analysis (dust, duf)
- Network debugging (curlie, httpie)

When the user asks for suggestions without a specific focus, default to "what would make this terminal setup better for working with AI coding agents?"

---

## Implementation Workflow

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

---

## Suggest/Research Workflow

### 1. Gather context
- Read the current configs (`bootstrap.sh`, `.zshrc`, `.tmux.conf`, `starship.toml`, `ghostty/config`) to understand what's already set up.
- Identify what's missing or could be improved relative to the user's ask.

### 2. Research (when needed)
- Use web search to find current information about tools, features, and best practices.
- Look for Catppuccin theme availability — strong preference for tools that have official Catppuccin Mocha support.
- Check cross-platform availability (must work on both macOS and Linux).
- Verify the tool is actively maintained and widely adopted.

### 3. Present findings
- Rank suggestions by impact (highest value first).
- For each suggestion, include:
  - **What**: Tool name and one-line description.
  - **Why**: How it improves the workflow (especially for agentic development).
  - **Effort**: Low/Medium/High to integrate into this repo.
  - **Catppuccin support**: Yes/No/Partial.
- Group related suggestions together.
- If the user likes a suggestion, offer to implement it immediately.

---

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
