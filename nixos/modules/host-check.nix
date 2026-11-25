# ── Host check ────────────────────────────────────────────────────────
# `host-check` asserts, on the running machine, everything that keeps it
# reachable. Run it after the install, after every rebuild, and before
# walking away. It only reads; it exits 1 if anything failed.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hostCheck;
  user = config.lifeline.user;
  loaderGuid = "4a67b082-0a4c-41cf-b6c7-440b29bb8c4f";

  host-check = pkgs.writeShellApplication {
    name = "host-check";
    runtimeInputs = [
      config.systemd.package
      config.services.tailscale.package
      config.services.openssh.package
      pkgs.coreutils
      pkgs.efibootmgr
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.iproute2
      pkgs.iptables
      pkgs.jq
      pkgs.util-linux
    ];
    text = ''
      if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

      fails=0
      warns=0
      pass() { printf '  ok    %s\n' "$1"; }
      fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
      warn() { printf '  warn  %s\n' "$1"; warns=$((warns + 1)); }
      # check <description> <command...>: FAIL unless the command succeeds.
      check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
      loader_var() {
        local f="/sys/firmware/efi/efivars/$1-${loaderGuid}"
        [[ -r $f ]] || return 0
        tail -c +5 "$f" | tr -d '\0'
      }

      echo "SSH"
      check "sshd is running" systemctl is-active --quiet sshd.service
      check "sshd starts at boot" systemctl is-enabled --quiet sshd.service
      check "sshd listens on port 22" bash -c "ss -Htlnp 'sport = :22' | grep -q sshd"
      check "sshd listens on port 2222 (OpenSSH over Tailscale)" bash -c "ss -Htlnp 'sport = :2222' | grep -q sshd"
      sshd_conf="$(sshd -T 2>/dev/null || true)"
      if grep -qix 'passwordauthentication no' <<<"$sshd_conf"; then pass "password logins are off"; else fail "password logins are off"; fi
      if grep -qix 'pubkeyauthentication yes' <<<"$sshd_conf"; then pass "key logins are on"; else fail "key logins are on"; fi
      if [[ -s /etc/ssh/authorized_keys.d/${user} ]]; then pass "${user} has an authorized key"; else fail "${user} has an authorized key"; fi
      check "${user} can sudo without a password" sudo -u ${user} sudo -n true
      check "the firewall allows port 22" bash -c "iptables -S 2>/dev/null | grep -q -- '--dport 22 -j nixos-fw-accept' || nft list ruleset 2>/dev/null | grep -Eq 'dport \{?[^}]*\b22\b'"

      echo "Tailscale"
      check "tailscaled is running" systemctl is-active --quiet tailscaled.service
      check "tailscaled starts at boot" systemctl is-enabled --quiet tailscaled.service
      ts="$(tailscale status --json 2>/dev/null || echo '{}')"
      ts_state="$(jq -r '.BackendState // "unknown"' <<<"$ts")"
      if [[ $ts_state == Running ]]; then
        pass "joined to the tailnet ($(jq -r '.Self.TailscaleIPs[0] // "no address"' <<<"$ts"))"
        expiry="$(jq -r '.Self.KeyExpiry // ""' <<<"$ts")"
        if [[ -z $expiry ]]; then
          pass "node key does not expire"
        else
          ${if cfg.requireTailnet then "fail" else "warn"} "node key expires $expiry (disable key expiry for this machine in the Tailscale admin console)"
        fi
        if [[ "$(tailscale debug prefs 2>/dev/null | jq -r '.RunSSH')" == true ]]; then
          pass "Tailscale SSH is on (second way in)"
        else
          warn "Tailscale SSH is off (run: sudo tailscale set --ssh)"
        fi
      else
        ${if cfg.requireTailnet then "fail" else "warn"} "not joined to the tailnet (state: $ts_state; run: sudo tailscale up --ssh)"
      fi

      echo "Network"
      check "NetworkManager is running" systemctl is-active --quiet NetworkManager.service
      dev="$(ip -4 route show default | awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}')"
      if [[ -z $dev ]]; then
        fail "there is a default route"
      elif [[ -d /sys/class/net/$dev/wireless ]]; then
        warn "the default route is over Wi-Fi ($dev); wired is more dependable"
      else
        pass "the default route is over $dev"
      fi

      echo "Staying up"
      for t in sleep suspend hibernate hybrid-sleep; do
        if [[ "$(systemctl is-enabled "$t.target" 2>/dev/null || true)" == masked ]]; then pass "$t is disabled"; else fail "$t is disabled"; fi
      done
      wd="$(systemctl show -P RuntimeWatchdogUSec)"
      if [[ -n $wd && $wd != 0 && $wd != infinity ]]; then
        if [[ -e /dev/watchdog0 ]]; then pass "hardware watchdog is armed ($wd)"; else warn "watchdog is configured but this machine exposes no watchdog device"; fi
      else
        fail "watchdog is configured"
      fi
      if systemctl list-timers --all --no-legend 2>/dev/null | grep -q nixos-upgrade; then fail "automatic upgrades are off"; else pass "automatic upgrades are off"; fi
      if findmnt -rn -t ntfs,ntfs3,fuseblk >/dev/null 2>&1; then warn "a Windows (NTFS) partition is mounted"; else pass "no Windows partition is mounted"; fi
      used="$(df --output=pcent / | tail -1 | tr -dc 0-9)"
      if (( used < 90 )); then pass "root filesystem has room ($used% used)"; else fail "root filesystem has room ($used% used)"; fi

      echo "Boot"
      if [[ -d /sys/firmware/efi ]]; then
        selected="$(loader_var LoaderEntrySelected)"
        pinned="$(loader_var LoaderEntryDefault)"
        if [[ -n $selected ]]; then pass "booted through systemd-boot ($selected)"; else fail "booted through systemd-boot"; fi
        if [[ -e /run/safe-rebuild/trial ]]; then
          warn "this is an unconfirmed TRIAL boot: run safe-confirm or it reboots"
        elif [[ -n $pinned ]]; then
          warn "the boot default is pinned to $pinned (a trial was not confirmed); safe-confirm after the next good change clears it"
        else
          pass "no trial boot is pending"
        fi
        if [[ -e /run/safe-rebuild/pending ]]; then warn "an unconfirmed safe-switch is active: run safe-confirm or it rolls back"; else pass "no safe-switch is pending"; fi
        if [[ "$(readlink -f /run/current-system)" == "$(readlink -f /nix/var/nix/profiles/system)" ]]; then
          pass "the running system is the boot default"
        else
          warn "the running system is not the one that boots next"
        fi
        order="$(efibootmgr 2>/dev/null || true)"
        first="$(sed -n 's/^BootOrder: \([0-9A-Fa-f]*\).*/\1/p' <<<"$order")"
        first_label="$(sed -n "s/^Boot$first\*\? \(.*\)/\1/p" <<<"$order" | cut -f1)"
        if grep -qi 'linux boot manager' <<<"$first_label"; then
          pass "firmware boots Linux first ($first_label)"
        else
          ${if cfg.requireFirmwareOrder then "fail" else "warn"} "firmware does not boot Linux first (first entry: ''${first_label:-unknown})"
        fi
      else
        fail "booted in UEFI mode"
      fi

      echo "Config"
      if [[ -e ${config.lifeline.flakeDir}/flake.nix ]]; then
        pass "the config checkout is at ${config.lifeline.flakeDir}"
      else
        warn "no config checkout at ${config.lifeline.flakeDir} (safe-switch builds from there)"
      fi

      echo
      if (( fails > 0 )); then
        echo "host-check: $fails FAILED, $warns warning(s)"
        exit 1
      fi
      echo "host-check: all passed, $warns warning(s)"
    '';
  };
in
{
  options.hostCheck = {
    requireTailnet = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Fail (not warn) when the machine is not on the tailnet with a non-expiring key.";
    };
    requireFirmwareOrder = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Fail (not warn) when the firmware's first boot entry is not Linux.";
    };
  };

  config.environment.systemPackages = [ host-check ];
}
