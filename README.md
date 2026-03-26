# dotfiles

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## New machine setup

```bash
git clone git@github.com:YOUR_USERNAME/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

## Structure

Each top-level directory is a Stow package that mirrors `$HOME`:

```
dotfiles/
├── ghostty/.config/ghostty/config   → ~/.config/ghostty/config
├── tmux/.tmux.conf                  → ~/.tmux.conf
├── zsh/.zshrc                       → ~/.zshrc
├── starship/.config/starship.toml   → ~/.config/starship.toml  (coming soon)
├── bootstrap.sh                     — one-command setup
└── README.md
```

## Adding a new config

```bash
mkdir -p ~/dotfiles/tool/.config/tool
mv ~/.config/tool/config ~/dotfiles/tool/.config/tool/config
cd ~/dotfiles && stow tool
```
