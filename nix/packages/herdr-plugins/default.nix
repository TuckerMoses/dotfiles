# The three herdr plugins bootstrap.sh pins, one directory each named by plugin id, for the Home
# Manager module and the sandboxes to place and `herdr plugin link`. `plugins` maps each id to
# its package.
{
  lib,
  linkFarm,
  herdr-plugin-vim-herdr-navigation,
  herdr-plugin-herdr-plus,
  herdr-plugin-herdr-fingers,
}:
let
  plugins = lib.listToAttrs (
    map (p: lib.nameValuePair p.pluginId p) [
      herdr-plugin-vim-herdr-navigation
      herdr-plugin-herdr-plus
      herdr-plugin-herdr-fingers
    ]
  );
in
(linkFarm "highwind-herdr-plugins" plugins) // { inherit plugins; }
