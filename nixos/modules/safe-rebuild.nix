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
    pkgs.gawk
    pkgs.gnugrep
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
      for part in kernel initrd kernel-modules firmware; do
        if [[ "$(readlink -f "$new/$part")" != "$(readlink -f "/run/booted-system/$part")" ]]; then
          return 0
        fi
      done
      if ! cmp -s "$new/kernel-params" /run/booted-system/kernel-params; then
        return 0
      fi
      if ! cmp -s "$new/etc/fstab" /run/booted-system/etc/fstab; then
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
      # From here on there is nothing left to confirm.
      rm -f "$STATE/pending"
      if ! "$old/bin/switch-to-configuration" test; then
        echo "safe-rollback: restoring failed, rebooting into the boot default"
        systemctl reboot
        exit 0
      fi
      # Logins from here on count as proof the restore worked.
      restored_at="$(date +%s)"
      sleep 5
      for unit in sshd.service tailscaled.service NetworkManager.service; do
        if ! systemctl is-active --quiet "$unit"; then
          echo "safe-rollback: $unit is not running after the restore, rebooting"
          systemctl reboot
          exit 0
        fi
      done
      echo "safe-rollback: restored"

      # Restoring in place can leave state behind (a stray firewall rule, say).
      # The only proof it worked is someone getting in: if no new login shows
      # up in time, reboot into the boot default, which is the old system.
      deadline=$(( SECONDS + ${toString (graceMinutes * 60)} ))
      while (( SECONDS < deadline )); do
        # A command run over SSH is a session that lasts milliseconds, so look
        # at what the login manager logged rather than at who is logged in now.
        if journalctl -t systemd-logind --since "@$restored_at" --no-pager -o cat 2>/dev/null \
          | grep "New session .* with class 'user'" | grep -qv "of user 'root'"; then
          echo "safe-rollback: a new login arrived after the restore; staying up"
          exit 0
        fi
        sleep 5
      done
      echo "safe-rollback: nobody could log in after the restore, rebooting into the boot default"
      systemctl reboot
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
      if systemctl is-active --quiet safe-rollback.service; then
        die "a rollback is running right now. Wait for it to finish, then check with host-check."
      fi
      echo "$old" > "$STATE/old"
      echo "$new" > "$STATE/new"
      date +%s > "$STATE/armed"

      systemctl stop safe-rollback.timer safe-rollback.service 2>/dev/null || true
      systemctl reset-failed safe-rollback.service safe-activate.service 2>/dev/null || true
      # Arm first, mark second: a failed arm must not leave a pending marker,
      # which would switch off lifeline-watchdog.
      if ! systemd-run --quiet --collect --unit=safe-rollback \
        --on-active="''${minutes}m" --timer-property=AccuracySec=1s \
        ${safe-rollback}/bin/safe-rollback; then
        die "could not arm the rollback; nothing was activated"
      fi
      touch "$STATE/pending"

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
      if ! [[ $minutes =~ ^[1-9][0-9]?$ ]] || (( minutes > 30 )); then
        die "usage: safe-switch [minutes 1-30]"
      fi
      new="$(build_system)"
      if needs_reboot "$new"; then
        die "this change touches the kernel, initrd, kernel modules, firmware, kernel parameters or fstab, which only a reboot applies. Use: trial-boot"
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
      if systemctl is-active --quiet safe-rollback.service; then
        die "a rollback is running right now. Wait for it to finish, then check with host-check."
      fi
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

  # What the trial timer runs when a trial is not confirmed in time: make the
  # on-disk defaults match the old system again, then reboot into it. (Covers
  # firmware that drops the pinned EFI variable.)
  trial-revert = pkgs.writeShellApplication {
    name = "trial-revert";
    inherit runtimeInputs;
    text = ''
      ${common}
      pinned="$(loader_var LoaderEntryDefault)"
      if [[ $pinned =~ ^nixos-generation-([0-9]+)\.conf$ ]]; then
        gen="''${BASH_REMATCH[1]}"
        old="$(readlink -f "/nix/var/nix/profiles/system-$gen-link" || true)"
        if [[ -x $old/bin/switch-to-configuration ]]; then
          timeout 60 nix-env -p /nix/var/nix/profiles/system --set "$old" || true
          timeout 300 "$old/bin/switch-to-configuration" boot || true
        fi
      fi
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
        local armed="$1" pid=$$ comm age change_age sid started started_s
        [[ $force -eq 0 ]] || return 0
        change_age=$(( $(date +%s) - armed ))
        while [[ $pid -gt 1 ]]; do
          comm="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
          if [[ $comm == sshd* ]]; then
            # Seconds since this SSH connection's process started.
            age="$(ps -o etimes= -p "$pid" | tr -d ' ')"
            if (( age >= change_age )); then
              die "this SSH session is older than the change. Open a NEW session (ssh -o ControlPath=none ...) and run safe-confirm there."
            fi
            return 0
          fi
          pid="$(ps -o ppid= -p "$pid" | tr -d ' ')"
          [[ -n $pid ]] || break
        done
        # No sshd above us (a Tailscale SSH or console login): ask logind when
        # this login began. If that cannot be told, refuse rather than guess.
        sid="$(cat /proc/$$/sessionid 2>/dev/null || true)"
        if [[ $sid =~ ^[0-9]+$ ]]; then
          started="$(loginctl show-session "$sid" -p Timestamp --value 2>/dev/null || true)"
          started_s="$(date -d "$started" +%s 2>/dev/null || true)"
          if [[ -n $started_s ]]; then
            if (( started_s <= armed )); then
              die "this login is older than the change. Open a NEW session and run safe-confirm there."
            fi
            return 0
          fi
        fi
        die "cannot tell when this login began (it is not an OpenSSH session). Open a NEW session with: ssh -p 2222 ... and run safe-confirm there (or use: safe-confirm --force)."
      }

      # A rollback that has already started must finish; confirming now would
      # make the boot default a system that is being undone.
      if systemctl is-active --quiet safe-rollback.service; then
        die "a rollback is running right now. Wait for it to finish, then check with host-check."
      fi

      did=0

      if [[ -e $STATE/pending ]]; then
        require_new_session "$(cat "$STATE/armed")"
        systemctl stop safe-rollback.timer 2>/dev/null || true
        if systemctl is-active --quiet safe-rollback.service; then
          die "a rollback is running right now. Wait for it to finish, then check with host-check."
        fi
        new="$(cat "$STATE/new")"
        if [[ "$(readlink -f /run/current-system)" != "$new" ]]; then
          rm -f "$STATE/pending"
          die "the pending change is no longer running (it was rolled back). Nothing confirmed."
        fi
        # Nothing may stay half done with the rollback disarmed: if making the
        # change the boot default fails, put the profile back and re-arm.
        if ! { nix-env -p /nix/var/nix/profiles/system --set "$new" \
          && "$new/bin/switch-to-configuration" boot; }; then
          nix-env -p /nix/var/nix/profiles/system --set "$(cat "$STATE/old")" || true
          timeout 300 "$(cat "$STATE/old")/bin/switch-to-configuration" boot || true
          systemd-run --quiet --collect --unit=safe-rollback \
            --on-active=2m --timer-property=AccuracySec=1s \
            ${safe-rollback}/bin/safe-rollback || true
          die "could not make the change the boot default. The rollback is re-armed for 2 minutes."
        fi
        bootctl set-default "" 2>/dev/null || true
        rm -f "$STATE/pending"
        if [[ -n "$(loader_var LoaderEntryDefault)" ]]; then
          die "the change is now the profile default, but an old entry is still pinned and the next reboot will boot it. Run: sudo bootctl set-default \"\"  then check with host-check."
        fi
        echo "Confirmed: this configuration is now the boot default."
        did=1
      fi

      if [[ -e $STATE/trial ]]; then
        if systemctl is-active --quiet trial-reboot.service; then
          die "the trial is being reverted right now; wait for the reboot, then check with host-check."
        fi
        # Drop the pin on the old entry: the boot loader's own default is this
        # system.
        bootctl set-default "" || true
        [[ -z "$(loader_var LoaderEntryDefault)" ]] || die "could not clear the pinned default entry; the trial revert is still armed"
        systemctl stop trial-reboot.timer 2>/dev/null || true
        rm -f "$STATE/trial"
        echo "Confirmed: the trial system is now the boot default."
        did=1
      fi

      [[ $did -eq 1 ]] || echo "Nothing is waiting for confirmation."
    '';
  };

  trialMinutes = config.safeRebuild.trialMinutes;
  graceMinutes = config.safeRebuild.graceMinutes;
