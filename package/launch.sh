#!/bin/sh
# KPM launch hook: start the configured browser in the background.
setsid sh "$(pwd)/kbrowser.sh" start >/dev/null 2>&1 < /dev/null &
