#!/bin/sh
# Boots the Kindle-like VM.
#
#   vm/run.sh            QEMU window + ssh on 2222
#   vm/run.sh --headless no window
#
# The Kindle-like screen (8-bit X, like the device) is at vnc://localhost:5910 -
# open it with macOS Screen Sharing (clicks = taps). The QEMU window only shows
# it when the VM runs KINDLE_DEPTH=24 (edit /etc/conf.d/kindle-x in the VM).
#
# Env knobs:
#   KVM_MEM=1024    RAM in MB given to QEMU. The Paperwhite 2024 (12th gen) has
#                   1 GB; use KVM_MEM=496 to mimic a 512 MB PW5 (~474 MB MemTotal).
#   KVM_SMP=2       Paperwhite 2024: dual-core MediaTek @ ~1 GHz
#   KVM_CPU=cortex-a7
#   KVM_ICOUNT=     e.g. "shift=2" to slow the emulated CPU down deterministically
set -eu
cd "$(dirname "$0")"
OUT=out
MEM="${KVM_MEM:-1024}"
SMP="${KVM_SMP:-2}"
CPU="${KVM_CPU:-cortex-a7}"

DISPLAY_ARGS="-display cocoa,show-cursor=on"
[ "${1:-}" = "--headless" ] && DISPLAY_ARGS="-display none"

ACCEL="-accel tcg,thread=multi,tb-size=256"
[ -n "${KVM_ICOUNT:-}" ] && ACCEL="-accel tcg -icount ${KVM_ICOUNT}"

# Alpine armv7 kernels have no generic PCI host driver -> virtio-mmio devices only.
exec qemu-system-arm \
  -M virt,highmem=off -global virtio-mmio.force-legacy=false -cpu "$CPU" -smp "$SMP" -m "$MEM" $ACCEL \
  -kernel $OUT/vmlinuz -initrd $OUT/initramfs \
  -append "root=LABEL=kindle-root rootfstype=ext4 modules=virtio_mmio,virtio_blk,ext4 rw console=ttyAMA0 quiet" \
  -drive if=none,id=root,file=$OUT/host.img,format=raw,cache=unsafe -device virtio-blk-device,drive=root \
  -drive if=none,id=us,file=$OUT/userstore.img,format=raw,cache=writeback -device virtio-blk-device,drive=us \
  -device virtio-gpu-device,xres=1272,yres=1696 \
  -device virtio-tablet-device -device virtio-keyboard-device \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:5910-:5900 -device virtio-net-device,netdev=n0 \
  -device virtio-rng-device \
  -vnc 127.0.0.1:5 \
  -monitor unix:$OUT/monitor.sock,server,nowait \
  -chardev socket,id=ser,path=$OUT/serial.sock,server=on,wait=off,logfile=$OUT/serial.log -serial chardev:ser \
  $DISPLAY_ARGS
