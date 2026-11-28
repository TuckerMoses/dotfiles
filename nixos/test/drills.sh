#!/usr/bin/env bash
# ── Drills ────────────────────────────────────────────────────────────
# Lockout drills against an installed, running guest (see vm.sh).
#
#   drills.sh <arch> [drill...]      no drill names = all, in order
#
# Each drill changes the guest's config through a module dropped at
# nixos/hosts/vm/test-override.nix on the guest, then checks the machine is
# still reachable (or becomes reachable again by itself).
# Set TS_IP to the guest's Tailscale address to also drill the tailnet paths.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
arch="$1"
shift
V="$here/vm.sh"
USER_NAME="${USER_NAME:-tucker}"
ATTR="vm-$arch"
TS_IP="${TS_IP:-}"

passed=0
failed=0
ok() { printf '    ok    %s\n' "$1"; passed=$((passed + 1)); }
bad() { printf '    FAIL  %s\n' "$1"; failed=$((failed + 1)); }
# expect <description> <command...>
expect() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
expect_not() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$d"; else ok "$d"; fi; }

# Every call is a fresh SSH connection.
g() { "$V" ssh "$arch" "$USER_NAME" "$@"; }
up() { g true 2>/dev/null; }
wait_up() { local t="${1:-300}"; for _ in $(seq $((t / 3))); do up && return 0; sleep 3; done; return 1; }
wait_down() { local t="${1:-120}"; for _ in $(seq "$t"); do up || return 0; sleep 1; done; return 1; }
override() { g "cat > ~/dotfiles/nixos/hosts/vm/test-override.nix"; }
clear_override() { g "rm -f ~/dotfiles/nixos/hosts/vm/test-override.nix" </dev/null; }
ts_ssh() {
  ssh -p "$1" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    -o ConnectTimeout=10 -o ControlPath=none -o BatchMode=yes "$USER_NAME@$TS_IP" true
}
cmdline_has() { g "grep -qw -- '$1' /proc/cmdline"; }

drill_baseline() {
  expect "host-check passes" g host-check
  expect "password login is refused" bash -c "! ssh -p $(port) -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no -o BatchMode=yes -o ControlPath=none $USER_NAME@127.0.0.1 true"
  expect_not "root login is refused" "$V" ssh "$arch" root true
  expect_not "suspend is refused" g "sudo systemctl suspend"
  sleep 3
  expect "still reachable after the suspend attempt" up
  if [[ -n $TS_IP ]]; then
    expect "Tailscale SSH answers on the tailnet address (port 22)" ts_ssh 22
    expect "OpenSSH answers on the tailnet address (port 2222)" ts_ssh 2222
  fi
}

port() { [[ $arch == aarch64 ]] && echo 2222 || echo 2223; }

drill_guard() {
  local name body
  while IFS='|' read -r name body; do
    echo "{ lib, ... }: { $body }" | override
    out="$(g "safe-switch 2" 2>&1 </dev/null)"
    if grep -q "lifeline:" <<<"$out"; then ok "build refused: $name"; else bad "build refused: $name"; fi
  done <<'EOF'
SSH disabled|services.openssh.enable = lib.mkForce false;
SSH port closed in the firewall|services.openssh.openFirewall = lib.mkForce false;
SSH port moved|services.openssh.ports = lib.mkForce [ 2022 ];
Tailscale disabled|services.tailscale.enable = lib.mkForce false;
no authorized keys|lifeline.authorizedKeys = lib.mkForce [ ];
sudo asks for a password|security.sudo.wheelNeedsPassword = lib.mkForce true;
suspend re-enabled|systemd.targets.suspend.enable = lib.mkForce true;
automatic upgrades on|system.autoUpgrade.enable = lib.mkForce true;
NetworkManager disabled|networking.networkmanager.enable = lib.mkForce false;
EOF
  clear_override
  expect "nothing is pending afterwards" g "test ! -e /run/safe-rebuild/pending"
}

