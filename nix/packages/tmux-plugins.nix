# The four TPM plugins under the directory names TPM derives from tmux/.tmux.conf's @plugin
# lines, so each entry can be linked into ~/.tmux/plugins and TPM sources it as it is.
{
  runCommand,
  tmuxPlugins,
  tpm,
}:
runCommand "dotfiles-tmux-plugins" { } ''
  mkdir -p $out
  ln -s ${tpm} $out/tpm
  ln -s ${tmuxPlugins.sensible}/share/tmux-plugins/sensible $out/tmux-sensible
  ln -s ${tmuxPlugins.resurrect}/share/tmux-plugins/resurrect $out/tmux-resurrect
  ln -s ${tmuxPlugins.continuum}/share/tmux-plugins/continuum $out/tmux-continuum
  # TPM runs each plugin's top-level *.tmux file; fail here if a layout ever moves.
  for p in tpm/tpm tmux-sensible/sensible.tmux tmux-resurrect/resurrect.tmux tmux-continuum/continuum.tmux; do
    [ -f "$out/$p" ] || { echo "missing $p" >&2; exit 1; }
  done
''
