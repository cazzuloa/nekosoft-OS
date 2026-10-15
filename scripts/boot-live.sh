#!/bin/bash
# NekoSoft - boot live ISO (2 CPU / 4 Go / CD-ROM prio 1)
cd "$(dirname "$0")"
exec qemu-system-x86_64 \
  -enable-kvm -cpu host -smp 2 -m 4G \
  -machine q35 \
  -drive file=trisquel-disk.img,format=qcow2,if=virtio \
  -drive file=trisquel-mini_12.0_amd64.iso,media=cdrom,if=none,id=cd0 \
  -device ich9-ahci,id=ahci \
  -device ide-cd,bus=ahci.0,drive=cd0 \
  -boot order=d,menu=on \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -display gtk
