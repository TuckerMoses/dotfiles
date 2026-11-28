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
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  link-modes = import ./link-modes.nix {
    inherit pkgs;
    inherit (inputs) home-manager nixpkgs;
    homeModule = self.homeManagerModules.default;
  };
  configs = import ./configs.nix { inherit pkgs checkLib; };
  zsh-interactive = import ./zsh-interactive.nix { inherit pkgs checkLib; };
  scripts = import ./scripts.nix { inherit pkgs checkLib; };
  herdr-headless = import ./herdr-headless.nix { inherit pkgs checkLib; };
  tool-versions = import ./tool-versions.nix {
    inherit pkgs;
    inherit (inputs) nixpkgs;
  };
}
# Left out on Darwin: lifeline-guard evaluates a NixOS host's lockout guard, and macOS has none.
// pkgs.lib.optionalAttrs isLinux {
  lifeline-guard = import ./lifeline-guard.nix { inherit pkgs self system; };
}
