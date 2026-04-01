-- ── Claude Code integration ──────────
-- WebSocket bridge between Claude Code and Neovim.
-- Claude Code sees your open buffers/selections; Neovim reloads on changes.

return {
  "coder/claudecode.nvim",
  config = true,
  keys = {
    { "<leader>cc", "<cmd>ClaudeCodeToggle<cr>", desc = "Toggle Claude Code" },
    { "<leader>cs", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send selection to Claude" },
  },
}
