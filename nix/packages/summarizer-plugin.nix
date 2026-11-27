# herdr-summarizer/plugin with its hook calling the packaged herdr-summarize. The repo's hook
# finds the script through the checkout, which a store copy does not have.
{
  lib,
  runCommand,
  runtimeShell,
  scripts,
}:
let
  src = lib.fileset.toSource {
    root = ../../herdr-summarizer/plugin;
    fileset = ../../herdr-summarizer/plugin;
  };
in
runCommand "dotfiles-summarizer-plugin" { } ''
  mkdir -p $out
  cp -r ${src}/. $out/
  chmod -R u+w $out
  cat > $out/hook <<EOF
  #!${runtimeShell}
  # herdr runs this from the plugin root on each subscribed event.
  exec ${scripts}/bin/herdr-summarize event
  EOF
  chmod 755 $out/hook
''
