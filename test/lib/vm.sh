# shellcheck shell=bash
# ── QEMU harness for test/suite.sh ──────────────────────────────────────────
# Sourced, not run. Boots a fresh Ubuntu cloud image (a qcow2 overlay on a
# cached, checksum-verified base image) with a cloud-init NoCloud seed, and
# talks to it over SSH on a forwarded localhost port. Nothing on the host
# filesystem is shared with the guest.
#
# Every function that can fail because the environment could not be started
# (download, checksum, QEMU, SSH never answering) returns 3.

VM_RELEASE="${DOTFILES_TEST_RELEASE:-26.04}"
VM_BASE_URL="https://cloud-images.ubuntu.com/releases/$VM_RELEASE/release"
VM_CACHE="${DOTFILES_TEST_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-test}"
VM_USER="dot"

vm_log() { printf '[vm %s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# ── architecture ─────────────────────────────────────────────────────────────
# Ubuntu image arch names: arm64, amd64.
vm_host_arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo arm64 ;;
    x86_64|amd64)  echo amd64 ;;
    *) vm_log "unsupported host architecture $(uname -m)"; return 3 ;;
  esac
}
vm_other_arch() { [[ "$(vm_host_arch)" == arm64 ]] && echo amd64 || echo arm64; }

vm_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# ── image cache ──────────────────────────────────────────────────────────────
# Prints the path of the verified base image for $1 (arm64|amd64).
vm_image() {
  local arch="$1" name sums want img
  name="ubuntu-$VM_RELEASE-server-cloudimg-$arch.img"
  img="$VM_CACHE/$name"
  mkdir -p "$VM_CACHE" || return 3
  sums="$VM_CACHE/SHA256SUMS"
  if ! curl -fsSL --retry 3 -o "$sums.new" "$VM_BASE_URL/SHA256SUMS"; then
    [[ -s "$sums" ]] || { vm_log "cannot fetch $VM_BASE_URL/SHA256SUMS"; return 3; }
    vm_log "SHA256SUMS unreachable; using the cached copy"
  else mv "$sums.new" "$sums"; fi
  want="$(awk -v n="*$name" '$2 == n {print $1}' "$sums")"
  [[ -n "$want" ]] || { vm_log "$name is not listed in SHA256SUMS"; return 3; }
  if [[ -f "$img" && -f "$img.sha256" && "$(cat "$img.sha256")" == "$want" ]]; then
    echo "$img"; return 0
  fi
  vm_log "downloading $name (once; cached in $VM_CACHE)"
  # Resume after a stall (no progress for a minute) instead of hanging on it.
  local try
  for try in 1 2 3 4 5 6 7 8; do
    curl -fsSL -C - --speed-limit 10240 --speed-time 60 -o "$img.part" "$VM_BASE_URL/$name" && break
    vm_log "download interrupted (attempt $try); resuming"; sleep 5
    [[ $try == 8 ]] && { vm_log "download failed"; return 3; }
  done
  if [[ "$(vm_sha256 "$img.part")" != "$want" ]]; then
    rm -f "$img.part"; vm_log "$name failed its checksum"; return 3
  fi
  mv "$img.part" "$img"; echo "$want" > "$img.sha256"
  echo "$img"
}

# ── firmware ─────────────────────────────────────────────────────────────────
vm_qemu_share() {
  local d
  for d in "${DOTFILES_TEST_QEMU_SHARE:-}" \
           "$(command -v brew >/dev/null 2>&1 && brew --prefix)/share/qemu" \
           /usr/share/qemu /usr/share/AAVMF /usr/share/OVMF /usr/local/share/qemu; do
    [[ -n "$d" && -d "$d" ]] && echo "$d"
  done
}
# Prints "code vars" firmware paths for $1.
vm_firmware() {
  local arch="$1" d code vars
  while IFS= read -r d; do
    if [[ "$arch" == arm64 ]]; then
      for code in "$d/edk2-aarch64-code.fd" "$d/AAVMF_CODE.fd"; do [[ -f "$code" ]] && break; code=""; done
      for vars in "$d/edk2-arm-vars.fd" "$d/AAVMF_VARS.fd"; do [[ -f "$vars" ]] && break; vars=""; done
    else
      for code in "$d/edk2-x86_64-code.fd" "$d/OVMF_CODE.fd" "$d/OVMF_CODE_4M.fd"; do [[ -f "$code" ]] && break; code=""; done
      for vars in "$d/edk2-i386-vars.fd" "$d/OVMF_VARS.fd" "$d/OVMF_VARS_4M.fd"; do [[ -f "$vars" ]] && break; vars=""; done
    fi
    if [[ -n "$code" && -n "$vars" ]]; then echo "$code $vars"; return 0; fi
  done < <(vm_qemu_share)
  vm_log "no UEFI firmware for $arch found"; return 3
}

# ── seed ─────────────────────────────────────────────────────────────────────
# cloud-init NoCloud seed: one user, passwordless sudo, this run's SSH key.
vm_seed() {
  local dir="$1" pub
  pub="$(cat "$dir/id_ed25519.pub")"
  mkdir -p "$dir/seed"
  cat > "$dir/seed/meta-data" <<EOF
instance-id: dotfiles-test-$(basename "$dir")
local-hostname: dotfiles-test
EOF
  cat > "$dir/seed/user-data" <<EOF
#cloud-config
users:
  - name: $VM_USER
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - $pub
ssh_pwauth: false
package_update: false
package_upgrade: false
growpart: {mode: auto, devices: ['/']}
EOF
  rm -f "$dir/seed.iso"
  if command -v hdiutil >/dev/null 2>&1; then
    hdiutil makehybrid -quiet -iso -joliet -default-volume-name cidata -o "$dir/seed.iso" "$dir/seed" >&2
  elif command -v cloud-localds >/dev/null 2>&1; then
    cloud-localds "$dir/seed.iso" "$dir/seed/user-data" "$dir/seed/meta-data"
  elif command -v genisoimage >/dev/null 2>&1; then
    genisoimage -quiet -output "$dir/seed.iso" -volid cidata -joliet -rock "$dir/seed/user-data" "$dir/seed/meta-data"
  elif command -v xorriso >/dev/null 2>&1; then
    xorriso -as mkisofs -quiet -output "$dir/seed.iso" -volid cidata -joliet -rock "$dir/seed/user-data" "$dir/seed/meta-data"
  else vm_log "no ISO tool (hdiutil, cloud-localds, genisoimage, xorriso)"; return 3; fi
  [[ -s "$dir/seed.iso" ]] || { vm_log "seed ISO was not created"; return 3; }
}

