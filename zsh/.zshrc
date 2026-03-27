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

# ── Conda ────────────────────────────────────────────────────────────────────
__conda_setup="$('$HOME/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="$HOME/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup

# ── NVM ──────────────────────────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# ── Language paths ───────────────────────────────────────────────────────────
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
eval $(opam env)
PATH="$HOME/perl5/bin${PATH:+:${PATH}}"; export PATH;
PERL5LIB="$HOME/perl5/lib/perl5${PERL5LIB:+:${PERL5LIB}}"; export PERL5LIB;
PERL_LOCAL_LIB_ROOT="$HOME/perl5${PERL_LOCAL_LIB_ROOT:+:${PERL_LOCAL_LIB_ROOT}}"; export PERL_LOCAL_LIB_ROOT;
PERL_MB_OPT="--install_base \"$HOME/perl5\""; export PERL_MB_OPT;
PERL_MM_OPT="INSTALL_BASE=$HOME/perl5"; export PERL_MM_OPT;
export PATH="$HOME/.local/bin:$PATH"

# ── Aliases ──────────────────────────────────────────────────────────────────
alias vim='nvim'
alias v='vim .'

# ── zoxide (smarter cd) — must be last ──────────────────────────────────────
eval "$(zoxide init zsh --cmd cd)"
