# The build-sandbox checks: no network, no real HOME. One file each.
# CI builds every name here by attribute, so adding a file and a line is all a new check needs.
{
  self,
  inputs,
  system,
  pkgs,
}:
{
  link-modes = import ./link-modes.nix {
    inherit pkgs;
    inherit (inputs) home-manager nixpkgs;
    homeModule = self.homeManagerModules.default;
  };
}