drill_switch_confirm() {
  echo '{ pkgs, ... }: { environment.systemPackages = [ pkgs.hello ]; }' | override
  # Same session: confirming must be refused.
  out="$(g "safe-switch 3 >/dev/null 2>&1; safe-confirm" 2>&1)"
  if grep -q "older than the change" <<<"$out"; then ok "safe-confirm refused from the session that made the change"; else bad "safe-confirm refused from the session that made the change: $out"; fi
  expect "change is active but pending" g "command -v hello && test -e /run/safe-rebuild/pending"
  expect "safe-confirm accepted from a new session" g safe-confirm
  expect "rollback timer is gone" g "! systemctl is-active --quiet safe-rollback.timer"
  expect "running system is the boot default" g 'test "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)"'
  g "sudo systemctl reboot" 2>/dev/null
  wait_down 60
  expect "back after a reboot" wait_up 300
  expect "the change survived the reboot" g "command -v hello"
}

drill_lockout_rollback() {
  cat <<'EOF' | override
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.hello ];
  environment.etc."drill-marker".text = "lockout drill";
  # Passes the guard, but drops every incoming TCP connection.
  networking.firewall.extraCommands = "iptables -I INPUT -p tcp -j DROP";
}
EOF
  g "safe-switch 2" >/dev/null 2>&1 &
  local pid=$!
  if wait_down 240; then ok "the bad change locked SSH out"; else bad "the bad change locked SSH out"; fi
  if [[ -n $TS_IP ]]; then expect_not "locked out over Tailscale too" ts_ssh 2222; fi
  local start=$SECONDS
  if wait_up 600; then ok "SSH came back by itself after $((SECONDS - start))s"; else bad "SSH came back by itself"; fi
  kill "$pid" 2>/dev/null
  expect "the bad change is gone" g "test ! -e /etc/drill-marker"
  expect "the earlier confirmed change is still there" g "command -v hello"
  expect "nothing is pending" g "test ! -e /run/safe-rebuild/pending"
  expect "the rollback rebooted because nobody could log in" g "sudo journalctl -b -1 -u safe-rollback.service | grep -q 'nobody could log in'"
  if [[ -n $TS_IP ]]; then expect "reachable over Tailscale again" ts_ssh 2222; fi
  expect "host-check passes" g host-check
}

drill_lockout_inplace() {
  # Breaks OpenSSH logins only. The rollback should fix it without a reboot,
  # and Tailscale SSH should keep working throughout.
  cat <<'EOF' | override
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.hello ];
  environment.etc."drill-marker".text = "in-place drill";
  services.openssh.settings.AllowUsers = [ "nobody" ];
}
EOF
  local boot_before
  boot_before="$(g "cat /proc/sys/kernel/random/boot_id")"
  same_boot() { [[ "$(g "cat /proc/sys/kernel/random/boot_id")" == "$boot_before" ]]; }
  g "safe-switch 2" >/dev/null 2>&1
  expect_not "OpenSSH logins are locked out" up
  if [[ -n $TS_IP ]]; then
    expect "Tailscale SSH still gets in while OpenSSH is broken" ts_ssh 22
    expect_not "OpenSSH over Tailscale is locked out too" ts_ssh 2222
  fi
  local start=$SECONDS
  if wait_up 300; then ok "OpenSSH came back by itself after $((SECONDS - start))s"; else bad "OpenSSH came back by itself"; fi
  expect "the bad change is gone" g "test ! -e /etc/drill-marker"
  expect "it recovered without a reboot" same_boot
  sleep 75
  expect "it stayed up after the grace period (a login was seen)" same_boot
  expect "host-check passes" g host-check
}

