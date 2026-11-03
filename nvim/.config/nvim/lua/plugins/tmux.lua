return {
  -- Seamless navigation between nvim splits and tmux panes with Ctrl+h/j/k/l
  {
    "christoomey/vim-tmux-navigator",
    -- Mappings are owned by plugins/herdr.lua (vim-herdr-navigation), which calls
    -- TmuxNavigate* itself when under tmux; keep only the commands here.
    init = function()
      vim.g.tmux_navigator_no_mappings = 1
    end,
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
    },
  },
}
