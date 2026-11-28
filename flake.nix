{
  description = "highwind: the configs and tools of the owner's machines as a Nix package set, and NixOS hosts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Only for herdr and jujutsu (nix/overlay.nix), so one fast-moving tool never moves the
    # kernel or Tailscale.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      disko,
      ...
    }:
    let
      lib = nixpkgs.lib;

      # All three are built: the Linux pair in CI and on homepc, aarch64-darwin on CI's macOS
      # runner (.github/workflows/nix.yml, job darwin).
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f system);

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };

      mkHost =
        name: system: host:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            disko.nixosModules.disko
            ./nixos/modules
            host
            # The rebuild tools need to know which entry below this machine is.
            { lifeline.flakeAttr = name; }
          ];
        };

      mkHome = import ./nix/lib/home-configuration.nix { inherit self inputs; };
    in
    {
      # ── Package set ──────────────────────────────────────────────────────────
      overlays.default = import ./nix/overlay.nix inputs;

      packages = forAllSystems (
        system:
        let
          d = (pkgsFor system).highwind;
        in
        {
          inherit (d)
            home-tree
            scripts
            summarizer-plugin
            oh-my-zsh-bundle
            tools
            sandbox
            herdr-sandbox
            highwind-switch
            herdr-plugin-vim-herdr-navigation
            herdr-plugin-herdr-plus
            herdr-plugin-herdr-fingers
            herdr-plugins
            herdr-plugin-hashes
            ;
        }
      );

      # ── Home Manager module ──────────────────────────────────────────────────
      # Closed over self, so it takes its packages from self.packages (see the module).
      homeManagerModules.default = import ./nix/home-manager self;

      # ── Standalone Home Manager configurations ──────────────────────────────
      # One per user and machine, activated by that user with highwind-switch (no root, no
      # safe-switch). The NixOS option highwind.users is the other way in, for a machine that
      # switches system and user together; homepc uses this one.
      homeConfigurations = {
        "tucker@homepc" = mkHome "tucker" "x86_64-linux" (
          { pkgs, ... }:
          {
            highwind.linkMode = "store";
            highwind.profiles.personal.enable = true;
            # The login shell stays bash, so SSH never depends on .zshrc.
            highwind.interactiveShell = pkgs.zsh;
          }
        );
        # The vm-switch test's user: base profile only.
        "test@vm" = mkHome "test" "x86_64-linux" (
          { pkgs, ... }:
          {
            highwind.interactiveShell = pkgs.zsh;
          }
        );
        # The Mac (docs/mac-cutover.md). zsh is its login shell already, so no interactiveShell.
        # highwind-switch calls any Mac "mac", whatever its network name (highwind-switch.sh).
        "johnmoses@mac" = mkHome "johnmoses" "aarch64-darwin" {
          highwind.linkMode = "store";
          highwind.profiles.personal.enable = true;
        };
        # CI's macOS runner activates this one (its user is runner): base profile only.
        "runner@mac-ci" = mkHome "runner" "aarch64-darwin" { };
      };

      # ── Apps ─────────────────────────────────────────────────────────────────
      apps = forAllSystems (
        system:
        let
          app = pkg: {
            type = "app";
            program = lib.getExe pkg;
            meta.description = pkg.meta.description;
          };
        in
        {
          sandbox = app self.packages.${system}.sandbox;
          herdr-sandbox = app self.packages.${system}.herdr-sandbox;
          # The first switch on a machine, before highwind-switch is on PATH.
          highwind-switch = app self.packages.${system}.highwind-switch;
          # After a herdr plugin pin moved in bootstrap.sh: the hashes its build needs.
          herdr-plugin-hashes = app self.packages.${system}.herdr-plugin-hashes;
        }
      );

      # ── Checks ───────────────────────────────────────────────────────────────
      # Build-sandbox checks on every system (nix/checks/default.nix says which are left out on
      # Darwin, and why).
      checks = forAllSystems (
        system:
        let
          args = {
            inherit self inputs system;
            pkgs = pkgsFor system;
          };
        in
        import ./nix/checks args
        # The NixOS VM tests (names start with vm-) need KVM; CI has it on x86-64 only.
        // lib.optionalAttrs (system == "x86_64-linux") (import ./nix/tests args)
      );

      # ── NixOS hosts ──────────────────────────────────────────────────────────
      nixosConfigurations = {
        # The home PC.
        homepc = mkHost "homepc" "x86_64-linux" ./nixos/hosts/homepc;

        # QEMU guests that run the same modules, for testing off the real machine.
        vm-aarch64 = mkHost "vm-aarch64" "aarch64-linux" ./nixos/hosts/vm;
        vm-x86_64 = mkHost "vm-x86_64" "x86_64-linux" ./nixos/hosts/vm;
      };
    };
}
