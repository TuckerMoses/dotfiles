# ── Desktop (off by default) ──────────────────────────────────────────
# GNOME, the NVIDIA driver and remote desktop (RDP). Kept out of the baseline
# because drivers and desktops are the likeliest way to lose a remote machine.
#
# Turn on with `desktop.enable = true;` in the host file, then use
# `trial-boot` (the driver needs a reboot), never a plain rebuild.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop;
in
{
  options.desktop = {
    enable = lib.mkEnableOption "the GNOME desktop with remote desktop access";
    nvidia = lib.mkEnableOption "the proprietary NVIDIA driver";
  };

  config = lib.mkIf cfg.enable {
    # ── GNOME ─────────────────────────────────────────────────────────
    services.xserver.enable = true;
    services.displayManager.gdm = {
      enable = true;
      # The login screen suspends an idle machine unless told not to.
      autoSuspend = false;
    };
    services.desktopManager.gnome.enable = true;

    # ── Remote desktop ────────────────────────────────────────────────
    # RDP on 3389, reachable only over Tailscale (tailscale0 is trusted;
    # the port is not opened on the LAN).
    services.gnome.gnome-remote-desktop.enable = true;
    systemd.services.gnome-remote-desktop.wantedBy = [ "graphical.target" ];

    # ── NVIDIA ────────────────────────────────────────────────────────
    nixpkgs.config.allowUnfree = lib.mkIf cfg.nvidia true;
    hardware.graphics.enable = true;
    services.xserver.videoDrivers = lib.mkIf cfg.nvidia [ "nvidia" ];
    hardware.nvidia = lib.mkIf cfg.nvidia {
      # RTX 40-series is supported by the open kernel modules.
      open = true;
      modesetting.enable = true;
      # Power management hooks into suspend, which this machine never does.
      powerManagement.enable = false;
    };

    environment.systemPackages = [ pkgs.gnome-remote-desktop ];
  };
}
