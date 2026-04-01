-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

-- ── External file change notification ──────────
-- LazyVim already sets autoread and calls checktime on FocusGained/CursorHold.
-- This adds a visible notification when a buffer is reloaded from disk,
-- so you know when Claude Code (or another tool) has modified a file.
vim.api.nvim_create_autocmd("FileChangedShellPost", {
  group = vim.api.nvim_create_augroup("claude_sync_reload_notify", { clear = true }),
  pattern = "*",
  callback = function()
    vim.notify("File changed on disk. Buffer reloaded.", vim.log.levels.INFO)
  end,
})