drill_trial_confirm() {
  echo '{ pkgs, ... }: { environment.systemPackages = [ pkgs.hello ]; boot.kernelParams = [ "drill=1" ]; }' | override
  out="$(g "safe-switch 2" 2>&1)"
  if grep -q "trial-boot" <<<"$out"; then ok "safe-switch refuses a change that needs a reboot"; else bad "safe-switch refuses a change that needs a reboot"; fi
  expect "nothing is pending after the refusal" g "test ! -e /run/safe-rebuild/pending"
  g trial-boot >/dev/null 2>&1
  wait_down 90
  expect "back after the trial reboot" wait_up 300
  expect "running the trial system" cmdline_has drill=1
  expect "marked as a trial" g "test -e /run/safe-rebuild/trial && systemctl is-active --quiet trial-reboot.timer"
  expect "safe-confirm accepted" g safe-confirm
  expect "trial timer is gone" g "! systemctl is-active --quiet trial-reboot.timer"
  g "sudo systemctl reboot" 2>/dev/null
  wait_down 60
  expect "back after a plain reboot" wait_up 300
  expect "the trial system is now the default" cmdline_has drill=1
  expect "host-check passes" g host-check
}

drill_trial_timeout() {
  echo '{ pkgs, ... }: { environment.systemPackages = [ pkgs.hello ]; boot.kernelParams = [ "drill=2" ]; }' | override
  g trial-boot >/dev/null 2>&1
  wait_down 90
  expect "back after the trial reboot" wait_up 300
  expect "running the trial system" cmdline_has drill=2
  echo "    (not confirming; waiting for it to reboot back)"
  local start=$SECONDS
  # Wait for the kernel command line to change back, across the reboot.
  local back=1
  for _ in $(seq 120); do
    if cmdline_has drill=1 2>/dev/null; then back=0; break; fi
    sleep 3
  done
  if [[ $back -eq 0 ]]; then ok "rebooted back to the old system by itself after $((SECONDS - start))s"; else bad "rebooted back to the old system by itself"; fi
  expect "not a trial any more" g "test ! -e /run/safe-rebuild/trial"
  expect "host-check still passes (with a warning about the pin)" g host-check
  g "sudo systemctl reboot" 2>/dev/null
  wait_down 60
  expect "back after another reboot" wait_up 300
  expect "still on the old system" cmdline_has drill=1
}

drill_trial_unbootable() {
  # A system that cannot finish booting at all.
  echo '{ pkgs, ... }: { environment.systemPackages = [ pkgs.hello ]; boot.kernelParams = [ "drill=3" "init=/drill/does-not-exist" ]; }' | override
  g trial-boot >/dev/null 2>&1
  wait_down 90
  echo "    (the trial system cannot boot; waiting for the machine to recover)"
  local start=$SECONDS back=1
  for _ in $(seq 200); do
    if cmdline_has drill=1 2>/dev/null; then back=0; break; fi
    sleep 3
  done
  if [[ $back -eq 0 ]]; then ok "recovered to the old system by itself after $((SECONDS - start))s"; else bad "recovered to the old system by itself (machine is stuck)"; fi
  expect_not "the broken system never ran" cmdline_has drill=3
}

drill_power_pull() {
  "$V" kill "$arch"
  sleep 2
  "$V" start "$arch" >/dev/null
  expect "back after the power was cut" wait_up 300
  expect "host-check passes" g host-check
  if [[ -n $TS_IP ]]; then
    sleep 10
    expect "reachable over Tailscale again" ts_ssh 2222
  fi
}

drill_cleanup() {
  # Leave the guest on the plain config, confirmed, with no pin left over.
  clear_override
  g trial-boot >/dev/null 2>&1
  wait_down 90
  expect "back after the trial reboot" wait_up 300
  expect "safe-confirm accepted" g safe-confirm
  expect_not "drill parameters are gone" cmdline_has drill=1
  out="$(g host-check 2>&1)"
  if grep -q "pinned" <<<"$out"; then bad "no pin is left over"; else ok "no pin is left over"; fi
  expect "host-check passes" g host-check
}

all=(baseline guard switch_confirm lockout_inplace lockout_rollback trial_confirm trial_timeout trial_unbootable power_pull cleanup)
[[ $# -gt 0 ]] || set -- "${all[@]}"
for d in "$@"; do
  echo "── $d ($ATTR)"
  "drill_$d"
done
echo
echo "drills: $passed passed, $failed failed"
[[ $failed -eq 0 ]]
