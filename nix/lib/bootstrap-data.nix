# What Nix reads out of bootstrap.sh, parsed the way validate.sh and herdr-plugins parse it, so
# Nix and the Stow route can never disagree about it.
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

  # ── tuicr ────────────────────────────────────────────────────────────────
  # The version from its `release_bin tuicr ".../download/v<version>/..."` line.
  tuicrVersions = map lib.head (
    lib.filter lib.isList (
      builtins.split "release_bin tuicr \"https://github.com/agavra/tuicr/releases/download/v([0-9.]+)/" text
    )
  );
  # The two `tuicr_sum=` lines sit in `if [[ "$arch" == x86_64 ]]; then ... else ... fi`: the
  # first is x86_64's, the second aarch64's. Each line is matched with the line before the
  # block's branch it is in, so a reordered block fails here instead of swapping the sums.
  sumLines = lib.filter (l: builtins.match " *tuicr_sum=[0-9a-f]{64}" l != null) lines;
  sumOf = l: lib.head (builtins.match " *tuicr_sum=([0-9a-f]{64})" l);
  indexOf = l: lib.lists.findFirstIndex (x: x == l) null lines;
  branchBefore =
    l:
    lib.findFirst (
      x: builtins.match " *if \\[\\[ \"\\$arch\" == x86_64 ]]; then" x != null || builtins.match " *else" x != null
    ) null (lib.reverseList (lib.take (indexOf l) lines));
  tuicr =
    assert lib.assertMsg (lib.length tuicrVersions == 1)
      "bootstrap-data: expected one `release_bin tuicr` line in bootstrap.sh, found ${toString (lib.length tuicrVersions)}";
    assert lib.assertMsg (lib.length sumLines == 2)
      "bootstrap-data: expected two `tuicr_sum=` lines in bootstrap.sh, found ${toString (lib.length sumLines)}";
    assert lib.assertMsg (
      builtins.match " *if.*x86_64.*" (toString (branchBefore (lib.elemAt sumLines 0))) != null
      && builtins.match " *else" (toString (branchBefore (lib.elemAt sumLines 1))) != null
    ) "bootstrap-data: the tuicr_sum lines are not in the x86_64 branch and the else branch, in that order";
    {
      version = lib.head tuicrVersions;
      sha256 = {
        x86_64-linux = sumOf (lib.elemAt sumLines 0);
        aarch64-linux = sumOf (lib.elemAt sumLines 1);
      };
    };

  # ── herdr plugins ────────────────────────────────────────────────────────
  # Each `herdr plugin install <owner/repo> --ref <sha>` line, read as herdr-plugins' pins() reads
  # it. Every install line must carry a pin, as herdr-plugins sync requires.
  installLines = lib.filter (l: builtins.match "[[:space:]]*herdr plugin install .*" l != null) lines;
  pinOf =
    l:
    let
      m = builtins.match "[[:space:]]*herdr plugin install ([^ ]*) --ref ([0-9a-f]{7,40})( .*)?" l;
    in
    if m == null then
      throw "bootstrap-data: a herdr plugin install line in bootstrap.sh has no --ref pin: ${l}"
    else
      {
        repo = lib.elemAt m 0;
        rev = lib.elemAt m 1;
      };
  herdrPlugins =
    assert lib.assertMsg (installLines != [ ]) "bootstrap-data: no herdr plugin install line in bootstrap.sh";
    map pinOf installLines;
in
{
  # The Stow packages bootstrap.sh stows, sorted and without duplicates.
  stowPackages = lib.sort lib.lessThan (lib.unique (forPkgs ++ restowPkgs));

  # The tuicr release bootstrap.sh pins: { version; sha256.<system>; }.
  inherit tuicr;

  # The herdr plugin pins, in bootstrap.sh's order: [ { repo = "<owner/repo>"; rev; } ].
  # Unlike the other values here, the plugin packages read these (nix/packages/herdr-plugins),
  # so a pin moved in bootstrap.sh moves the build too.
  inherit herdrPlugins;

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
    # On Darwin, the marker of the fonts Home Manager copies into ~/Library/Fonts/HomeManager.
    "Library/Fonts/.home-manager-fonts-version"
  ];
}
