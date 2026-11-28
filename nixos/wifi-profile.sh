#!/usr/bin/env bash
# ── Wi-Fi profile ─────────────────────────────────────────────────────
# Gives a machine its Wi-Fi network name and password, so it joins at boot
# with nobody logged in. Run at the machine's own keyboard:
#
#   ./nixos/wifi-profile.sh /mnt     in the installer, after install.sh
#   ./nixos/wifi-profile.sh /        on the running system, to change networks
#
# It asks for the name and password and writes a NetworkManager profile only
# root can read. The password is never printed and never goes into git.
set -euo pipefail

root="${1:-}"
[[ -n $root ]] || { sed -n '2,11p' "$0"; exit 2; }
if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi
[[ -d $root/etc ]] || { echo "error: $root does not look like a system root" >&2; exit 1; }

read -r -p "Wi-Fi network name (SSID): " ssid
[[ -n $ssid ]] || { echo "error: the name is empty" >&2; exit 1; }
read -r -s -p "Wi-Fi password: " psk
echo
read -r -s -p "Wi-Fi password again: " psk2
echo
[[ $psk == "$psk2" ]] || { echo "error: the two passwords differ. Nothing was written." >&2; exit 1; }
if (( ${#psk} < 8 || ${#psk} > 63 )); then
  echo "error: a Wi-Fi password is 8 to 63 characters. Nothing was written." >&2
  exit 1
fi

dir="$root/etc/NetworkManager/system-connections"
file="$dir/lifeline-wifi.nmconnection"
mkdir -p "$dir"
chmod 700 "$dir"
umask 077
cat > "$file" <<EOF
[connection]
id=lifeline-wifi
type=wifi
autoconnect=true
autoconnect-priority=100
autoconnect-retries=0

[wifi]
mode=infrastructure
ssid=$ssid

[wifi-security]
key-mgmt=wpa-psk
psk=$psk

[ipv4]
method=auto

[ipv6]
method=auto
EOF
chmod 600 "$file"
echo "Wrote $file"

# On a running system, load it now.
if [[ $root == / ]] && command -v nmcli >/dev/null; then
  nmcli connection reload
  nmcli connection up lifeline-wifi || echo "warning: could not connect; check the name and password"
fi