vm_free_port() {
  /usr/bin/env python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'
}

# ── boot ─────────────────────────────────────────────────────────────────────
# vm_create <run-dir> <arch>: fresh overlay, firmware vars, seed and SSH key.
vm_create() {
  local dir="$1" arch="$2" base fw
  base="$(vm_image "$arch")" || return 3
  fw="$(vm_firmware "$arch")" || return 3
  echo "$arch" > "$dir/arch"
  ssh-keygen -q -t ed25519 -N '' -C dotfiles-test -f "$dir/id_ed25519" || return 3
  qemu-img create -q -f qcow2 -F qcow2 -b "$base" "$dir/overlay.qcow2" "${DOTFILES_TEST_DISK:-20G}" || return 3
  cp "${fw#* }" "$dir/vars.fd" || return 3
  vm_seed "$dir" || return 3
}

# vm_start <run-dir> <accel: native|tcg>
vm_start() {
  local dir="$1" mode="$2" arch fw code qemu accel cpu machine port
  arch="$(cat "$dir/arch")"
  fw="$(vm_firmware "$arch")" || return 3; code="${fw% *}"
  if [[ "$mode" == native ]]; then
    if [[ "$(uname)" == Darwin ]]; then accel=hvf
    elif [[ -w /dev/kvm ]]; then accel=kvm
    else vm_log "no hardware acceleration (/dev/kvm not writable)"; return 3; fi
    cpu=host
  else accel="tcg,thread=multi,tb-size=512"; cpu=max; fi
  if [[ "$arch" == arm64 ]]; then qemu=qemu-system-aarch64; machine="virt"
  else qemu=qemu-system-x86_64; machine="q35"; fi
  command -v "$qemu" >/dev/null 2>&1 || { vm_log "$qemu not installed"; return 3; }
  port="$(vm_free_port)" || return 3
  echo "$port" > "$dir/port"
  vm_log "booting $arch guest ($accel), ssh on 127.0.0.1:$port"
  "$qemu" -name dotfiles-test -machine "$machine" -accel "$accel" -cpu "$cpu" \
    -smp "${DOTFILES_TEST_CPUS:-4}" -m "${DOTFILES_TEST_MEM:-4096}" \
    -drive "if=pflash,format=raw,readonly=on,file=$code" \
    -drive "if=pflash,format=raw,file=$dir/vars.fd" \
    -drive "if=virtio,format=qcow2,file=$dir/overlay.qcow2" \
    -drive "if=virtio,format=raw,readonly=on,file=$dir/seed.iso" \
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$port-:22" -device virtio-net-pci,netdev=n0 \
    -device virtio-rng-pci \
    -display none -serial "file:$dir/console.log" -monitor none \
    -daemonize -pidfile "$dir/qemu.pid" || { vm_log "qemu failed to start"; return 3; }
}

vm_ssh() {
  local dir="$1"; shift
  # Only this run's key: an ssh-agent offering its own keys first can exhaust the
  # guest's MaxAuthTries ("Too many authentication failures").
  ssh -i "$dir/id_ed25519" -p "$(cat "$dir/port")" -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o IdentitiesOnly=yes -o IdentityAgent=none \
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10 \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=20 "$VM_USER@127.0.0.1" "$@"
}

vm_alive() { [[ -f "$1/qemu.pid" ]] && kill -0 "$(cat "$1/qemu.pid")" 2>/dev/null; }

# vm_wait <run-dir> <timeout-seconds>: SSH answers and cloud-init has finished.
vm_wait() {
  local dir="$1" timeout="$2" start=$SECONDS
  until vm_ssh "$dir" true 2>/dev/null; do
    vm_alive "$dir" || { vm_log "qemu exited during boot (see console.log)"; return 3; }
    (( SECONDS - start > timeout )) && { vm_log "guest not reachable after ${timeout}s"; return 3; }
    sleep 5
  done
  vm_log "ssh up after $((SECONDS - start))s; waiting for cloud-init"
  vm_ssh "$dir" 'cloud-init status --wait >/dev/null 2>&1; cloud-init status' >&2 || true
}

# vm_stop <run-dir>: power off, then make sure qemu is gone.
vm_stop() {
  local dir="$1" pid i
  [[ -f "$dir/qemu.pid" ]] || return 0
  pid="$(cat "$dir/qemu.pid")"
  if kill -0 "$pid" 2>/dev/null; then
    vm_ssh "$dir" 'sudo systemctl poweroff' >/dev/null 2>&1 || true
    for i in $(seq 1 60); do kill -0 "$pid" 2>/dev/null || break; sleep 2; done
    kill -0 "$pid" 2>/dev/null && { vm_log "guest did not power off; killing qemu"; kill "$pid" 2>/dev/null; sleep 2; kill -9 "$pid" 2>/dev/null; }
  fi
  rm -f "$dir/qemu.pid"
  vm_log "guest stopped"
}
