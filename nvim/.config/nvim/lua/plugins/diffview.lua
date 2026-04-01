-- ── Diff review ──────────
-- Side-by-side diffs for reviewing changes from Claude Code or any external tool.
-- <leader>gd = unstaged changes, <leader>gc = last commit, <leader>gh = file history

return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewFileHistory" },
  keys = {
    { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Review unstaged changes" },
    { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File git history" },
    { "<leader>gc", "<cmd>DiffviewOpen HEAD~1<cr>", desc = "Review last commit" },
  },
}
