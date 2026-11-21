#!/usr/bin/env bash
set -euo pipefail

# ── Dotfiles bootstrap ──────────────────────────────────────────────────────
# Clone this repo to ~/dotfiles, then run: ./bootstrap.sh
# Idempotent — safe to re-run on updates.
# Contract: "==> Installing" is printed whenever, and only when, something is installed (test/suite.sh's third run relies on it).
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

  echo "==> Checking brew packages..."
  # formula:cmd pairs (cmd=formula when they match)
  for pair in stow tmux neovim:nvim starship fzf zoxide atuin jq lazygit lazyjj; do
    formula="${pair%%:*}"
    cmd="${pair#*:}"
    command -v "$cmd" &>/dev/null || { echo "==> Installing $formula..."; brew install "$formula"; }
  done

  if ! brew list --cask font-jetbrains-mono-nerd-font &>/dev/null 2>&1; then
    echo "==> Installing JetBrains Mono Nerd Font..."
    brew install --cask font-jetbrains-mono-nerd-font
  fi
fi

# ── Linux: install packages ──────────────────────────────────────────────────
# System packages come from apt/dnf; user-level binaries go to ~/.local/bin
# (zsh/.zshrc puts it on PATH). Every download is picked by `uname -m`.
if [[ "$(uname)" == "Linux" ]]; then
  LOCAL_BIN="$HOME/.local/bin"
  mkdir -p "$LOCAL_BIN"
  [[ ":$PATH:" == *":$LOCAL_BIN:"* ]] || export PATH="$LOCAL_BIN:$PATH"
  arch="$(uname -m)"   # x86_64 | aarch64
  case "$arch" in x86_64|aarch64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; esac

  # pkg:cmd pairs (cmd=pkg when they match). jj and lazyjj are release binaries
  # (below), not packages; they are listed so validate.sh checks them too.
  # Ubuntu 26.04's neovim (0.11), fzf (0.67, has --zsh) and lazygit are new enough.
  missing=()
  for pair in stow tmux zsh git curl unzip fontconfig:fc-list wl-clipboard:wl-copy neovim:nvim fzf zoxide jq lazygit jj lazyjj; do
    cmd="${pair#*:}"
    command -v "$cmd" &>/dev/null && continue
    case "$cmd" in jj|lazyjj) ;; *) missing+=("${pair%%:*}") ;; esac   # same list as test/suite.sh env_local
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "==> Installing packages: ${missing[*]}"
    if command -v apt-get &>/dev/null; then
      apt_get() { sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o Acquire::Retries=5 "$@"; }
      apt_get update -qq
      apt_get install -y -qq --no-install-recommends "${missing[@]}"
    elif command -v dnf &>/dev/null; then
      sudo dnf install -y "${missing[@]}"
    fi
  fi

  # fetch <curl args>: a download that gives up on a dead connection (under 1 KB/s for a
  # minute) and retries, where plain curl would wait on it forever.
  fetch() { curl -fsSL --retry 5 --connect-timeout 20 --speed-limit 1024 --speed-time 60 "$@"; }

  # release_bin <cmd> <url> <sha256|-> <path-in-tarball>: one binary from a .tar.gz
  # (`-` skips the checksum: used where the URL is `latest` and the asset changes)
  release_bin() {
    local cmd="$1" url="$2" sum="$3" member="$4" tmp
    command -v "$cmd" &>/dev/null && return 0
    echo "==> Installing $cmd..."
    tmp="$(mktemp -d)"
    fetch -o "$tmp/a.tgz" "$url"
    if [[ "$sum" != "-" ]] && [[ "$(sha256sum "$tmp/a.tgz" | awk '{print $1}')" != "$sum" ]]; then
      echo "    $cmd: checksum mismatch for $url" >&2; rm -rf "$tmp"; return 1
    fi
    tar -xzf "$tmp/a.tgz" -C "$tmp" "$member"
    install -m 755 "$tmp/$member" "$LOCAL_BIN/$cmd"
    rm -rf "$tmp"
  }

  # jj, and lazyjj for it. lazyjj 0.6 publishes no binaries; 0.5.0 is the newest
  # prebuilt one (cargo-quickinstall, static musl), pinned by checksum. It works
  # with current jj.
  if [[ "$arch" == x86_64 ]]; then
    jj_sum=d4b657f622ee50929c8916466dfa3d6a6c17a0a32b50e7b2c793707ec9ebcad7
    lazyjj_sum=19cb8ae9a416708cb69ebfb6e513a4f49378a303bf8c4d32427e099fe15121ea
  else
    jj_sum=0f300e1576de8dabe0a9dedf0b87ae44f8accea5cf54d9a342a51061c1fb1bcd
    lazyjj_sum=56efa62b2a925d3127479d264443b152914badba707f3c694d4ef57be4c2369d
  fi
  release_bin jj "https://github.com/jj-vcs/jj/releases/download/v0.47.1/jj-v0.47.1-$arch-unknown-linux-musl.tar.gz" "$jj_sum" ./jj
  release_bin lazyjj "https://github.com/cargo-bins/cargo-quickinstall/releases/download/lazyjj-0.5.0/lazyjj-0.5.0-$arch-unknown-linux-musl.tar.gz" "$lazyjj_sum" lazyjj

  # Atuin (shell history): the release binary. Its setup script would edit ~/.zshrc,
  # which is the stowed repo file.
  release_bin atuin "https://github.com/atuinsh/atuin/releases/latest/download/atuin-$arch-unknown-linux-gnu.tar.gz" - "atuin-$arch-unknown-linux-gnu/atuin"

  # Starship (cross-platform installer; -y: no prompt, -b: no sudo)
  if ! command -v starship &>/dev/null; then
    echo "==> Installing starship..."
    fetch https://starship.rs/install.sh | sh -s -- -y -b "$LOCAL_BIN" >/dev/null
  fi

  # Herdr (its installer verifies the release checksum)
  if ! command -v herdr &>/dev/null; then
    echo "==> Installing herdr..."
    fetch https://herdr.dev/install.sh | HERDR_INSTALL_DIR="$LOCAL_BIN" sh >/dev/null
  fi

  # JetBrains Mono Nerd Font (macOS gets the brew cask)
  # (captured, not piped to grep -q: under pipefail an early grep exit fails the pipe)
  if [[ "$(fc-list : family 2>/dev/null)" != *"JetBrainsMono Nerd Font"* ]]; then
    echo "==> Installing JetBrains Mono Nerd Font..."
    font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
    mkdir -p "$font_dir"
    tmp="$(mktemp -d)"
    fetch -o "$tmp/f.zip" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
    unzip -oq "$tmp/f.zip" '*.ttf' -d "$font_dir"
    rm -rf "$tmp"
    fc-cache -f "$font_dir" >/dev/null
  fi

  if [[ "$(basename "${SHELL:-}")" != "zsh" ]]; then
    echo "==> Login shell is ${SHELL:-unset}; to use zsh: chsh -s \"$(command -v zsh)\""
  fi
