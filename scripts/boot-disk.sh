#!/bin/bash
# Boot disque installé (après installation : sans ISO, disque en premier)
cd "$(dirname "$0")"
exec qemu-system-x86_64 \
  -enable-kvm -cpu host -smp 2 -m 4G \
  -machine q35 \
  -drive file=trisquel-disk.img,format=qcow2,if=virtio \
  -boot order=c,menu=on \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -display gtk
