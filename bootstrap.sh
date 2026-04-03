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
    # cmd:formula pairs (cmd=formula when they match)
    for pair in stow tmux neovim:nvim starship fzf zoxide atuin; do
        formula="${pair%%:*}"
        cmd="${pair#*:}"
        command -v "$cmd" &>/dev/null || brew install "$formula"
    done

    if ! brew list --cask font-jetbrains-mono-nerd-font &>/dev/null 2>&1; then
        brew install --cask font-jetbrains-mono-nerd-font
    fi
fi

# ── Linux: install packages ──────────────────────────────────────────────────
if [[ "$(uname)" == "Linux" ]]; then
    missing=()
    for pair in stow tmux neovim:nvim fzf zoxide; do
        cmd="${pair#*:}"
        command -v "$cmd" &>/dev/null || missing+=("${pair%%:*}")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        if command -v apt &>/dev/null; then
            sudo apt update && sudo apt install -y "${missing[@]}"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y "${missing[@]}"
        fi
    fi

    # Starship (cross-platform installer)
    if ! command -v starship &>/dev/null; then
        curl -sS https://starship.rs/install.sh | sh
    fi

    # Atuin (shell history)
    if ! command -v atuin &>/dev/null; then
        echo "==> Installing atuin..."
        curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
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

[[ -d "$ZSH_CUSTOM/plugins/fzf-tab" ]] || \
    git clone https://github.com/Aloxaf/fzf-tab "$ZSH_CUSTOM/plugins/fzf-tab"

[[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] || \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# ── Stow packages ────────────────────────────────────────────────────────────
echo "==> Stowing dotfiles..."
mkdir -p "$HOME/.config"

for pkg in tmux zsh ghostty starship nvim atuin; do
    if [[ -d "$DOTFILES_DIR/$pkg" ]]; then
        echo "    stowing $pkg"
        stow -d "$DOTFILES_DIR" -t "$HOME" --restow "$pkg"
    fi
done

# ── TPM (Tmux Plugin Manager) ───────────────────────────────────────────────
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [[ ! -d "$TPM_DIR" ]]; then
    echo "==> Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi

# Install/update TPM plugins (non-interactive equivalent of prefix + I)
if [[ -x "$TPM_DIR/bin/install_plugins" ]]; then
    echo "==> Installing tmux plugins..."
    "$TPM_DIR/bin/install_plugins"
fi

# ── Reload tmux config (if server is running) ───────────────────────────────
if command -v tmux &>/dev/null && tmux list-sessions &>/dev/null 2>&1; then
    echo "==> Reloading tmux config..."
    tmux source-file ~/.tmux.conf || true
fi

if command -v atuin &>/dev/null; then
    echo "==> Tip: Run 'atuin import auto' to import your existing shell history"
fi

# ── Claude Code plugins (macOS only) ────────────────────────────────────────
if command -v claude &>/dev/null; then
    echo "==> Setting up Claude Code plugins..."

    # Add marketplaces
    claude plugin marketplace add 777genius/claude-notifications-go 2>/dev/null || true
    claude plugin marketplace add Citedy/game-sounds 2>/dev/null || true

    # Install plugins
    claude plugin install claude-notifications-go@claude-notifications-go 2>/dev/null || true
    claude plugin install game-sounds@game-sounds 2>/dev/null || true

    # claude-notifications-go: write config (desktop banners + click-to-focus, sounds off)
    NOTIFY_CONFIG_DIR="$HOME/.claude/claude-notifications-go"
    mkdir -p "$NOTIFY_CONFIG_DIR"
    if [[ ! -f "$NOTIFY_CONFIG_DIR/config.json" ]]; then
        echo "    writing claude-notifications-go config"
        cat > "$NOTIFY_CONFIG_DIR/config.json" << 'EOF'
{
  "notifications": {
    "desktop": {
      "enabled": true,
      "sound": false,
      "volume": 1.0,
      "appIcon": "${CLAUDE_PLUGIN_ROOT}/claude_icon.png",
      "clickToFocus": true,
      "terminalBundleId": ""
    },
    "webhook": {
      "enabled": false,
      "preset": "custom",
      "url": "",
      "chat_id": "",
      "format": "json",
      "headers": {}
    },
    "suppressQuestionAfterTaskCompleteSeconds": 12,
    "suppressQuestionAfterAnyNotificationSeconds": 7,
    "suppressForSubagents": true,
    "suppressFilters": []
  },
  "statuses": {
    "task_complete": { "title": "✅ Completed", "sound": "" },
    "review_complete": { "title": "🔍 Review", "sound": "" },
    "question": { "title": "❓ Question", "sound": "" },
    "plan_ready": { "title": "📋 Plan", "sound": "" },
    "session_limit_reached": { "title": "⏱️ Session Limit Reached", "sound": "" },
    "api_error": { "title": "🔴 API Error", "sound": "" },
    "api_error_overloaded": { "title": "🔴 API Error", "sound": "" }
  }
}
EOF
    fi

    # game-sounds: symlink custom sound pack into plugin
    GS_SOUNDS_DIR=$(find "$HOME/.claude/plugins/cache/citedy/game-sounds" -maxdepth 2 -type d -name "sounds" 2>/dev/null | head -1)
    if [[ -n "$GS_SOUNDS_DIR" ]] && [[ -d "$DOTFILES_DIR/notification-sounds" ]]; then
        echo "    linking custom notification sound pack"
        ln -sfn "$DOTFILES_DIR/notification-sounds" "$GS_SOUNDS_DIR/custom"
    fi

    # game-sounds: set custom pack as active
    GS_CONFIG=$(find "$HOME/.claude/plugins/cache/citedy/game-sounds" -maxdepth 2 -name "config.json" 2>/dev/null | head -1)
    if [[ -n "$GS_CONFIG" ]]; then
        python3 -c "
import json
with open('$GS_CONFIG') as f:
    c = json.load(f)
c['active_pack'] = 'custom'
with open('$GS_CONFIG', 'w') as f:
    json.dump(c, f, indent=2)
    f.write('\n')
" 2>/dev/null || true
    fi
fi

echo ""
echo "==> Done! Restart your terminal for changes to take effect."
