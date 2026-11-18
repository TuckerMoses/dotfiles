#!/usr/bin/env bash
set -euo pipefail

# ── Dotfiles bootstrap ──────────────────────────────────────────────────────
# Clone this repo to ~/dotfiles, then run: ./bootstrap.sh
# Idempotent — safe to re-run on updates.
#
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DOTFILES_DIR"

# ── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            sed -n '4,6p' "$0"
            exit 0 ;;
        *)
            echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

echo "==> Bootstrapping dotfiles from $DOTFILES_DIR"

# ── macOS: install Homebrew + packages ───────────────────────────────────────
if [[ "$(uname)" == "Darwin" ]]; then
  if ! command -v brew &>/dev/null; then
    echo "==> Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  echo "==> Installing brew packages..."
  # cmd:formula pairs (cmd=formula when they match)
  for pair in stow tmux neovim:nvim starship fzf zoxide atuin jq lazygit lazyjj; do
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
  for pair in stow tmux neovim:nvim fzf zoxide jq lazygit; do
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

[[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] ||
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

[[ -d "$ZSH_CUSTOM/plugins/fzf-tab" ]] ||
  git clone https://github.com/Aloxaf/fzf-tab "$ZSH_CUSTOM/plugins/fzf-tab"

[[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] ||
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

# herdr: --no-folding because ~/.config/herdr also holds sockets, logs and session state
# that must stay real files, so only the package's own files (config.toml, plugin configs) are linked.
if [[ -d "$DOTFILES_DIR/herdr" ]]; then
  echo "    stowing herdr (--no-folding)"
  mkdir -p "$HOME/.config/herdr"
  stow -d "$DOTFILES_DIR" -t "$HOME" --no-folding --restow herdr
fi

# ── Herdr plugins ────────────────────────────────────────────────────────────
# Every third-party plugin is pinned with --ref to a reviewed commit; these --ref lines are the
# only record of the pins. Move them with `herdr-plugins update` (herdr/.local/bin/herdr-plugins),
# which shows what changed in the install-time code first; `herdr plugin update` skips that review.
# --yes is deliberate: herdr's install prompt guards against unreviewed code, and --ref installs
# only the commit that was reviewed before it was pinned, so the pin is the review and bootstrap
# stays unattended (fresh machines, containers). Moving a pin is where the prompts are:
# `herdr-plugins update` asks before it edits a --ref and reinstalls without --yes. Never add
# --yes to an install without --ref.
# vim-herdr-navigation: ctrl+h/j/k/l across panes, vim-split-aware (needs jq)
if command -v herdr >/dev/null 2>&1; then
  if ! herdr plugin list 2>/dev/null | grep -q vim-herdr-navigation; then
    echo "==> Installing herdr plugin vim-herdr-navigation"
    herdr plugin install paulbkim-dev/vim-herdr-navigation --ref 7873100eb47212269005c693effb2a844986b30f --yes || echo "    (install failed: herdr server not running, or a build, toolchain or network error above; re-run ./bootstrap.sh)"
  fi
  # herdr-plus: project templates, worktree layouts and quick actions (prefix+t, prefix+space);
  # its config is stowed by the herdr package into ~/.config/herdr/plugins/config/cloudmanic.herdr-plus/
  # Needs Go: without it, its build step downloads the latest release binary instead of building the pin.
  if ! herdr plugin list 2>/dev/null | grep -q herdr-plus; then
    if command -v go >/dev/null 2>&1; then
      echo "==> Installing herdr plugin herdr-plus (go build)"
      herdr plugin install cloudmanic/herdr-plus --ref f38df3570bea8f7ca71dc1ba11bce3b123d14402 --yes || echo "    (install failed: herdr server not running, or a build, toolchain or network error above; re-run ./bootstrap.sh)"
    else echo "    (skipping herdr-plus: needs Go to build the pinned source, https://go.dev/dl)"; fi
  fi
  # herdr-reviewr: review an agent's diff, send line comments back (prefix+alt+r). Pinned to the
  # v0.52.2 tag commit. Its build step downloads that release's binary (checked only against the
  # release's own .sha256): the review covers the source and install script at the pin, and the
  # binary is trusted to the release, not verified. Bump with `herdr-plugins update`.
  if ! herdr plugin list 2>/dev/null | grep -q persiyanov.reviewr; then
    echo "==> Installing herdr plugin herdr-reviewr"
    herdr plugin install persiyanov/herdr-reviewr --ref bb71050caa5d3a0b1a414527783eb7a772447f9f --yes || echo "    (install failed: herdr server not running, or a build, toolchain or network error above; re-run ./bootstrap.sh)"
  fi
  # herdr-fingers (trial): hint-copy paths, SHAs, URLs from the focused pane (prefix+f). Pinned to a
  # reviewed commit; builds with cargo (Rust >= 1.85). Remove the trial: the targets listed in docs/plans/herdr-fingers-trial.md.
  if ! herdr plugin list 2>/dev/null | grep -q herdr-fingers; then
    if command -v cargo >/dev/null 2>&1; then
      echo "==> Installing herdr plugin herdr-fingers (cargo build, a minute or two)"
      herdr plugin install nathan-poncet/herdr-fingers --ref 2d9fc997ce1a95976b975da758dccc7b6e011336 --yes || echo "    (install failed: herdr server not running, or a build, toolchain or network error above; re-run ./bootstrap.sh)"
    else echo "    (skipping herdr-fingers: needs Rust/cargo, https://rustup.rs)"; fi
  fi
  # Claude Code integration: agent state + session refs via hook (re-run after herdr upgrades)
  if ! herdr integration status 2>/dev/null | grep -i "claude" | grep -qiv "not installed"; then
    echo "==> Installing herdr Claude integration"
    herdr integration install claude || echo "    (install later: herdr integration install claude)"
  fi
fi

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

# ── Claude Code notifications ───────────────────────────────────────────────
# Removed 2026-11-03: claude-notifications-go (banners + tmux click-to-focus) and game-sounds
# (notification-sounds pack) are replaced by Herdr's own toasts, prefix+o and [ui.sound] in
# herdr/.config/herdr/config.toml. The notification-sounds/ pack itself was removed 2026-11-12.

# ── Validate ─────────────────────────────────────────────────────────────────
# Read-only check that everything above is linked, installed and actually what
# each program loads. Problems are reported, never fixed here, and never fail
# the bootstrap: its own work is already done by this point.
echo ""
echo "==> Validating (./validate.sh for the full report)..."
if "$DOTFILES_DIR/validate.sh" -q; then
  echo "==> Done! Restart your terminal for changes to take effect."
else
  echo "==> Done, but validation found failures (listed above). Restart your terminal, fix them, then run ./validate.sh."
fi
