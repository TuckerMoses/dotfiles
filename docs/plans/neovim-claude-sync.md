---
status: done
created: 2026-03-27
updated: 2026-03-31
---

# Plan: Neovim ↔ Claude Code Sync

## Goal
Keep Neovim in sync with file changes Claude Code makes on disk, and provide a way to review those changes as diffs inside Neovim.

## Context
- Neovim (aliased as `vim`/`v`), run inside tmux alongside Claude Code
- tmux already has `focus-events on` configured
- User works across multiple projects in `~/Desktop/projects/`
- Claude Code edits files directly on disk (and sometimes commits them)

## Architecture

Three tiers, each building on the last. Implement in order.

---

## Tier 1: Auto-reload (no plugins needed)

### What it does
When you switch from a Claude Code pane back to Neovim, all externally modified buffers reload automatically.

### Implementation
Add to Neovim config (likely `~/.config/nvim/init.lua` or equivalent):

```lua
-- Auto-reload files changed outside Neovim
vim.o.autoread = true

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  pattern = "*",
  callback = function()
    if vim.fn.mode() ~= "c" then
      vim.cmd("checktime")
    end
  end,
})

-- Notify when a file is reloaded
vim.api.nvim_create_autocmd("FileChangedShellPost", {
  pattern = "*",
  callback = function()
    vim.notify("File changed on disk. Buffer reloaded.", vim.log.levels.INFO)
  end,
})
```

### Why this works
- `autoread` tells Neovim to accept external changes without prompting
- `FocusGained` fires when you switch tmux panes (because `focus-events on` is set)
- `CursorHold` catches changes even without a pane switch (after `updatetime` ms of idle)
- The `FileChangedShellPost` notification tells you when a reload happens

### Verify
1. Open a file in Neovim in one tmux pane
2. Edit that same file with Claude Code in another pane
3. Switch back to the Neovim pane — the buffer should update automatically

---

## Tier 2: Diff review with diffview.nvim

### What it does
After Claude Code makes changes (especially git commits), open a diff view inside Neovim to review exactly what changed.

### Implementation

Install `diffview.nvim` (via lazy.nvim or your plugin manager):

```lua
{
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewFileHistory" },
  keys = {
    { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Review unstaged changes" },
    { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File git history" },
    { "<leader>gc", "<cmd>DiffviewOpen HEAD~1<cr>", desc = "Review last commit" },
  },
}
```

### Workflow
- Claude Code edits files → press `<leader>gd` to see all unstaged changes in a side-by-side diff
- Claude Code commits → press `<leader>gc` to review the last commit
- Navigate between changed files with `<Tab>` / `<S-Tab>`
- Stage/unstage hunks directly from the diff view

### Why diffview
- Full side-by-side diff with syntax highlighting
- Works with git history (natural fit since Claude Code commits)
- Can stage individual hunks — useful for accepting some Claude changes and rejecting others
- Much more ergonomic than `:DiffOrig` or external `git diff`

---

## Tier 3: claudecode.nvim (deep integration)

### What it does
Provides the same integration as the VS Code extension — Claude Code can communicate directly with Neovim over WebSocket, enabling:
- File selection awareness (Claude sees what you have open/selected)
- Direct navigation to files Claude references
- Automatic buffer reload on changes

### Implementation

Install `claudecode.nvim` (by Coder):

```lua
{
  "coder/claudecode.nvim",
  config = true,
  keys = {
    { "<leader>cc", "<cmd>ClaudeCodeToggle<cr>", desc = "Toggle Claude Code" },
    { "<leader>cs", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send selection to Claude" },
  },
}
```

### What this enables
- Claude Code knows which files are open in your Neovim buffers
- You can visually select code and send it to Claude as context
- Claude Code can open files in Neovim directly
- Changes are auto-reloaded via the WebSocket connection (faster than filesystem polling)

### Caveats
- Newer plugin, may have rough edges
- Requires Claude Code to be started from within Neovim (or with the right environment)
- Check the repo for current compatibility with your Claude Code version

---

## Recommended Order
1. **Start with Tier 1** — takes 5 minutes, solves the core problem
2. **Add Tier 2** when you want to review Claude's changes before accepting them
3. **Try Tier 3** if you want the full IDE-like integration

## Files to Modify
- `~/.config/nvim/init.lua` (or wherever your Neovim config lives)
- Plugin manager config for Tiers 2-3
- Consider adding Neovim config to dotfiles repo as a `nvim/.config/nvim/` stow package

## Dependencies
- Tier 1: None (built-in Neovim)
- Tier 2: `sindrets/diffview.nvim` + git
- Tier 3: `coder/claudecode.nvim`
