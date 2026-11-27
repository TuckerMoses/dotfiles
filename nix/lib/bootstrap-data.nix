# What the checks read out of bootstrap.sh, parsed the way validate.sh parses it, so Nix and
# the Stow route can never disagree about it.
{ lib }:
let
  text = builtins.readFile ../../bootstrap.sh;
  lines = lib.splitString "\n" text;

  # The first `for pkg in a b c; do` line (validate.sh: sed ... | head -1).
  forPkgLine = lib.findFirst (l: builtins.match "for pkg in .*; do" l != null) (throw
    "bootstrap-data: no `for pkg in ...; do` line in bootstrap.sh"
  ) lines;
  forPkgs = lib.filter (s: s != "") (
    lib.splitString " " (lib.head (builtins.match "for pkg in (.*); do" forPkgLine))
  );

  # Every `--restow <name>` with a literal name (`--restow "$pkg"` does not match).
  restowPkgs = map lib.head (
    lib.filter lib.isList (builtins.split "--restow ([a-z][a-z0-9_-]*)" text)
  );
in
{
  # The Stow packages bootstrap.sh stows, sorted and without duplicates.
  stowPackages = lib.sort lib.lessThan (lib.unique (forPkgs ++ restowPkgs));

  # Files Home Manager itself adds to config.home.file, which belong to no Stow package; the
  # checks that compare placed files with Stow files leave these out, and only these.
  homeManagerTargets = [
    # Placed by every Home Manager configuration.
    ".cache/.keep"
    ".local/state/.keep"
    ".config/environment.d/10-home-manager.conf"
    ".config/systemd/user/tray.target"
    # fonts.fontconfig.enable, for the Nerd Font.
    ".config/fontconfig/conf.d/10-hm-fonts.conf"
    ".config/fontconfig/conf.d/10-hm-rendering.conf"
    ".config/fontconfig/conf.d/52-hm-default-fonts.conf"
  ];
}
