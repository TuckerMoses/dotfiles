# The NixOS VM tests: whole machines under QEMU, for what needs one (a login over SSH, Home
# Manager activating at boot). Every name starts with vm-; CI selects them by that prefix.
{
  self,
  inputs,
  system,
  pkgs,
}:
{
  vm-home = import ./home.nix { inherit self inputs pkgs; };
  vm-lifeline = import ./lifeline.nix { inherit pkgs; };
}
