# nixpkgs' Oh My Zsh with the custom plugins zsh/.zshrc loads, linked as ~/.oh-my-zsh.
#
# No patch is needed for a read-only $ZSH: upstream oh-my-zsh.sh already moves ZSH_CACHE_DIR to
# ${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh when $ZSH/cache is not writable, and
# tools/check_for_upgrade.sh already skips the update check when $ZSH is not writable, not
# owned by the user, or not a git repository.
#
# Oh My Zsh loads custom/plugins/<name>/<name>.plugin.zsh, and .zshrc sources
# custom/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh itself.
{
  runCommand,
  oh-my-zsh,
  zsh-autosuggestions,
  zsh-fzf-tab,
  zsh-syntax-highlighting,
  zsh-vi-mode,
}:
runCommand "dotfiles-oh-my-zsh-bundle" { } ''
  cp -r ${oh-my-zsh}/share/oh-my-zsh $out
  chmod -R u+w $out
  plugins=$out/custom/plugins

  ln -s ${zsh-autosuggestions}/share/zsh/plugins/zsh-autosuggestions $plugins/zsh-autosuggestions
  ln -s ${zsh-fzf-tab}/share/fzf-tab $plugins/fzf-tab
  ln -s ${zsh-vi-mode}/share/zsh-vi-mode $plugins/zsh-vi-mode

  # nixpkgs ships zsh-syntax-highlighting without the .plugin.zsh entry Oh My Zsh looks for.
  mkdir $plugins/zsh-syntax-highlighting
  echo 'source ${zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' \
    > $plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh

  for p in zsh-autosuggestions fzf-tab zsh-vi-mode zsh-syntax-highlighting; do
    [ -f "$plugins/$p/$p.plugin.zsh" ] || { echo "missing $p/$p.plugin.zsh" >&2; exit 1; }
  done
''
