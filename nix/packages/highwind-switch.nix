# highwind-switch (highwind-switch.sh): builds and activates the calling user's standalone Home
# Manager configuration. nix and nix-env come from the user's PATH, as Home Manager's own
# driver takes them, so the machine's Nix does the building.
{
  writeShellApplication,
  coreutils,
  diffutils,
  findutils,
  gnused,
}:
writeShellApplication {
  name = "highwind-switch";
  runtimeInputs = [
    coreutils
    diffutils
    findutils
    gnused
  ];
  # Prefixed, not replaced: nix comes from the user's PATH.
  inheritPath = true;
  text = builtins.readFile ./highwind-switch.sh;
  meta.description = "Build and activate this user's highwind Home Manager configuration";
}
