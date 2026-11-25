#!/usr/bin/env bash
# Copy this repo's flake (flake.nix, flake.lock, nixos/) into a guest.
#   push.sh <arch> <user> [dest]     dest defaults to ~/cfg
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
arch="$1"
user="$2"
dest="${3:-cfg}"
files=(flake.nix nixos)
[[ ! -f $root/flake.lock ]] || files+=(flake.lock)
COPYFILE_DISABLE=1 tar -C "$root" --no-xattrs --exclude .vm -cf - "${files[@]}" |
  "$here/vm.sh" ssh "$arch" "$user" "rm -rf $dest && mkdir -p $dest && tar -xf - -C $dest"
