# ── Safe rebuild ──────────────────────────────────────────────────────
# Three commands for changing this machine without being at it:
#
#   safe-switch   build and activate a change; it is undone automatically
#                 unless `safe-confirm` is run from a NEW login in time.
#   trial-boot    for changes that need a reboot (kernel, drivers, boot
#                 settings): boot the new system once, with the old one still
#                 the default; it reboots back unless confirmed.
#   safe-confirm  keep the change.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  flakeDir = config.lifeline.flakeDir;
  host = config.lifeline.flakeAttr;
  esp = config.boot.loader.efi.efiSysMountPoint;
  state = "/run/safe-rebuild";
  loaderGuid = "4a67b082-0a4c-41cf-b6c7-440b29bb8c4f";

  runtimeInputs = [
    config.nix.package
    config.systemd.package
    pkgs.coreutils
    pkgs.gnused
    pkgs.procps
  ];

  # Shared shell helpers.
  common = ''
    STATE=${state}
    FLAKE="''${SAFE_FLAKE:-${flakeDir}}"
    HOST=${host}
    export STATE FLAKE HOST

    die() { echo "error: $*" >&2; exit 1; }

    # Print a systemd-boot EFI variable (stored as UTF-16 after 4 flag bytes).
    loader_var() {
      local f="/sys/firmware/efi/efivars/$1-${loaderGuid}"
      [[ -r $f ]] || return 0
      tail -c +5 "$f" | tr -d '\0'
    }

    build_system() {
      [[ $EUID -ne 0 ]] || die "run this as your own user, not root (it uses sudo itself)"
      [[ -e $FLAKE/flake.nix ]] || die "no flake at $FLAKE"
      echo "Building $FLAKE#$HOST ..." >&2
      nix build --no-link --print-out-paths \
        "$FLAKE#nixosConfigurations.$HOST.config.system.build.toplevel"
    }

    # True when the new system needs a reboot to take effect.
    needs_reboot() {
      local new="$1" part
      for part in kernel initrd; do
        if [[ "$(readlink -f "$new/$part")" != "$(readlink -f "/run/booted-system/$part")" ]]; then
          return 0
        fi
      done
      if ! cmp -s "$new/kernel-params" /run/booted-system/kernel-params; then
        return 0
      fi
      return 1
    }
  '';

  safe-rollback = pkgs.writeShellApplication {
    name = "safe-rollback";
    inherit runtimeInputs;
    text = ''
      ${common}
      old="$(cat "$STATE/old")"
      echo "safe-rollback: not confirmed in time, restoring $old"
      if ! "$old/bin/switch-to-configuration" test; then
        echo "safe-rollback: restoring failed, rebooting into the boot default"
        systemctl reboot
        exit 0
      fi
      rm -f "$STATE/pending"
      sleep 5
      for unit in sshd.service tailscaled.service NetworkManager.service; do
        if ! systemctl is-active --quiet "$unit"; then
          echo "safe-rollback: $unit is not running after the restore, rebooting"
          systemctl reboot
          exit 0
        fi
      done
      echo "safe-rollback: restored"
    '';
  };

  # Root half of safe-switch.
  safe-activate = pkgs.writeShellApplication {
    name = "safe-activate";
    inherit runtimeInputs;
    text = ''
      ${common}
      new="$1"
      minutes="$2"
      [[ $EUID -eq 0 ]] || die "must run as root"
      mkdir -p "$STATE"
      [[ ! -e $STATE/pending ]] || die "a change is already waiting: run safe-confirm, or wait for its rollback"
      [[ ! -e $STATE/trial ]] || die "this is a trial boot: run safe-confirm first"
      old="$(readlink -f /run/current-system)"
      if [[ $new == "$old" ]]; then
        echo "Nothing to do: that is already the running system."
        exit 0
      fi
      echo "$old" > "$STATE/old"
      echo "$new" > "$STATE/new"
      date +%s > "$STATE/armed"
      touch "$STATE/pending"

      systemctl stop safe-rollback.timer safe-rollback.service 2>/dev/null || true
      systemctl reset-failed safe-rollback.service safe-activate.service 2>/dev/null || true
      systemd-run --quiet --collect --unit=safe-rollback \
        --on-active="''${minutes}m" --timer-property=AccuracySec=1s \
        ${safe-rollback}/bin/safe-rollback

      echo "Activating. Rollback is armed for $minutes minutes."
      # Runs as its own unit so it finishes even if this SSH session drops.
      systemd-run --quiet --collect --wait --unit=safe-activate \
        "$new/bin/switch-to-configuration" test \
        || echo "warning: activation reported errors (see: journalctl -u safe-activate)"

      echo
      echo "Now open a NEW ssh session and run:  safe-confirm"
      echo "If you cannot get in, do nothing: it rolls back by itself in $minutes minutes."
    '';
  };

  safe-switch = pkgs.writeShellApplication {
    name = "safe-switch";
    inherit runtimeInputs;
    text = ''
      ${common}
      minutes="''${1:-5}"
      [[ $minutes =~ ^[0-9]+$ ]] || die "usage: safe-switch [minutes]"
      new="$(build_system)"
      if needs_reboot "$new"; then
        die "this change touches the kernel, initrd or kernel parameters, which only a reboot applies. Use: trial-boot"
      fi
      exec sudo ${safe-activate}/bin/safe-activate "$new" "$minutes"
    '';
  };

  # Root half of trial-boot.
  trial-arm = pkgs.writeShellApplication {
    name = "trial-arm";
    inherit runtimeInputs;
    text = ''
      ${common}
      new="$1"
      [[ $EUID -eq 0 ]] || die "must run as root"
      [[ ! -e $STATE/pending ]] || die "a change is waiting: run safe-confirm, or wait for its rollback"
      [[ ! -e $STATE/trial ]] || die "this is already a trial boot: run safe-confirm first"
      current="$(loader_var LoaderEntrySelected)"
      [[ -n $current ]] || die "cannot read the booted entry (not booted through systemd-boot?)"
      [[ -e ${esp}/loader/entries/$current ]] || die "booted entry $current is not on ${esp}"

      nix-env -p /nix/var/nix/profiles/system --set "$new"
      "$new/bin/switch-to-configuration" boot
      generation="$(readlink /nix/var/nix/profiles/system | sed -E 's/^system-([0-9]+)-link$/\1/')"
      entry="nixos-generation-$generation.conf"
      [[ -e ${esp}/loader/entries/$entry ]] || die "expected boot entry $entry was not written"
      [[ $entry != "$current" ]] || die "nothing new to boot: $entry is already running"

      # Old system stays the default; the new one boots exactly once.
      bootctl set-default "$current"
      bootctl set-oneshot "$entry"
      [[ "$(loader_var LoaderEntryDefault)" == "$current" ]] || die "could not pin the default entry; not rebooting"
      [[ "$(loader_var LoaderEntryOneShot)" == "$entry" ]] || die "could not set the one-time entry; not rebooting"

      echo "Rebooting into $entry on trial (default stays $current)."
      echo "When it is back, log in and run:  safe-confirm"
      echo "Without that, it reboots into $current after ${toString trialMinutes} minutes."
      systemctl reboot
    '';
  };

  trial-boot = pkgs.writeShellApplication {
    name = "trial-boot";
    inherit runtimeInputs;
    text = ''
      ${common}
      new="$(build_system)"
      exec sudo ${trial-arm}/bin/trial-arm "$new"
    '';
  };

  safe-confirm = pkgs.writeShellApplication {
    name = "safe-confirm";
    inherit runtimeInputs;
    text = ''
      ${common}
      if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi
      force=0
      [[ "''${1:-}" != --force ]] || force=1

      # Confirming from the session that made the change proves nothing:
      # only a login made after it shows the machine is still reachable.
      require_new_session() {
        local armed="$1" pid=$$ comm start
        [[ $force -eq 0 ]] || return 0
        while [[ $pid -gt 1 ]]; do
          comm="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
          if [[ $comm == sshd* ]]; then
            start="$(stat -c %Y "/proc/$pid")"
            if (( start <= armed )); then
              die "this SSH session is older than the change. Open a NEW session (ssh -o ControlPath=none ...) and run safe-confirm there."
            fi
            return 0
          fi
          pid="$(ps -o ppid= -p "$pid" | tr -d ' ')"
          [[ -n $pid ]] || break
        done
        return 0
      }

      did=0

      if [[ -e $STATE/pending ]]; then
        require_new_session "$(cat "$STATE/armed")"
        systemctl stop safe-rollback.timer 2>/dev/null || true
        new="$(cat "$STATE/new")"
        if [[ "$(readlink -f /run/current-system)" != "$new" ]]; then
          rm -f "$STATE/pending"
          die "the pending change is no longer running (it was rolled back). Nothing confirmed."
        fi
        nix-env -p /nix/var/nix/profiles/system --set "$new"
        "$new/bin/switch-to-configuration" boot
        bootctl set-default "" 2>/dev/null || true
        rm -f "$STATE/pending"
        echo "Confirmed: this configuration is now the boot default."
        did=1
      fi

      if [[ -e $STATE/trial ]]; then
        systemctl stop trial-reboot.timer 2>/dev/null || true
        # Drop the pin on the old entry: the boot loader's own default is this system.
        bootctl set-default ""
        [[ -z "$(loader_var LoaderEntryDefault)" ]] || die "could not clear the pinned default entry"
        rm -f "$STATE/trial"
        echo "Confirmed: the trial system is now the boot default."
        did=1
      fi

      [[ $did -eq 1 ]] || echo "Nothing is waiting for confirmation."
    '';
  };

  trialMinutes = config.safeRebuild.trialMinutes;
