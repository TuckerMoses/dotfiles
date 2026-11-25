{
  description = "NixOS hosts for the dotfiles repo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, disko, ... }:
    let
      mkHost =
        name: system: host:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            disko.nixosModules.disko
            ./nixos/modules
            host
            # The rebuild tools need to know which entry below this machine is.
            { lifeline.flakeAttr = name; }
          ];
        };
    in
    {
      nixosConfigurations = {
        # The home PC.
        homepc = mkHost "homepc" "x86_64-linux" ./nixos/hosts/homepc;

        # QEMU guests that run the same modules, for testing off the real machine.
        vm-aarch64 = mkHost "vm-aarch64" "aarch64-linux" ./nixos/hosts/vm;
        vm-x86_64 = mkHost "vm-x86_64" "x86_64-linux" ./nixos/hosts/vm;
      };
    };
}
