#!/bin/sh
# KPM install hook (cwd = package directory). Creates home-screen scriptlets.
# Hooks must not touch the root filesystem - everything goes to /mnt/us.
PKG="$(pwd)"
chmod +x "$PKG/kbrowser.sh"
mkdir -p /mnt/us/kbrowser /mnt/us/documents
[ -f /mnt/us/kbrowser/kbrowser.conf ] || cp "$PKG/kbrowser.conf" /mnt/us/kbrowser/kbrowser.conf

scriptlet() { # file name browser
  cat > "/mnt/us/documents/$1" <<EOF
#!/bin/sh
# Name: $2
# Author: kbrowser
# DontUseFBInk
# Launches $2 via kbrowser ($PKG). Log: /mnt/us/kbrowser/kbrowser.log
setsid sh "$PKG/kbrowser.sh" start $3 >/dev/null 2>&1 < /dev/null &
EOF
}
scriptlet "kbrowser-firefox.sh" "Firefox" firefox
scriptlet "kbrowser-chromium.sh" "Chromium" chromium
echo "kbrowser installed. Copy kbrowser.ext3 to /mnt/us/kbrowser/ if you haven't."
