# NixOS hosts

`flake.nix` at the repo root defines the machines; everything else is here.

| Path | What it is |
|---|---|
| `modules/lifeline.nix` | What keeps a machine reachable: SSH, Tailscale, firewall, no sleep, watchdog, and a guard that fails the build if a change would cut any of them |
| `modules/safe-rebuild.nix` | `safe-switch`, `trial-boot`, `safe-confirm` |
| `modules/host-check.nix` | `host-check`, the on-machine test suite |
| `modules/base.nix` | Boot loader, Nix settings, tools |
| `modules/desktop.nix` | GNOME, NVIDIA and remote desktop; off by default |
| `hosts/homepc/` | The home PC |
| `hosts/vm/` | A QEMU guest running the same modules, for tests |
| `install.sh` | Installs a host from the NixOS installer |
| `test/` | VM harness (`vm.sh`) and lockout drills (`drills.sh`) |

## Changing a machine over SSH

Edit the checkout on the machine (`~/dotfiles`), then:

| Command | Use it for | If you do nothing |
|---|---|---|
| `safe-switch` | Ordinary changes (packages, services, settings) | Undone after 5 minutes; if nobody can log in after that, it reboots into the last confirmed system |
| `trial-boot` | Changes that need a reboot (kernel, drivers, boot settings). `safe-switch` tells you when | Reboots back into the old system after 10 minutes |
| `safe-confirm` | Keeping either kind of change. Run it from a **new** SSH session: that login is the proof you can still get in | |
| `host-check` | Checking the machine is healthy and reachable. Run it after every change | |

Rules while away from the machine:

- Never use `nixos-rebuild switch` directly. It has no rollback.
- Do not run `nix flake update`. It changes the kernel and Tailscale together.
- Two ways in over Tailscale: `ssh homepc` (port 22, answered by Tailscale SSH) and
  `ssh -p 2222 homepc` (OpenSSH). If one is broken, use the other.
- A change that disables SSH, Tailscale, the firewall holes, the login key or sudo will not build.
  That is the guard in `lifeline.nix`, not a bug.

What these do not cover: a trial system that hangs before it finishes booting and does not
panic. The watchdog resets most hangs; for the rest, cut the power with the smart plug (the
machine then boots the old system).

## Installing `homepc`

Needs a wired keyboard and a USB stick (4 GB or more).

1. **Flash the stick** on the Mac. The image is `~/Downloads/nixos-minimal-26.05-x86_64.iso`.
   Find the stick with `diskutil list`, then (replace `N`; this erases the stick):
   ```
   diskutil unmountDisk /dev/diskN
   sudo dd if=~/Downloads/nixos-minimal-26.05-x86_64.iso of=/dev/rdiskN bs=4m
   ```
2. **Before wiping anything:** boot the Windows clone on the 9100 PRO and check `C:` is on the
   2TB disk, `reagentc /info` points there, and it survives a reboot.
3. **BIOS** (Del at power-on, F7 for Advanced Mode):
   - Boot → Secure Boot → OS Type: **Other OS** (turns Secure Boot off).
   - Advanced → APM Configuration → Restore AC Power Loss: **Power On**.
   - Save, then press F8 at power-on and pick the USB stick.
4. **At the installer console**, set a temporary password and note the address:
   ```
   passwd
   ip -4 addr
   ```
5. **From the Mac**, copy the repo over and log in (`<ip>` from the last step):
   ```
   tar -C ~/dotfiles -cf - flake.nix flake.lock nixos | ssh nixos@<ip> 'mkdir cfg && tar -xf - -C cfg'
   ssh nixos@<ip>
   ```
6. **In that session**, fill in the two machine-specific files:
   ```
   cd cfg
   ls -l /dev/disk/by-id/ | grep -v part          # find the 980 PRO, by model AND size
   nano nixos/hosts/homepc/disko.nix              # put its nvme-Samsung_SSD_980_PRO_... name in `device`
   nixos-generate-config --no-filesystems --show-hardware-config > nixos/hosts/homepc/hardware-configuration.nix
   ```
7. **Install.** It shows the disk, asks you to type its model, then asks for a root password
   (the way in from the keyboard if SSH is ever broken):
   ```
   ./nixos/install.sh homepc
   ```
   Copy the two edited files back to the Mac before rebooting, so they get committed:
   ```
   scp nixos@<ip>:cfg/nixos/hosts/homepc/{disko,hardware-configuration}.nix ~/dotfiles/nixos/hosts/homepc/
   ```
8. **Reboot** without the stick. From the Mac: `ssh tucker@<ip>`.
9. **Join the tailnet** and open the link it prints:
   ```
   sudo tailscale up --ssh
   ```
   Then in the Tailscale admin console, open the machine's menu and choose **Disable key expiry**.
10. **Check:** `host-check` must end with "all passed".

## Before leaving it unattended

Each of these must end with the machine reachable over Tailscale and `host-check` passing:

1. `sudo systemctl reboot`, twice. It must come back into NixOS, not Windows, with nobody touching it.
2. Cut the power (smart plug off, then on). It must power on by itself and come back.
3. From a phone hotspot, not home Wi-Fi: `ssh tucker@homepc` and `ssh -p 2222 tucker@homepc`.
4. Make a harmless change, run `safe-switch 2`, and do **not** confirm. After 2 minutes
   `host-check` must show nothing pending and the change gone.
5. Push the branch, and on the machine replace the copied `~/dotfiles` with a real `git clone`.

## Testing in a VM

Needs QEMU and the installer images (`nixos-<arch>.iso`) in `test/.vm/`, or `VM_DIR` pointing
at them. Nix is not needed on the Mac.

```
nixos/test/vm.sh start aarch64 --iso      # boot the installer; authorize a key through the serial console
nixos/test/push.sh aarch64 nixos          # copy the repo in
nixos/test/vm.sh ssh aarch64 nixos 'cd cfg && ./nixos/install.sh vm-aarch64 --yes'
nixos/test/vm.sh stop aarch64 && nixos/test/vm.sh start aarch64
nixos/test/drills.sh aarch64              # every drill; TS_IP=<tailnet address> adds the Tailscale ones
```
