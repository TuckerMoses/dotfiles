# ── Desktop (all off by default) ──────────────────────────────────────
# Three switches, meant to be turned on one at a time, in this order:
#
#   desktop.nvidia         the NVIDIA driver. A kernel change: use `trial-boot`.
#   desktop.enable         the GNOME desktop and its login screen.
#   desktop.remoteDesktop  RDP into the desktop, reachable over Tailscale only.
#
# Kept out of the baseline because drivers and desktops are the likeliest way
# to lose a remote machine.
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
    nvidia = lib.mkEnableOption "the proprietary NVIDIA driver";
    enable = lib.mkEnableOption "the GNOME desktop";
    remoteDesktop = lib.mkEnableOption "RDP access to the GNOME desktop over Tailscale";
  };

  config = lib.mkMerge [
    # ── NVIDIA ──────────────────────────────────────────────────────────
    (lib.mkIf cfg.nvidia {
      nixpkgs.config.allowUnfree = true;
      hardware.graphics.enable = true;
      # This is what loads the driver, with or without a desktop.
      services.xserver.videoDrivers = [ "nvidia" ];
      hardware.nvidia = {
        # RTX 40-series is supported by the open kernel modules.
        open = true;
        modesetting.enable = true;
        # Power management hooks into suspend, which this machine never does.
        powerManagement.enable = false;
      };
    })

    # ── GNOME ───────────────────────────────────────────────────────────
    (lib.mkIf cfg.enable {
      services.xserver.enable = true;
      services.displayManager.gdm = {
        enable = true;
        # The login screen suspends an idle machine unless told not to.
        autoSuspend = false;
      };
      services.desktopManager.gnome.enable = true;
      hardware.graphics.enable = true;
    })

    # ── Remote desktop ──────────────────────────────────────────────────
    # RDP on 3389. tailscale0 is a trusted interface, so it is reachable over
    # Tailscale; the port is not opened on the LAN.
    (lib.mkIf cfg.remoteDesktop {
      services.gnome.gnome-remote-desktop.enable = true;
      systemd.services.gnome-remote-desktop.wantedBy = [ "graphical.target" ];
      environment.systemPackages = [ pkgs.gnome-remote-desktop ];

      # RDP needs the password itself, not a hash, so it cannot be stored the
      # way login passwords are. With access to the TPM the service seals it
      # there; without, it falls back to a plain file only root can read.
      security.tpm2.enable = true;
      users.users.gnome-remote-desktop.extraGroups = [ "tss" ];
    })

    {
      assertions = [
        {
          assertion = cfg.remoteDesktop -> cfg.enable;
          message = "desktop: remoteDesktop needs desktop.enable (there is no desktop to share without it).";
        }
      ];
    }
  ];
}
