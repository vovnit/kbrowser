#!/bin/sh
# kbrowser - run Firefox or Chromium on a jailbroken Kindle as a single app.
#
#   kbrowser.sh start [chromium|firefox]   mount the image, run the browser, clean up on exit
#   kbrowser.sh stop                       kill a running session and clean up
#   kbrowser.sh cleanup                    only unmount leftovers (after a crash)
#   kbrowser.sh shell                      root shell inside the image (debugging, apk add ...)
#
# Everything is logged to /mnt/us/kbrowser/kbrowser.log (readable over USB).
# Settings: /mnt/us/kbrowser/kbrowser.conf (created from the defaults on first run).

SELF="$(readlink -f "$0")"
DIR="$(dirname "$SELF")"
DATA=/mnt/us/kbrowser
CONF="$DATA/kbrowser.conf"
LOG="$DATA/kbrowser.log"
PIDFILE=/var/tmp/kbrowser.pid
MNT=/var/tmp/kbrowser

mkdir -p "$DATA"
[ -f "$CONF" ] || cp "$DIR/kbrowser.conf" "$CONF"
# shellcheck disable=SC1090
. "$DIR/kbrowser.conf"   # defaults
. "$CONF"                # user overrides
IMAGE="${IMAGE:-$DATA/kbrowser.ext3}"

say() { echo "$(date '+%H:%M:%S') $*" >> "$LOG"; echo "$*"; }
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

is_mounted() { awk -v m="$MNT" '$2 == m { f = 1 } END { exit !f }' /proc/mounts; }

procs_in_chroot() {
  for p in /proc/[0-9]*; do
    [ "$(readlink "$p/root" 2>/dev/null)" = "$MNT" ] && echo "${p#/proc/}"
  done
}

mount_image() {
  [ -f "$IMAGE" ] || { say "ERROR: $IMAGE not found - copy kbrowser.ext3 there"; return 1; }
  mkdir -p "$MNT"
  if ! is_mounted; then
    mount -o loop,noatime -t ext3 "$IMAGE" "$MNT" || { say "ERROR: cannot mount $IMAGE"; return 1; }
  fi
  mount -o bind /dev "$MNT/dev"
  mount -o bind /dev/pts "$MNT/dev/pts"
  # Private RAM-backed /dev/shm for Chromium's shared memory (it only uses what it
  # needs; the size is a cap). Squeezing it into /tmp crashed tabs on heavy pages.
  mount -t tmpfs -o size="${SHM_MB:-256}m",mode=1777 tmpfs "$MNT/dev/shm"
  mount -t proc proc "$MNT/proc"
  mount -o bind /sys "$MNT/sys"
  # RAM-backed /tmp: keeps browser temp files off the flash.
  mount -t tmpfs -o size="${TMP_MB:-128}m",mode=1777 tmpfs "$MNT/tmp"
  mkdir -p "$MNT/tmp/.X11-unix"
  mount -o bind /tmp/.X11-unix "$MNT/tmp/.X11-unix"
  mkdir -p "$MNT/mnt/us" /mnt/us/documents/Downloads
  mount -o bind /mnt/us "$MNT/mnt/us"
  cp -L /etc/resolv.conf "$MNT/etc/resolv.conf" 2>/dev/null || echo "nameserver 1.1.1.1" > "$MNT/etc/resolv.conf"
  cp /etc/hosts "$MNT/etc/hosts" 2>/dev/null
  chmod a+w /dev/shm 2>/dev/null
}

swap_on() {
  [ -n "${SWAP_IMAGE:-}" ] && [ -f "$SWAP_IMAGE" ] || return 0
  L="$(losetup -f 2>/dev/null)" || return 0
  losetup "$L" "$SWAP_IMAGE" && swapon "$L" && echo "$L" > /var/tmp/kbrowser.swap && say "swap on $L"
}
swap_off() {
  [ -f /var/tmp/kbrowser.swap ] || return 0
  L="$(cat /var/tmp/kbrowser.swap)"; swapoff "$L"; losetup -d "$L"; rm -f /var/tmp/kbrowser.swap
}

