-- ── Herdr: ctrl+h/j/k/l across nvim splits AND herdr panes ──────────────────
-- Loads the editor half of the vim-herdr-navigation plugin (installed by
-- `herdr plugin install paulbkim-dev/vim-herdr-navigation`). It owns <C-h/j/k/l>:
-- wincmd first, then crosses into herdr at an edge; falls back to
-- TmuxNavigate* when running under tmux instead of herdr.
-- vim-tmux-navigator's own maps are disabled in plugins/tmux.lua so these win.
return {
  {
    "LazyVim/LazyVim",
    init = function()
      local matches = vim.fn.glob(
        vim.fn.expand("~/.config/herdr/plugins/github/vim-herdr-navigation-*/editor/nvim.lua"),
        false, true
      )
      if #matches > 0 then
        dofile(matches[1])
      else
        -- plugin not installed: keep vim-tmux-navigator's mappings
        vim.g.tmux_navigator_no_mappings = 0
      end
    end,
  },
}
