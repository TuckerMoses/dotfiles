# The build-sandbox checks: no network, no real HOME. One file each.
# CI builds every name here by attribute, so adding a file and a line is all a new check needs.
{
  self,
  inputs,
  system,
  pkgs,
}:
let
  checkLib = import ./lib.nix { inherit pkgs; };
in
{
  link-modes = import ./link-modes.nix {
    inherit pkgs;
    inherit (inputs) home-manager nixpkgs;
    homeModule = self.homeManagerModules.default;
  };
  configs = import ./configs.nix { inherit pkgs checkLib; };
  zsh-interactive = import ./zsh-interactive.nix { inherit checkLib; };
  scripts = import ./scripts.nix { inherit pkgs checkLib; };
  herdr-headless = import ./herdr-headless.nix { inherit checkLib; };
  tool-versions = import ./tool-versions.nix {
    inherit pkgs;
    inherit (inputs) nixpkgs;
  };
  lifeline-guard = import ./lifeline-guard.nix { inherit pkgs self system; };
}
