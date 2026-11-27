# NixOS hosts

`flake.nix` at the repo root defines the machines; everything else is here.

| Path | What it is |
|---|---|
| `modules/lifeline.nix` | What keeps a machine reachable: SSH, Tailscale, firewall, no sleep, watchdog, and a guard that fails the build if a change would cut SSH, Tailscale, the OpenSSH firewall hole, the login key, sudo or NetworkManager, or turn on sleep or auto-upgrades |
| `modules/safe-rebuild.nix` | `safe-switch`, `trial-boot`, `safe-confirm` |
| `modules/host-check.nix` | `host-check`, the on-machine test suite |
| `modules/base.nix` | Boot loader, Nix settings, tools |
| `modules/desktop.nix` | GNOME, NVIDIA and remote desktop; off by default |
| `modules/dotfiles-user.nix` | The `dotfiles.users` option: the dotfiles' configs and tools for named users, through Home Manager |
| `hosts/homepc/` | The home PC |
| `hosts/vm/` | A QEMU guest running the same modules, for tests |
| `install.sh` | Installs a host from the NixOS installer |
| `test/` | VM harness (`vm.sh`) and lockout drills (`drills.sh`) |

## The dotfiles for a user

The other modules set up the system. `modules/dotfiles-user.nix` works one level down: it hands named
users to the dotfiles' Home Manager module (`nix/home-manager/`; Home Manager is a Nix tool that places
files and packages in a user's home), which links that user's configs and installs the tools the configs
call. A host names users like this:

```nix
dotfiles.users.alice = { linkMode = "store"; };   # configs linked from the build: an edit needs a rebuild
dotfiles.users.bob = {
  linkMode = "checkout";                           # configs linked into a checkout: edits are live, as with Stow
  checkout = "/srv/dotfiles";                      # absolute path of a git checkout of this repo
};
```

Every host imports the file, and it is empty by default. No host names a user yet, so `homepc`'s system is
unchanged by it and `tucker`'s home is still set up by Stow. The module never changes a login shell. The VM
test `vm-home` (`nix/tests/`) is the one place users are named. How the module works and how to test it:
the "Nix" section of the top-level `README.md`, and `test/README.md`.

## Changing a machine over SSH

Edit the checkout on the machine (`~/dotfiles`), then:

| Command | Use it for | If you do nothing |
|---|---|---|
| `safe-switch` | Ordinary changes (packages, services, settings) | Undone after 5 minutes; if nobody can log in after that, it reboots into the last confirmed system |
| `trial-boot` | Changes that need a reboot (kernel, drivers, boot settings). `safe-switch` refuses and tells you when | Reboots back into the old system after 10 minutes |
| `safe-confirm` | Keeping either kind of change. Run it from a **new** SSH session: that login is the proof you can still get in. A Tailscale SSH login proves only the Tailscale path; when the change touched sshd or the firewall, confirm from `ssh -p 2222 homepc` | |
| `host-check` | Checking the machine is healthy and reachable. Run it after every change | |

Rules while away from the machine:

- Never use `nixos-rebuild switch` directly. It has no rollback.
- Do not run `nix flake update`. It changes the kernel and Tailscale together.
- Two ways in over Tailscale: `ssh homepc` (port 22, answered by Tailscale SSH) and
  `ssh -p 2222 homepc` (OpenSSH). If one is broken, use the other.
- A change the `lifeline.nix` guard rejects (see the file table) will not build. That is not a bug.

What these do not cover: a trial system that hangs before systemd starts (kernel or initrd) and does not
panic, or any hang that does not panic while the hardware watchdog is off. The watchdog cannot reset that; cut the power with the smart plug (the machine then boots the old system).

## Installing `homepc`

Needs a wired keyboard and a USB stick (4 GB or more).

1. **Flash the stick** on the Mac. The image is `~/Downloads/nixos-minimal-26.05-x86_64.iso`.
   Find the stick with `diskutil list`, then (replace `N`; this erases the stick):
   ```
   diskutil unmountDisk /dev/diskN
   sudo dd if="$HOME/Downloads/nixos-minimal-26.05-x86_64.iso" of=/dev/rdiskN bs=4m
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
   COPYFILE_DISABLE=1 tar -C ~/dotfiles --no-xattrs --exclude nixos/test/.vm -cf - flake.nix flake.lock nixos | ssh nixos@<ip> 'mkdir cfg && tar -xf - -C cfg'
   ssh nixos@<ip>
   ```
6. **In that session**, fill in the two machine-specific files:
   ```
   cd cfg
   ls -l /dev/disk/by-id/ | grep -v part          # find the 980 PRO, by model AND size
   nano nixos/hosts/homepc/disko.nix              # put its nvme-Samsung_SSD_980_PRO_... name in `device`
   lsblk -dno NAME,MODEL,SIZE                     # the model and size must be the 980 PRO's
   nixos-generate-config --no-filesystems --show-hardware-config > nixos/hosts/homepc/hardware-configuration.nix
   ```
7. **Install.** It first refuses unless the disk's model matches `installDiskModel` in
   `hosts/homepc/default.nix` (and the disk is not the one the installer booted from), then shows
   the disk, asks you to type its model, then asks for a root password
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
6. Trial-boot a harmless change that needs a reboot (add `boot.kernelParams = [ "drill=1" ];`),
   run `trial-boot`, and do **not** confirm. It must be back on the old system by itself within
   about 10 minutes (this is the firmware check the VM could not do). Undo the edit afterwards.
7. Crash it on purpose: `sudo sh -c 'echo 1 > /proc/sys/kernel/sysrq; echo c > /proc/sysrq-trigger'`.
   It must come back by itself within a few minutes. `host-check` must show the hardware
   watchdog as armed. A FAIL on the watchdog line means `sp5100_tco` did not bind on this
   board: look for a watchdog or TCO setting in the BIOS; only if there is none, set
   `hostCheck.requireWatchdog = false` in `hosts/homepc/default.nix`. Then a hang that
   does not panic is no longer reset (see "What these do not cover").
8. Power off the router and the PC together, power the PC on first and the router about 3 minutes
   later. The PC must be reachable within 25 minutes.
9. Run `nixos/test/drills.sh x86_64` once in the x86_64 VM, so the drills have run on the same
   architecture as the real machine.

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
