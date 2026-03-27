# ── Oh My Zsh ────────────────────────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""  # disabled — using Starship instead
plugins=(git wd zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

# ── zsh-vi-mode (must be after oh-my-zsh, before fzf) ────────────────────────
source $(brew --prefix)/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh

# ── Starship prompt ──────────────────────────────────────────────────────────
eval "$(starship init zsh)"

# ── fzf (fuzzy finder) ──────────────────────────────────────────────────────
# zsh-vi-mode overrides keybindings, so fzf must be re-sourced in its callback
function zvm_after_init() {
  source <(fzf --zsh)
}

# ── Local overrides (machine-specific paths, tools, aliases) ────────────────
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# ── Aliases ──────────────────────────────────────────────────────────────────
alias vim='nvim'
alias v='vim .'

# ── zoxide (smarter cd) — must be last ──────────────────────────────────────
eval "$(zoxide init zsh --cmd cd)"
