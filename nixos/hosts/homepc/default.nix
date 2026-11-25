# ── homepc ────────────────────────────────────────────────────────────
# The home PC: Ryzen 5 7600X, ASUS TUF B650M-PLUS WIFI, RTX 4070 Ti SUPER.
# NixOS lives on the Samsung 980 PRO 1TB; Windows is on the 9100 PRO.
{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "homepc";

  lifeline = {
    user = "tucker";
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOvX4BZrlfstsKxjAkWBWRc5nmCCrkvlLyuPUMNptDui"
    ];
  };

  # AMD's chipset watchdog, so a hung system resets itself.
  boot.kernelModules = [ "sp5100_tco" ];

  # Off for the baseline. See nixos/modules/desktop.nix before turning on.
  desktop = {
    enable = false;
    nvidia = true;
  };
}
