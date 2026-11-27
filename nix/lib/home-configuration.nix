# A standalone Home Manager configuration for one user on one machine, with the dotfiles module
# on. The flake exports each as homeConfigurations."<user>@<host>", which dotfiles-switch builds
# and the user activates without root. `module` is any Home Manager module, for the machine's
# own settings. Linux homes only (/home/<user>).
{ self, inputs }:
user: system: module:
inputs.home-manager.lib.homeManagerConfiguration {
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  modules = [
    self.homeManagerModules.default
    {
      home.username = user;
      home.homeDirectory = "/home/${user}";
      home.stateVersion = "26.05";
      dotfiles.enable = true;
    }
    module
  ];
}
