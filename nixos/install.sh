#!/usr/bin/env bash
# ── Install ───────────────────────────────────────────────────────────
# Run from the NixOS installer, inside a copy of this repo:
#
#   ./nixos/install.sh <host>          e.g. ./nixos/install.sh homepc
#
# It ERASES the disk named in the host's disko.nix, installs NixOS from this
# flake, and leaves a copy of the repo in the admin user's home so
# `safe-switch` works on first boot. `--yes` skips the questions (for VMs).
set -euo pipefail

host="${1:-}"
yes="${2:-}"
[[ -n $host ]] || { sed -n '2,10p' "$0"; exit 2; }
[[ $EUID -ne 0 ]] || { echo "run as the installer's normal user, not root" >&2; exit 1; }

flake="$(cd "$(dirname "$0")/.." && pwd)"
export NIX_CONFIG="experimental-features = nix-command flakes"
cfg="$flake#nixosConfigurations.$host.config"

device="$(nix eval --raw "$cfg.disko.devices.disk.main.device")"
user="$(nix eval --raw "$cfg.lifeline.user")"
dest="$(nix eval --raw "$cfg.lifeline.flakeDir")"

if [[ ! -b $device ]]; then
  echo "error: $device does not exist on this machine." >&2
  echo "Disks here:" >&2
  ls -l /dev/disk/by-id/ | grep -v -- '-part' >&2 || true
  echo "Put the right /dev/disk/by-id/ name in nixos/hosts/$host/disko.nix." >&2
  exit 1
fi
real="$(readlink -f "$device")"

echo "This will ERASE everything on:"
echo "  $device"
echo
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MODEL,SERIAL "$real"
echo
if [[ $yes != --yes ]]; then
  model="$(lsblk -dno MODEL "$real" | sed 's/ *$//')"
  read -r -p "Type the disk's model exactly as shown ($model) to erase it: " answer
  [[ $answer == "$model" ]] || { echo "Did not match. Nothing was changed."; exit 1; }
fi

echo "── Partitioning and formatting"
script="$(nix build --no-link --print-out-paths "$cfg.system.build.destroyFormatMount")"
sudo "$script/bin/disko-destroy-format-mount" ${yes:+--yes-wipe-all-disks}

echo "── Installing"
install_args=(--flake "$flake#$host" --no-channel-copy)
[[ $yes != --yes ]] || install_args+=(--no-root-password)
sudo nixos-install "${install_args[@]}"

echo "── Copying this repo to $dest"
sudo mkdir -p "/mnt$dest"
sudo cp -a "$flake/." "/mnt$dest/"
sudo nixos-enter --root /mnt -c "chown -R $user:users $dest"

echo
echo "Installed. Remove the installer stick and reboot."
