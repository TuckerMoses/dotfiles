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
    "zsh"
  ];
  fileset = fs.difference (fs.unions (map (p: root + "/${p}") stowPackages)) (
    root + "/herdr/.local/bin"
  );
  src = fs.toSource { inherit root fileset; };

  # ── Profiles ─────────────────────────────────────────────────────────────
  # "personal" is what names the owner's own directories or repos; "base" is everything else
  # and is all a configuration gets unless it turns personal on. The Stow route places both.
  # herdr-plus project and worktree entries are personal by directory, so a new one is too.
  herdrPlus = ".config/herdr/plugins/config/cloudmanic.herdr-plus";
  personal = {
    dirs = [
      "${herdrPlus}/projects/"
      "${herdrPlus}/worktrees/"
    ];
    files = [
      # Runs $HOME/dotfiles/validate.sh.
      "${herdrPlus}/quick-actions/validate-highwind.toml"
    ];
    # What a base file must not contain outside a comment (link-modes checks it): one of the
    # owner's directories, or a herdr-plus project or worktree entry. ERE, for grep -E.
    pattern = ''(~|\$HOME|\$\{HOME\})/(aios|Vault|claude-materia|dotfiles)([^[:alnum:]_-]|$)|^[[:space:]]*(working_dir|repo)[[:space:]]*='';
  };
  profileOf =
    rel: if lib.elem rel personal.files || lib.any (d: lib.hasPrefix d rel) personal.dirs then "personal" else "base";

  # Each file as { pkg; rel; profile; }, rel being its path under $HOME, for the Home Manager
  # module to link one by one. passthru only, so the build itself is unchanged.
  files = lib.concatMap (
    p:
    map (
      f:
      let
        rel = lib.removePrefix "./" (lib.path.removePrefix (root + "/${p}") f);
      in
      {
        pkg = p;
        inherit rel;
        profile = profileOf rel;
      }
    ) (fs.toList (fs.intersection fileset (root + "/${p}")))
  ) stowPackages;
in
runCommand "highwind-home-tree" { passthru = { inherit stowPackages files personal; }; } ''
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
