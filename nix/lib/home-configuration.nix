# A standalone Home Manager configuration for one user on one machine, with the highwind module
# on. The flake exports each as homeConfigurations."<user>@<host>", which highwind-switch builds
# and the user activates without root. `module` is any Home Manager module, for the machine's
# own settings. The home directory comes from the user name and the system (home-directory.nix).
{ self, inputs }:
user: system: module:
inputs.home-manager.lib.homeManagerConfiguration {
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  modules = [
    self.homeManagerModules.default
    {
      home.username = user;
      home.homeDirectory = import ./home-directory.nix { inherit (inputs.nixpkgs) lib; } system user;
      home.stateVersion = "26.05";
      highwind.enable = true;
    }
    module
  ];
}