in
{
  options.safeRebuild.graceMinutes = lib.mkOption {
    type = lib.types.ints.positive;
    default = 3;
    description = "After an automatic rollback, how long to wait for a new login before rebooting.";
  };
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
    # It starts in sysinit, not multi-user: a trial that never finishes booting
    # (a failed unit or mount) must still be reverted.
    systemd.services.trial-boot-watch = {
      description = "Reboot out of an unconfirmed trial boot";
      wantedBy = [ "sysinit.target" ];
      wants = [ "sys-firmware-efi-efivars.mount" ];
      after = [ "sys-firmware-efi-efivars.mount" ];
      before = [ "shutdown.target" ];
      conflicts = [ "shutdown.target" ];
      unitConfig.DefaultDependencies = false;
      path = runtimeInputs;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${common}
        selected="$(loader_var LoaderEntrySelected)"
        pinned="$(loader_var LoaderEntryDefault)"
        if [[ -n $pinned && -z $selected ]]; then
          echo "trial-boot-watch: WARNING: the running entry cannot be read but a default is pinned; treating this boot as a trial" >&2
        fi
        if [[ -n $pinned && $selected != "$pinned" ]]; then
          mkdir -p "$STATE"
          # --no-block and DefaultDependencies=no, because this runs in sysinit.
          if systemd-run --quiet --no-block --collect --unit=trial-reboot \
            --on-active=${toString trialMinutes}m --timer-property=AccuracySec=1s \
            --timer-property=DefaultDependencies=no --property=DefaultDependencies=no \
            ${trial-revert}/bin/trial-revert; then
            echo "''${selected:-unknown}" > "$STATE/trial"
            echo "trial boot of ''${selected:-unknown}: rebooting into $pinned in ${toString trialMinutes} minutes unless safe-confirm is run"
          else
            echo "trial-boot-watch: ERROR: could not arm the trial revert; no trial marker written" >&2
          fi
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
