#!/usr/bin/env bash
set -euo pipefail

# ── Dotfiles bootstrap ──────────────────────────────────────────────────────
# Clone this repo to ~/dotfiles, then run: ./bootstrap.sh
# Idempotent — safe to re-run on updates.

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DOTFILES_DIR"

echo "==> Bootstrapping dotfiles from $DOTFILES_DIR"

# ── macOS: install Homebrew + packages ───────────────────────────────────────
if [[ "$(uname)" == "Darwin" ]]; then
    if ! command -v brew &>/dev/null; then
        echo "==> Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    echo "==> Installing brew packages..."
    brew install stow tmux neovim starship fzf zoxide
    brew install --cask font-jetbrains-mono-nerd-font
fi

# ── Linux: install packages ──────────────────────────────────────────────────
if [[ "$(uname)" == "Linux" ]]; then
    if command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y stow tmux neovim fzf zoxide
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y stow tmux neovim fzf zoxide
    fi

    # Starship (cross-platform installer)
    if ! command -v starship &>/dev/null; then
        curl -sS https://starship.rs/install.sh | sh
    fi
fi

# ── Oh My Zsh ────────────────────────────────────────────────────────────────
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    echo "==> Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# ── Zsh plugins ──────────────────────────────────────────────────────────────
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

[[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] || \
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

[[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] || \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# ── Stow packages ────────────────────────────────────────────────────────────
echo "==> Stowing dotfiles..."
mkdir -p "$HOME/.config"

for pkg in tmux zsh ghostty starship; do
    if [[ -d "$DOTFILES_DIR/$pkg" ]]; then
        echo "    stowing $pkg"
        stow -d "$DOTFILES_DIR" -t "$HOME" --restow "$pkg"
    fi
done

echo ""
echo "==> Done! Restart your terminal for changes to take effect."
