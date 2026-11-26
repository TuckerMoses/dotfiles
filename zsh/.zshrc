# ── PATH ─────────────────────────────────────────────────────────────────────
# user-level installs (bootstrap puts the Linux tools in ~/.local/bin)
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"

# ── Oh My Zsh ────────────────────────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""  # disabled — using Starship instead
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
plugins=(git wd fzf-tab zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

# ── zsh-vi-mode (must be after oh-my-zsh, before fzf) ────────────────────────
# brew's copy when brew has it (macOS), else the Oh My Zsh custom plugin (Linux)
if (( $+commands[brew] )) && [[ -f "$(brew --prefix)/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh" ]]; then
  source "$(brew --prefix)/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh"
elif [[ -f "${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh" ]]; then
  source "${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh"
fi

# ── Starship prompt ──────────────────────────────────────────────────────────
eval "$(starship init zsh)"

# ── fzf (fuzzy finder) & atuin (shell history) ──────────────────────────────
# zsh-vi-mode overrides keybindings, so these must be re-sourced in its callback
function zvm_after_init() {
  source <(fzf --zsh)
  command -v atuin &>/dev/null && eval "$(atuin init zsh)"
}

# ── Local overrides (machine-specific paths, tools, aliases) ────────────────
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# ── Aliases ──────────────────────────────────────────────────────────────────
alias vim='nvim'
alias v='vim .'
[[ "$OSTYPE" == darwin* ]] && alias claude-jobs="launchctl list | awk 'NR==1 || /com\\.tuckermoses\\./'"  # launchd jobs Claude registered

# ── zoxide (smarter cd) — must be last ──────────────────────────────────────
export _ZO_DOCTOR=0  # suppress false positive in non-interactive shells (e.g. Claude Code)
eval "$(zoxide init zsh --cmd cd)"
