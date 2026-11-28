#!/usr/bin/env bash
# ── VM harness ────────────────────────────────────────────────────────
# Runs a QEMU guest on a Mac for testing the NixOS hosts in this repo.
# No Nix is needed on the Mac: everything Nix happens inside the guest.
#
#   vm.sh start <aarch64|x86_64> [--iso]   boot the guest (with the installer attached)
#   vm.sh stop  <arch>                     power the guest off
#   vm.sh wait-serial <arch> <regex> [s] [from]   wait for text on the serial console
#                                          (from: byte offset in the log to start at)
#   vm.sh send  <arch> <text>              type a line on the serial console
#   vm.sh ssh   <arch> <user> [cmd...]     ssh into the guest (port-forwarded)
#   vm.sh kill  <arch>                     power off with no clean shutdown
#   vm.sh reset <arch>                     delete the guest's disk and firmware state
#
# State lives in $VM_DIR (default: ./.vm next to this script, git-ignored).
# The installer images are expected there as nixos-<arch>.iso.
set -euo pipefail

VM_DIR="${VM_DIR:-$(cd "$(dirname "$0")" && pwd)/.vm}"
FW_DIR="${FW_DIR:-$(dirname "$(dirname "$(command -v qemu-system-aarch64)")")/share/qemu}"

cmd="${1:-}"
arch="${2:-}"
[[ -n $cmd && -n $arch ]] || { sed -n '2,15p' "$0"; exit 2; }
shift 2

case "$arch" in
  aarch64) port=2222 ;;
  x86_64) port=2223 ;;
  *) echo "unknown arch: $arch" >&2; exit 2 ;;
esac

dir="$VM_DIR/$arch"
mkdir -p "$dir"
# Relative paths from here on: a UNIX socket path is limited to 104 bytes.
cd "$dir"
disk=disk.qcow2
vars=vars.fd
serial_sock=serial.sock
serial_log=serial.log
monitor=monitor.sock
pidfile=qemu.pid

running() { [[ -s $pidfile ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; }

case "$cmd" in
  start)
    running && { echo "already running" >&2; exit 1; }
    [[ -e $disk ]] || qemu-img create -q -f qcow2 "$disk" 40G
    args=()
    if [[ $arch == aarch64 ]]; then
      [[ -e $vars ]] || cp "$FW_DIR/edk2-arm-vars.fd" "$vars"
      args+=(qemu-system-aarch64 -machine virt,accel=hvf -cpu host
        -drive "if=pflash,format=raw,readonly=on,file=$FW_DIR/edk2-aarch64-code.fd")
    else
      [[ -e $vars ]] || cp "$FW_DIR/edk2-i386-vars.fd" "$vars"
      args+=(qemu-system-x86_64 -machine q35,accel=tcg -cpu max
        -device i6300esb
        -drive "if=pflash,format=raw,readonly=on,file=$FW_DIR/edk2-x86_64-code.fd")
    fi
    args+=(-smp 6 -m 8G
      -drive "if=pflash,format=raw,file=$vars"
      -drive "file=$disk,if=none,id=nvm,format=qcow2"
      -device nvme,serial=TESTNVME0001,drive=nvm,bootindex=1
      -device qemu-xhci
      -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$port-:22"
      -device virtio-net-pci,netdev=n0
      -device virtio-rng-pci
      -chardev "socket,id=ser,path=$serial_sock,server=on,wait=off,logfile=$serial_log,logappend=on"
      -serial chardev:ser
      -monitor "unix:$monitor,server,nowait"
      -display none -pidfile "$pidfile" -daemonize)
    if [[ "${1:-}" == --iso ]]; then
      args+=(-drive "file=$VM_DIR/nixos-$arch.iso,if=none,id=stick,format=raw,readonly=on"
        -device usb-storage,drive=stick,bootindex=0)
    fi
    "${args[@]}"
    echo "started $arch (ssh port $port, serial log $dir/$serial_log)"
    ;;
  stop)
    if running; then
      echo system_powerdown | nc -U "$monitor" >/dev/null 2>&1 || true
      for _ in $(seq 60); do running || break; sleep 1; done
      if running; then kill "$(cat "$pidfile")"; fi
    fi
    rm -f "$pidfile"
    ;;
  kill)
    # Pull the plug: no clean shutdown.
    if running; then kill -9 "$(cat "$pidfile")"; fi
    rm -f "$pidfile"
    ;;
  wait-serial)
    pattern="$1"
    timeout="${2:-300}"
    from="${3:-1}"
    for _ in $(seq "$timeout"); do
      if tail -c "+$from" "$serial_log" 2>/dev/null | LC_ALL=C grep -aEq "$pattern"; then exit 0; fi
      sleep 1
    done
    echo "timed out waiting for /$pattern/ on the serial console" >&2
    exit 1
    ;;
  send)
    python3 - "$serial_sock" "$1" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
s.sendall(sys.argv[2].encode() + b"\n")
time.sleep(0.5)
s.close()
PY
    ;;
  ssh)
    user="$1"
    shift
    exec ssh -p "$port" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR -o ConnectTimeout=10 -o ControlPath=none -o BatchMode=yes \
      "$user@127.0.0.1" "$@"
    ;;
  reset)
    running && { echo "stop it first" >&2; exit 1; }
    rm -rf "$dir"
    ;;
  *)
    echo "unknown command: $cmd" >&2
    exit 2
    ;;
esac
