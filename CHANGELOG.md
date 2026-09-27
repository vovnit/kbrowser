# Changelog

Versions are the KPM package versions (`package/manifest.json`). The Touch Kit
has its own version in `extension/manifest.json`.

## 0.1.3
- Chromium gets a private RAM-backed `/dev/shm` (`SHM_MB`, default 256 MB)
  instead of `--disable-dev-shm-usage`. Heavy pages (e.g. MANGA Plus) no longer
  exhaust `/tmp` and crash the tab.
- Chromium is the default browser.

## 0.1.2
- Touch Kit: **⤢ fullscreen** button (window fullscreen, stays on while
  navigating), and error toasts.
- kview is also a minimal window manager for the private display: fullscreen
  requests are acknowledged, windows get no decorations, dialogs are centred,
  dock struts are honoured.
- The launcher clears Chromium's stale extension service-worker cache when the
  Touch Kit changes.
- Chromium: local `.crx` installs are allowed by policy.

## 0.1.1
- **kview**: the browser renders on a private 24-bit Xvfb, converted to the
  Kindle's 8-bit screen. This fixes the black screen on the device. Adds
  `MODE=auto` (the default) and `REFRESH_MS`.
- The previous run's log is kept as `kbrowser.prev.log`.
- `apk-tools` is included in the image.
- KPM manifest v2, for KPM 0.2.x.

## 0.1.0
- First version: Chromium 149 / Firefox ESR 140 in an Alpine armv7 image, a KPM
  package with library launchers, the Kindle Touch Kit extension, and the
  Kindle-like test VM.
