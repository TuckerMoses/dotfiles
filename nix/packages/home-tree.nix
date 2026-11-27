# A store directory laid out like $HOME: the union of the Stow packages, minus the scripts
# (packaged with rewritten interpreters in scripts.nix). Only these directories are in the
# source, so an edit elsewhere in the repo does not rebuild it.
{ lib, runCommand }:
let
  fs = lib.fileset;
  root = ../..;
  stowPackages = [
    "atuin"
    "ghostty"
    "herdr"
    "nvim"
    "starship"
    "tmux"
    "zsh"
  ];
  fileset = fs.difference (fs.unions (map (p: root + "/${p}") stowPackages)) (
    root + "/herdr/.local/bin"
  );
  src = fs.toSource { inherit root fileset; };
  # Each file as { pkg; rel; }, rel being its path under $HOME, for the Home Manager module to
  # link one by one. passthru only, so the build itself is unchanged.
  files = lib.concatMap (
    p:
    map (f: {
      pkg = p;
      rel = lib.removePrefix "./" (lib.path.removePrefix (root + "/${p}") f);
    }) (fs.toList (fs.intersection fileset (root + "/${p}")))
  ) stowPackages;
in
runCommand "dotfiles-home-tree" { passthru = { inherit stowPackages files; }; } ''
  mkdir -p $out
  for p in ${lib.escapeShellArgs stowPackages}; do
    # "dir/." copies the dotfiles too.
    cp -r ${src}/$p/. $out/
    chmod -R u+w $out
  done
  # Two packages placing the same file would mean one silently wins.
  want=$(cd ${src} && find ${lib.escapeShellArgs stowPackages} -type f | wc -l)
  got=$(find $out -type f | wc -l)
  [ "$want" -eq "$got" ] || { echo "home-tree: $want files in, $got out (a path collides)" >&2; exit 1; }
''
