#!/bin/bash
# NekoSoft - test ISO en live + install (disque vierge 20 Go, SSH host:2223)
cd "$(dirname "$0")"
exec qemu-system-x86_64 \
  -enable-kvm -cpu host -smp 2 -m 4G \
  -machine q35 \
  -drive file=nekosoft-test.img,format=qcow2,if=virtio \
  -drive file=nekosoft-12.0-amd64.iso,media=cdrom,if=none,id=cd0 \
  -device ich9-ahci,id=ahci \
  -device ide-cd,bus=ahci.0,drive=cd0 \
  -boot order=d,menu=on \
  -netdev user,id=net0,hostfwd=tcp::2223-:22 \
  -device virtio-net-pci,netdev=net0 \
  -display gtk
