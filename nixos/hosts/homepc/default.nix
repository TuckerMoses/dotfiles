# ── homepc ────────────────────────────────────────────────────────────
# The home PC: Ryzen 5 7600X, ASUS TUF B650M-PLUS WIFI, RTX 4070 Ti SUPER.
# NixOS lives on the Samsung 980 PRO 1TB; Windows is on the 9100 PRO.
{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "homepc";

  # This machine is on Wi-Fi (no cable reaches it). The network name and
  # password live in a root-only NetworkManager profile written by
  # nixos/wifi-profile.sh, not here. Power saving off, so the card does not doze.
  networking.networkmanager.wifi.powersave = false;

  lifeline = {
    user = "tucker";
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOvX4BZrlfstsKxjAkWBWRc5nmCCrkvlLyuPUMNptDui"
    ];
    # The Windows disk is a Samsung too; see lifeline.installDiskModel.
    installDiskModel = "Samsung SSD 980 PRO 1TB";
  };

  # AMD's chipset watchdog, so a hung system resets itself. Loaded in the
  # initrd as well, so it exists before systemd tries to open it.
  boot.initrd.kernelModules = [ "sp5100_tco" ];
  boot.kernelModules = [ "sp5100_tco" ];

  # Not in hardware-configuration.nix: the install regenerates that file. Without
  # it there is no firmware for the RTL8125 wired port or the Wi-Fi.
  hardware.enableRedistributableFirmware = true;

  # All off for the baseline. Turn on one at a time, in this order; see
  # nixos/modules/desktop.nix.
  desktop = {
    nvidia = false;
    enable = false;
    remoteDesktop = false;
  };
}
