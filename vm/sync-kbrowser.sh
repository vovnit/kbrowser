#!/bin/sh
# Dev loop: push package/, rootfs/, extension/ (+ out/kview) into the RUNNING VM without
# rebuilding the image. The browser must not be running (the image gets mounted).
set -eu
cd "$(dirname "$0")/.."
S=vm/ssh.sh
$S 'sh /mnt/us/kmc/kpm/packages/kbrowser/kbrowser.sh stop >/dev/null 2>&1; true'
tar -C package -cf - . | $S 'tar -C /mnt/us/kmc/kpm/packages/kbrowser -xf - 2>/dev/null; true'
$S 'M=/var/tmp/kbrowser-sync; mkdir -p $M; mount -o loop -t ext3 /mnt/us/kbrowser/kbrowser.ext3 $M'
tar -C rootfs -cf - . | $S 'tar -C /var/tmp/kbrowser-sync --no-same-owner -xf -'
(cd extension && tar -cf - .) | $S 'M=/var/tmp/kbrowser-sync; rm -rf $M/opt/kbrowser/touchkit; mkdir -p $M/opt/kbrowser/touchkit; tar -C $M/opt/kbrowser/touchkit --no-same-owner -xf -'
# kview: built by ./build.sh kview (out/kview); copied if present.
if [ -f out/kview ]; then $S 'cat > /var/tmp/kbrowser-sync/usr/local/bin/kview' < out/kview; fi
(cd extension && zip -q -r -X - .) | $S 'cat > /var/tmp/kbrowser-sync/opt/kbrowser/touchkit.xpi; chmod 755 /var/tmp/kbrowser-sync/usr/local/bin/*; umount /var/tmp/kbrowser-sync && echo synced'
