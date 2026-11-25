# ── vm ────────────────────────────────────────────────────────────────
# A QEMU guest that runs the same modules as homepc, for testing the install
# and the rollback tools away from the real machine. Same disk layout, on the
# guest's virtual NVMe drive.
{
  lib,
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../homepc/disko.nix
  ]
  # Test drills drop a module here, on the guest only, to change the config.
  ++ lib.optional (builtins.pathExists ./test-override.nix) ./test-override.nix;

  disko.devices.disk.main.device = lib.mkForce "/dev/disk/by-id/nvme-QEMU_NVMe_Ctrl_TESTNVME0001";

  networking.hostName = "nixvm";

  lifeline = {
    user = "tucker";
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOvX4BZrlfstsKxjAkWBWRc5nmCCrkvlLyuPUMNptDui"
    ];
  };

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "virtio_pci"
    "virtio_blk"
    "virtio_net"
    "usbhid"
  ];
  # QEMU's emulated watchdog card (x86 guests). Loaded in the initrd, as on homepc.
  boot.initrd.kernelModules = lib.optional pkgs.stdenv.hostPlatform.isx86_64 "i6300esb";
  boot.kernelModules = lib.optional pkgs.stdenv.hostPlatform.isx86_64 "i6300esb";

  # Serial console, so the guest can be driven without a display.
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
    "console=ttyAMA0,115200"
  ];

  # A VM has no firmware boot order worth asserting.
  hostCheck.requireFirmwareOrder = false;
  # Test guests join with a short-lived key, which always has an expiry.
  hostCheck.requireTailnet = false;
  # No watchdog device on the aarch64 guest.
  hostCheck.requireWatchdog = false;

  # Drills should not wait ten minutes for a trial boot to time out.
  safeRebuild.trialMinutes = 2;
  safeRebuild.graceMinutes = 1;
}
