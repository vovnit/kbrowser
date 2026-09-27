#!/bin/sh
# KPM uninstall hook. Keeps /mnt/us/kbrowser (image, profile, settings) on upgrade.
sh "$(pwd)/kbrowser.sh" stop 2>/dev/null
sh "$(pwd)/kbrowser.sh" cleanup 2>/dev/null
rm -f /mnt/us/documents/kbrowser-firefox.sh /mnt/us/documents/kbrowser-chromium.sh
[ "$1" = upgrade ] || echo "Left /mnt/us/kbrowser in place; delete it to remove the image and profiles."
