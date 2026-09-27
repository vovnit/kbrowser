#!/bin/sh
# Grab the VM's Kindle screen (X display :0) as PNG: vm/screenshot.sh [out.png] [width]
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/out/screen.png}"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
"$HERE/ssh.sh" "DISPLAY=:0 magick import -window root -resize ${2:-1272}x png:-" > "$OUT"
echo "$OUT"
