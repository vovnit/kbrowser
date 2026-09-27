#!/bin/sh
# Builds the Kindle-like QEMU VM (kernel, root disk, FAT32 userstore) in vm/out/.
# Needs Docker with linux/arm/v7 emulation (OrbStack / Docker Desktop both work).
set -eu
cd "$(dirname "$0")/.."
mkdir -p vm/out
[ -f vm/out/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -C kindle-vm -f vm/out/id_ed25519
docker run --rm --platform linux/arm/v7 \
  -e ALPINE_BRANCH -e HOST_SIZE_MB -e USERSTORE_SIZE_MB -e REBUILD_USERSTORE \
  -v "$PWD:/work:ro" -v "$PWD/vm/out:/out" \
  alpine:3.23 sh /work/vm/container/build-host.sh
