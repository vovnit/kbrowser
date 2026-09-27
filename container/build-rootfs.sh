#!/bin/sh
# Runs INSIDE an alpine linux/arm/v7 container (see build.sh).
# Builds kbrowser.ext3: a minimal Alpine armv7 root with just a browser (no
# desktop, no WM, no panel), plus the Touch Kit extension and Kindle tuning.
#
#   BROWSERS="firefox chromium"   which browsers to include (either or both)
#   ALPINE_BRANCH=v3.23
set -eu
BROWSERS="${BROWSERS:-firefox chromium}"
ALPINE_BRANCH="${ALPINE_BRANCH:-v3.23}"
MIRROR=https://dl-cdn.alpinelinux.org/alpine
ROOT=/build/kbrowser
OUT=/out

apk add --no-cache e2fsprogs zip curl >/dev/null

PKGS="alpine-baselayout busybox musl-utils apk-tools ca-certificates dbus dbus-x11
  xwininfo xdpyinfo xdotool xprop xorg-server-xephyr xvfb libxdamage libxfixes libxtst
  font-dejavu font-liberation font-noto font-noto-symbols font-noto-emoji fontconfig
  mesa-dri-gallium"
for b in $BROWSERS; do
  case "$b" in
    firefox) PKGS="$PKGS firefox-esr" ;;
    chromium) PKGS="$PKGS chromium" ;;
    *) echo "unknown browser $b"; exit 1 ;;
  esac
done
[ -n "${EXTRA_PKGS:-}" ] && PKGS="$PKGS $EXTRA_PKGS"

rm -rf "$ROOT"; mkdir -p "$ROOT/etc/apk"
printf '%s\n' "$MIRROR/$ALPINE_BRANCH/main" "$MIRROR/$ALPINE_BRANCH/community" > "$ROOT/etc/apk/repositories"
cp -r /etc/apk/keys "$ROOT/etc/apk/"
echo ">> apk add ($BROWSERS)"
# shellcheck disable=SC2086
apk --root "$ROOT" --initdb --update-cache --arch armv7 --no-cache add $PKGS >/dev/null
cp /etc/apk/repositories "$ROOT/etc/apk/repositories.container" 2>/dev/null || true

echo ">> overlay + user"
cp -a /work/rootfs/. "$ROOT/"
chmod +x "$ROOT/usr/local/bin/"*
case " $BROWSERS " in *" firefox "*) ;; *) rm -rf "$ROOT/usr/lib/firefox-esr" ;; esac
case " $BROWSERS " in *" chromium "*) ;; *) rm -rf "$ROOT/etc/chromium" ;; esac
chroot "$ROOT" /bin/sh -c 'adduser -D -u 1000 -h /home/kindle -s /bin/sh kindle 2>/dev/null; fc-cache -f >/dev/null 2>&1; true'

echo ">> kview (24-bit -> Kindle screen bridge)"
apk add --no-cache build-base libx11-dev libxext-dev libxdamage-dev libxfixes-dev libxtst-dev >/dev/null
gcc -O2 -Wall -s -o "$ROOT/usr/local/bin/kview" /work/kview/kview.c -lX11 -lXext -lXdamage -lXfixes -lXtst

echo ">> Touch Kit extension"
mkdir -p "$ROOT/opt/kbrowser/touchkit"
cp -a /work/extension/. "$ROOT/opt/kbrowser/touchkit/"
(cd /work/extension && zip -q -r -X "$ROOT/opt/kbrowser/touchkit.xpi" .)

case " $BROWSERS " in *" firefox "*)
  echo ">> uBlock Origin (Firefox)"
  curl -fsSL -o "$ROOT/opt/kbrowser/ublock_origin.xpi" \
    https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi
esac

# Trim what a Kindle never needs.
rm -rf "$ROOT/usr/share/doc" "$ROOT/usr/share/man" "$ROOT/usr/share/gtk-doc" "$ROOT/var/cache/apk/"*
find "$ROOT/usr/share/locale" -mindepth 1 -maxdepth 1 ! -name 'en*' ! -name 'ru*' ! -name 'fr*' ! -name 'de*' -exec rm -rf {} + 2>/dev/null || true

USED_MB=$(du -sm "$ROOT" | cut -f1)
SIZE_MB="${IMAGE_SIZE_MB:-$(( USED_MB + USED_MB / 2 + 256 ))}"   # room for profile + cache
echo ">> kbrowser.ext3: ${USED_MB} MB used, ${SIZE_MB} MB image"
rm -f "$OUT/kbrowser.ext3"
# ext3 without newer features: mounts on the Kindle's 4.9 kernel.
mkfs.ext3 -q -L kbrowser -O ^metadata_csum,^64bit -d "$ROOT" "$OUT/kbrowser.ext3" "${SIZE_MB}M"
echo "$BROWSERS" > "$OUT/kbrowser.browsers"
ls -la "$OUT"
