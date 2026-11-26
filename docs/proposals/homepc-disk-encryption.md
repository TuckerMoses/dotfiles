---
created: 2026-11-25
source: session (nixos-host), agreed with the user after the homepc install
---

# homepc: encrypt the disk and still boot unattended

- **What:** Put homepc's NixOS disk under LUKS encryption, unlocked by the TPM so the machine
  still reboots with nobody at it.
- **Why here:** The disk is plain Btrfs (`nixos/hosts/homepc/disko.nix`), a choice made on
  2026-11-24 so that an unattended reboot never waits for a passphrase. It now holds the SSH host
  keys, the Tailscale node key, GitHub deploy keys, the Claude login and the remote desktop
  credentials, all readable by anyone who takes the drive. If homepc becomes the aiOS server, its
  record would be on that disk too.
- **Effort:** large.
- **Touches:** `nixos/hosts/homepc/disko.nix`, `nixos/modules/base.nix` (boot loader),
  `nixos/install.sh`, `nixos/modules/host-check.nix`, `nixos/README.md`.
- **Needs the real machine:** yes, with someone at it. This is a reinstall.
- **Notes for the plan:**
  - TPM unlock only protects anything when the boot chain is measured, which means Secure Boot
    (lanzaboote on NixOS). Secure Boot was turned off on 2026-11-25 to install. Windows on the
    other drive may want it back on for anti-cheat, so the two goals line up.
  - `trial-boot` relies on systemd-boot entries and EFI variables; check it still works under
    lanzaboote before trusting it remotely.
  - Keep a recovery passphrase that is stored off the machine.
  - The TPM has surprised us once already: GNOME Remote Desktop's TPM-sealed credentials failed to
    load after a reboot (`desktop.nix` records why they are kept in a file). Test every unlock
    path across a real power cycle, not a service restart.
  - Re-run the full lockout, power-cut and trial-boot drills on the encrypted install.
  - The config is reproducible from the flake, so the reinstall loses no system state; list what
    is not in the flake (Tailscale login, Wi-Fi profile, remote desktop credentials, deploy keys,
    Claude login, `/home`) and how each is restored.

## Needs decision
When is someone at the machine for the reinstall, and should Secure Boot (lanzaboote) be adopted
in the same change?
