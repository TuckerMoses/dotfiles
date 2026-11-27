# Adds pkgs.dotfiles: the packages the dotfiles need (see docs/design/nix-dotfiles.md, section 4).
# Takes the flake inputs so two tools can come from nixpkgs-unstable.
inputs: final: prev:
let
  unstable = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system};
in
{
  dotfiles = prev.lib.makeScope final.newScope (self: {
    # ── Tools from nixpkgs-unstable ──────────────────────────────────────────
    # 26.05 has no herdr and only jujutsu 0.41.0; bootstrap.sh pins 0.47.1.
    herdr = unstable.herdr;
    jujutsu = unstable.jujutsu;

    # ── Tools from elsewhere ─────────────────────────────────────────────────
    tuicr = self.callPackage ./packages/tuicr.nix { };

    # bootstrap.sh alone, as the repo herdr-plugins reads its pins from when no checkout is given.
    bootstrap-dir = prev.lib.fileset.toSource {
      root = ../.;
      fileset = ../bootstrap.sh;
    };

    # ── The package set ──────────────────────────────────────────────────────
    home-tree = self.callPackage ./packages/home-tree.nix { };
    scripts = self.callPackage ./packages/scripts.nix { };
    summarizer-plugin = self.callPackage ./packages/summarizer-plugin.nix { };
    oh-my-zsh-bundle = self.callPackage ./packages/oh-my-zsh-bundle.nix { };
    tools = self.callPackage ./packages/tools.nix { };
    sandbox = self.callPackage ./packages/sandbox.nix { };
    herdr-sandbox = self.callPackage ./packages/sandbox.nix { withHerdr = true; };
    dotfiles-switch = self.callPackage ./packages/dotfiles-switch.nix { };

    # ── herdr's third-party plugins ──────────────────────────────────────────
    # Built at the pins bootstrap.sh writes (nix/packages/herdr-plugins/source.nix).
    herdr-plugin-vim-herdr-navigation = self.callPackage ./packages/herdr-plugins/vim-herdr-navigation.nix { };
    herdr-plugin-herdr-plus = self.callPackage ./packages/herdr-plugins/herdr-plus.nix { };
    herdr-plugin-herdr-fingers = self.callPackage ./packages/herdr-plugins/herdr-fingers.nix { };
    herdr-plugins = self.callPackage ./packages/herdr-plugins { };
    herdr-plugin-hashes = final.writeShellApplication {
      name = "herdr-plugin-hashes";
      # The caller's own nix, so the hashes come from the Nix that builds the plugins.
      runtimeInputs = [
        final.jq
        final.gnused
        final.gnugrep
        final.coreutils
      ];
      text = builtins.readFile ./packages/herdr-plugins/hashes.sh;
      meta.description = "Print nix/packages/herdr-plugins/hashes.nix for the pins in bootstrap.sh";
    };
  });
}