fi

# ── Oh My Zsh ────────────────────────────────────────────────────────────────
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  echo "==> Installing Oh My Zsh..."
  # On a machine with no ~/.zshrc the installer writes its template there, which
  # would block stowing ours; drop it (an existing ~/.zshrc is kept as it was).
  had_zshrc=0; [[ -e "$HOME/.zshrc" || -L "$HOME/.zshrc" ]] && had_zshrc=1
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
  (( had_zshrc )) || [[ -L "$HOME/.zshrc" ]] || rm -f "$HOME/.zshrc"
fi

# ── Zsh plugins ──────────────────────────────────────────────────────────────
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

[[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] ||
  { echo "==> Installing zsh-autosuggestions..."; git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"; }

[[ -d "$ZSH_CUSTOM/plugins/fzf-tab" ]] ||
  { echo "==> Installing fzf-tab..."; git clone https://github.com/Aloxaf/fzf-tab "$ZSH_CUSTOM/plugins/fzf-tab"; }

[[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] ||
  { echo "==> Installing zsh-syntax-highlighting..."; git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"; }

# zsh-vi-mode: .zshrc uses brew's copy when brew has one, else this one.
zvm_brew=""
command -v brew &>/dev/null && zvm_brew="$(brew --prefix)/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh"
[[ -n "$zvm_brew" && -f "$zvm_brew" ]] || [[ -d "$ZSH_CUSTOM/plugins/zsh-vi-mode" ]] ||
  { echo "==> Installing zsh-vi-mode..."; git clone https://github.com/jeffreytse/zsh-vi-mode "$ZSH_CUSTOM/plugins/zsh-vi-mode"; }

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
# that must stay real files, so only config.toml is linked.
if [[ -d "$DOTFILES_DIR/herdr" ]]; then
  echo "    stowing herdr (--no-folding)"
  mkdir -p "$HOME/.config/herdr"
  stow -d "$DOTFILES_DIR" -t "$HOME" --no-folding --restow herdr
fi

# ── Herdr plugins ────────────────────────────────────────────────────────────
# vim-herdr-navigation: ctrl+h/j/k/l across panes, vim-split-aware (needs jq)
# The list is read once into a variable: piping it straight into grep -q fails the
# check under pipefail whenever grep exits before herdr finishes writing (SIGPIPE),
# which reinstalled plugins that were already there.
if command -v herdr >/dev/null 2>&1; then
  herdr_plugins="$(herdr plugin list 2>/dev/null || true)"
  if ! grep -q vim-herdr-navigation <<<"$herdr_plugins"; then
    echo "==> Installing herdr plugin vim-herdr-navigation"
    herdr plugin install paulbkim-dev/vim-herdr-navigation --yes || echo "    (herdr server not running; install later)"
  fi
  # herdr-plus: per-worktree layouts and quick actions
  if ! grep -q herdr-plus <<<"$herdr_plugins"; then
    echo "==> Installing herdr plugin herdr-plus"
    herdr plugin install cloudmanic/herdr-plus --yes || echo "    (herdr server not running; install later)"
  fi
  # Claude Code integration: agent state + session refs via hook (re-run after herdr upgrades).
  # It installs into ~/.claude, so it waits until Claude Code has been set up.
  if [[ ! -d "$HOME/.claude" ]]; then
    echo "    (herdr Claude integration: install Claude Code, then re-run ./bootstrap.sh)"
  elif ! herdr integration status 2>/dev/null | grep -i "claude" | grep -qiv "not installed"; then
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
  echo "==> Syncing tmux plugins (TPM)..."
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
