# Test VM

A QEMU `virt` armv7 machine set up so kbrowser runs unmodified, as it does on a
Kindle. Everything is built with Docker; nothing needs installing except QEMU
(`brew install qemu`).

```sh
vm/build.sh               # kernel + root disk (Alpine armv7) + FAT32 userstore → vm/out/
./build.sh                # kbrowser image + package → out/
vm/install-kbrowser.sh    # (VM off) copy image + package into the VM's /mnt/us
vm/run.sh --headless      # or without --headless for a QEMU window
vm/ssh.sh                 # root shell (key-only, port 2222)
open vnc://localhost:5910 # the Kindle's 8-bit screen via x11vnc; click = tap
```

Inside the VM, do what KPM and a tap would do:
```sh
cd /mnt/us/kmc/kpm/packages/kbrowser && sh install.sh
sh /mnt/us/documents/kbrowser-chromium.sh
```

## What matches the Kindle and what doesn't

| Kindle PW 2024 | VM |
|---|---|
| armv7/armhf userspace, dual core ~1 GHz | `-cpu cortex-a7 -smp 2`, TCG emulation (speed not calibrated) |
| 1 GB RAM, no swap active (per the device log) | 1 GB (`KVM_MEM`), 128 MB zram. Run `swapoff /dev/zram0` to match the device. |
| Amazon's framework memory | A "ballast" in tmpfs, sized so used RAM is ~235 MB with `lab126_gui` running and ~110 MB when stopped. `initctl stop/start lab126_gui` resizes it. |
| X `:0`, 1272×1696, **8-bit** | Xvfb 1272×1696×8, StaticGray (`KINDLE_DEPTH=24` in `/etc/conf.d/kindle-x` switches to Xorg on virtio-gpu, visible in QEMU's window, but **not** device-like) |
| awesome + `lab126LayerLogic.lua` | awesome with a Lua emulation of the title parser (`vm/overlay/etc/xdg/awesome/rc.lua`), logging to `/var/log/lab126-wm.log` |
| `/mnt/us` FAT32; `/tmp` → `/var/tmp` | FAT32 disk mounted at `/mnt/us` |
| `initctl`, `lipc-get/set-prop`, `eips`, `pillow` | logging stubs (`/var/log/kindle-stubs.log`) |
| touch panel | pointer (VNC or QEMU tablet); no multi-touch |
| e-ink refresh and ghosting | not emulated |
| kernel 4.9 lab126, glibc host | Alpine 6.18 LTS kernel, musl host (the browser runs in its own musl chroot either way) |

## Dev loop

```sh
vm/sync-kbrowser.sh       # push package/, rootfs/, extension/ (+ out/kview) into the running VM's image
./build.sh kview          # rebuild out/kview after changing kview/kview.c, then sync
vm/screenshot.sh out.png 600    # PNG of the Kindle screen (:0), 600 px wide
```

- **Firefox extension updates.** Firefox only reinstalls the force-installed
  Touch Kit when `extension/manifest.json` has a higher `version`, so bump it.
- **Logs.**
  - Session: `/mnt/us/kbrowser/kbrowser.log`.
  - Private display: `/var/tmp/kbrowser/tmp/xvfb.log`.
  - WM decisions: `/var/log/lab126-wm.log`.

### Debugging Chromium with DevTools

```sh
# inside the image (browser not running): enable the remote debugger
vm/ssh.sh 'M=/var/tmp/kb; mkdir -p $M; mount -o loop -t ext3 /mnt/us/kbrowser/kbrowser.ext3 $M &&
  echo "CHROMIUM_FLAGS=\"\$CHROMIUM_FLAGS --remote-debugging-port=9222 --remote-allow-origins=*\"" > $M/etc/chromium/zz-debug.conf; umount $M'
# allow SSH port forwarding in the VM once
vm/ssh.sh 'sed -i "s/^AllowTcpForwarding.*/AllowTcpForwarding yes/" /etc/ssh/sshd_config; rc-service sshd reload'
ssh -f -N -i vm/out/id_ed25519 -p 2222 -o StrictHostKeyChecking=no -L 9222:127.0.0.1:9222 root@127.0.0.1
# then use chrome://inspect on the Mac, or talk CDP to http://127.0.0.1:9222/json
```
Remove `zz-debug.conf` afterwards.

The Touch Kit's extension ID (it's unpacked) is derived from its path:
`printf %s /opt/kbrowser/touchkit | shasum -a 256 | cut -c1-32 | tr 0-9a-f a-p`.
