#!/bin/sh
# Build kbrowser. Needs Docker with linux/arm/v7 emulation (OrbStack or Docker Desktop).
#
#   ./build.sh            browser image (out/kbrowser.ext3) + KPM package (out/*.kpkg)
#   ./build.sh package    KPM package only (fast; launcher/config changes)
#   ./build.sh kview      out/kview binary only (for vm/sync-kbrowser.sh)
#
#   BROWSERS="chromium" ./build.sh     one browser only (image about half the size)
#   BROWSERS="chromium firefox"        default: both
set -eu
cd "$(dirname "$0")"
mkdir -p out

build_package() {
  V="$(python3 -c 'import json;print(".".join(map(str,json.load(open("package/manifest.json"))["version"])))')"
  rm -f out/kbrowser_*.kpkg
  # A KPM package is a gzip'd tar of the package dir (manifest v2: what KPM <= 0.2.x accepts).
  tar -C package -czf "out/kbrowser_${V}_kindlehf.kpkg" manifest.json install.sh uninstall.sh launch.sh kbrowser.sh kbrowser.conf
  echo "out/kbrowser_${V}_kindlehf.kpkg"
}

case "${1:-all}" in
  package) build_package ;;
  kview)
    docker run --rm --platform linux/arm/v7 -v "$PWD:/work" alpine:3.23 sh -c \
      'apk add -q build-base libx11-dev libxext-dev libxdamage-dev libxfixes-dev libxtst-dev >/dev/null &&
       gcc -O2 -Wall -Wextra -s -o /work/out/kview /work/kview/kview.c -lX11 -lXext -lXdamage -lXfixes -lXtst'
    echo out/kview ;;
  all)
    docker run --rm --platform linux/arm/v7 -e BROWSERS -e ALPINE_BRANCH -e IMAGE_SIZE_MB -e EXTRA_PKGS \
      -v "$PWD:/work:ro" -v "$PWD/out:/out" alpine:3.23 sh /work/container/build-rootfs.sh
    build_package
    ls -la out ;;
  *) echo "usage: $0 [all|package|kview]"; exit 2 ;;
esac