# Ask the browser to quit (it saves its session), give it time on this slow CPU,
# then terminate whatever is left in the chroot.
browser_pids() {
  for pid in $(procs_in_chroot); do
    case "$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')" in
      *-contentproc*|*--type=*) ;;
      */firefox-esr\ *|*/chromium/chromium\ *) echo "$pid" ;;
    esac
  done
}
stop_browser() {
  for pid in $(browser_pids); do kill -TERM "$pid" 2>/dev/null; done
  i=0
  while [ -n "$(browser_pids)" ] && [ $i -lt 20 ]; do sleep 1; i=$((i + 1)); done
}

cleanup() {
  stop_browser
  for pid in $(procs_in_chroot); do kill "$pid" 2>/dev/null; done
  sleep 2
  for pid in $(procs_in_chroot); do kill -9 "$pid" 2>/dev/null; done
  for m in tmp/.X11-unix tmp mnt/us sys proc dev/shm dev/pts dev; do
    umount "$MNT/$m" 2>/dev/null || umount -l "$MNT/$m" 2>/dev/null
  done
  sync
  umount "$MNT" 2>/dev/null || { sleep 2; umount "$MNT" 2>/dev/null; } || umount -l "$MNT" 2>/dev/null
  swap_off
  is_mounted && say "WARNING: $MNT still mounted" || say "unmounted"
}

framework_stop() {
  [ "${STOP_FRAMEWORK:-0}" = 1 ] || return 0
  say "stopping Kindle UI to free RAM"
  initctl stop lab126_gui >/dev/null 2>&1
  initctl start pillow >/dev/null 2>&1   # pillow pushes X frames to the panel
  touch /var/tmp/kbrowser.framework_stopped
}
framework_restore() {
  [ -f /var/tmp/kbrowser.framework_stopped ] || return 0
  rm -f /var/tmp/kbrowser.framework_stopped
  say "restarting Kindle UI"
  initctl start lab126_gui >/dev/null 2>&1
}

run() {
  B="${1:-${BROWSER:-chromium}}"
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    say "already running (pid $(cat "$PIDFILE"))"; return 0
  fi
  echo $$ > "$PIDFILE"
  # Keep the previous run next to the current one (e.g. Chromium, then Firefox).
  [ -f "$LOG" ] && mv -f "$LOG" "$DATA/kbrowser.prev.log"
  say "kbrowser start: browser=$B mode=${MODE:-auto} image=$IMAGE"
  mount_image || { cleanup; rm -f "$PIDFILE"; return 1; }
  swap_on
  framework_stop
  lipc-set-prop com.lab126.powerd preventScreenSaver 1 2>/dev/null
  free | sed 's/^/  /' >> "$LOG"

  env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    KBROWSER_BROWSER="$B" KBROWSER_MODE="${MODE:-auto}" KBROWSER_REFRESH_MS="${REFRESH_MS:-80}" KBROWSER_SCALE="${SCALE:-2.0}" \
    KBROWSER_UA="${USER_AGENT:-}" KBROWSER_URL="${START_URL:-}" KBROWSER_RENDERERS="${RENDERERS:-2}" \
    KBROWSER_LOWEND="${LOW_END:-0}" KBROWSER_DOWNLOADS="${DOWNLOADS:-/mnt/us/documents/Downloads}" \
    chroot "$MNT" /usr/local/bin/kbrowser-session >> "$LOG" 2>&1
  say "session ended ($?)"

  lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
  framework_restore
  cleanup
  rm -f "$PIDFILE"
}

case "${1:-start}" in
  start)   shift; run "$@" ;;
  stop)
    # Quit the browser; the running "start" then restores the UI and unmounts.
    stop_browser
    for pid in $(procs_in_chroot); do kill "$pid" 2>/dev/null; done
    i=0
    while [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null && [ $i -lt 20 ]; do sleep 1; i=$((i + 1)); done
    if [ -f "$PIDFILE" ] || is_mounted; then
      [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null
      cleanup; framework_restore; rm -f "$PIDFILE"
    fi
    ;;
  cleanup) cleanup; framework_restore; rm -f "$PIDFILE" ;;
  shell)
    mount_image && chroot "$MNT" /bin/sh -l
    is_mounted && [ ! -f "$PIDFILE" ] && cleanup
    ;;
  *) echo "usage: $0 start [firefox|chromium] | stop | cleanup | shell"; exit 2 ;;
esac
