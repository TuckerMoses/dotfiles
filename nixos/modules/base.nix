# ── Base ──────────────────────────────────────────────────────────────
# Boot loader, Nix settings and the few tools needed to iterate over SSH.
{ pkgs, lib, ... }:
{
  # ── Boot ──────────────────────────────────────────────────────────
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 20;
    # No kernel command-line editing from the boot menu.
    editor = false;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  # Short menu: an unattended boot must not sit waiting.
  boot.loader.timeout = 3;

  # ── Nix ───────────────────────────────────────────────────────────
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "@wheel"
    ];
  };
  # Old generations are the rollback targets: collect by hand, never on a timer.
  nix.gc.automatic = false;

  # ── Prebuilt binaries ─────────────────────────────────────────────
  # Lets downloaded binaries (agent tools, npx, pip wheels) find a loader.
  programs.nix-ld.enable = true;

  # ── Tools ─────────────────────────────────────────────────────────
  programs.git.enable = true;
  environment.systemPackages = with pkgs; [
    curl
    efibootmgr
    htop
    jq
    neovim
    tmux
  ];

  # ── Clock ─────────────────────────────────────────────────────────
  # Hardware clock in UTC; Windows was switched to match.
  time.hardwareClockInLocalTime = false;
  time.timeZone = lib.mkDefault "UTC";

  system.stateVersion = "26.05";
}
