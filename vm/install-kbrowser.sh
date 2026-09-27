#!/bin/sh
# Copies the kbrowser image + KPM package into the VM's /mnt/us (VM must be OFF),
# laid out like KPM would install it on the Kindle.
set -eu
cd "$(dirname "$0")/.."
docker run --rm -v "$PWD:/w" alpine:3.23 sh -c '
  apk add -q mtools >/dev/null; export MTOOLS_SKIP_CHECK=1; U=/w/vm/out/userstore.img
  mmd -i $U ::/kbrowser ::/kmc/kpm ::/kmc/kpm/packages ::/kmc/kpm/packages/kbrowser 2>/dev/null || true
  mcopy -o -i $U /w/out/kbrowser.ext3 ::/kbrowser/kbrowser.ext3
  mcopy -o -i $U /w/package/* ::/kmc/kpm/packages/kbrowser/
  mdir -i $U ::/kbrowser ::/kmc/kpm/packages/kbrowser'
echo "Now boot the VM and run: sh -c 'cd /mnt/us/kmc/kpm/packages/kbrowser && sh install.sh'"
