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
  src = fs.toSource {
    inherit root;
    fileset = fs.difference (fs.unions (map (p: root + "/${p}") stowPackages)) (
      root + "/herdr/.local/bin"
    );
  };
in
runCommand "dotfiles-home-tree" { } ''
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