in
{
  options.safeRebuild.trialMinutes = lib.mkOption {
    type = lib.types.ints.positive;
    default = 10;
    description = "How long a trial boot waits for safe-confirm before rebooting back.";
  };

  config = {
    environment.systemPackages = [
      safe-switch
      safe-confirm
      trial-boot
    ];

    # ── Trial-boot watch ────────────────────────────────────────────────
    # At every boot: if the running entry is not the pinned default, this is a
    # trial. Reboot back to the default unless `safe-confirm` is run in time.
    systemd.services.trial-boot-watch = {
      description = "Reboot out of an unconfirmed trial boot";
      wantedBy = [ "multi-user.target" ];
      path = runtimeInputs;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${common}
        selected="$(loader_var LoaderEntrySelected)"
        pinned="$(loader_var LoaderEntryDefault)"
        if [[ -n $pinned && -n $selected && $selected != "$pinned" ]]; then
          mkdir -p "$STATE"
          echo "$selected" > "$STATE/trial"
          echo "trial boot of $selected: rebooting into $pinned in ${toString trialMinutes} minutes unless safe-confirm is run"
          systemd-run --quiet --collect --unit=trial-reboot \
            --on-active=${toString trialMinutes}m --timer-property=AccuracySec=1s \
            systemctl reboot
        fi
      '';
    };

    assertions = [
      {
        assertion = config.boot.loader.systemd-boot.enable;
        message = "safe-rebuild: trial-boot needs systemd-boot.";
      }
      {
        assertion = lib.hasPrefix "/" flakeDir;
        message = "safe-rebuild: lifeline.flakeDir must be an absolute path.";
      }
    ];
  };
}
