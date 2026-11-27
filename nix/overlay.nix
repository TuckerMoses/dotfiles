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
    tpm = self.callPackage ./packages/tpm.nix { };

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
    tmux-plugins = self.callPackage ./packages/tmux-plugins.nix { };
    tools = self.callPackage ./packages/tools.nix { };
    sandbox = self.callPackage ./packages/sandbox.nix { };
    herdr-sandbox = self.callPackage ./packages/sandbox.nix { withHerdr = true; };
  });
}
