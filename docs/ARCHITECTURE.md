# Architecture

## Launch path

1. **Library item.** `package/install.sh` writes scriptlets
   `/mnt/us/documents/kbrowser-{chromium,firefox}.sh`. The Kindle lists `.sh`
   files in `documents/` that carry a `# Name:` header as library items. The
   scriptlet runs `kbrowser.sh start <browser>` detached (`setsid`), so the
   Kindle UI isn't blocked.
2. **`package/kbrowser.sh`** runs on the Kindle as root, in busybox `sh`:
   - loop-mounts the ext3 image at `/var/tmp/kbrowser`, and binds `/dev`,
     `/dev/pts`, `/sys`, `/mnt/us` and the X socket dir `/tmp/.X11-unix` into it;
     mounts `proc` and RAM-backed `tmpfs` on `/tmp` (`TMP_MB`) and `/dev/shm`
     (`SHM_MB`);
   - optionally stops `lab126_gui` and restarts `pillow` (`STOP_FRAMEWORK=1`;
     `pillow` pushes X frames to the panel and stops together with the UI);
   - disables the screensaver (`lipc-set-prop com.lab126.powerd preventScreenSaver 1`);
   - `chroot`s into `/usr/local/bin/kbrowser-session` with a clean environment;
   - on exit, reverses all of that. "Stop" first sends the browser SIGTERM and
     waits (the CPU is slow) so the session is saved; only then does it kill
     whatever is left inside the chroot.
3. **`rootfs/usr/local/bin/kbrowser-session`** runs inside the image. It sets up
   a private D-Bus system bus, picks a display mode, and starts the browser as
   user `kindle`, wrapped in `dbus-run-session`.

The image is a stock Alpine armv7 root (`container/build-rootfs.sh`). There's
no desktop, panel or display manager. The browser's own processes are the
only ones inside.

## The Kindle's screen

- **Window placement by title.** The Kindle runs Xorg with a patched `awesome`
  (`lab126LayerLogic.lua`). It places windows by their WM_NAME, e.g.
  `L:A_N:application_ID:<id>_PC:N_WS:true_O:U`, and clients can't resize
  themselves. `L:A` with `WS:true` / `PC:N` means a fullscreen application
  window. Anything else stays a 100×100 stamp in the corner.
- **8-bit screen.** The X root is **8-bit** (1272×1696 on a PW 2024). Chromium
  and GTK3 Firefox need a 24-bit TrueColor visual, and they draw nothing on
  8-bit. Xephyr doesn't help, because it can't be deeper than its host.

### Display modes (`MODE`)

| Mode | How | When |
|---|---|---|
| `kview` | The browser draws on a private 24-bit Xvfb `:1`; `kview` mirrors it into one lab126-titled window on `:0` | 8-bit screens: every Kindle so far. Chosen by `auto`. |
| `direct` | The browser window goes straight onto `:0`. Chromium gets `--window-name=<lab126 title>`; Firefox's title is pinned by `kbrowser.cfg` | Only on 24/32-bit screens |
| `xephyr` | A nested Xephyr on `:0` | Only on 24/32-bit screens |

`direct` and `xephyr` fall back to `kview` automatically on a screen below 24-bit.

## kview

`kview/kview.c` is about 450 lines of C: Xlib, XShm, XDamage, XFixes, XTest.

- **Mirroring.** It listens for DAMAGE on the source root window. It gathers
  the damaged region for `-delay` ms (`REFRESH_MS`), fetches the rectangles
  (one bounding box if there are more than 16) with `XShmGetImage`, converts
  them, and `XPutImage`s them into its window on `:0`.
- **Pixel conversion.** On TrueColor targets, pixels are repacked using the
  channel masks. On anything else (StaticGray, GrayScale, PseudoColor), kview
  computes luma (`(77r + 150g + 29b) >> 8`) and asks the server for the pixel of
  each of 256 gray levels with `XAllocColor`. That works for every visual class
  without guessing.
- **Input.** Pointer and button events on its window are forwarded to `:1`
  with XTEST, scaled if the window size differs. Keys are mapped by keysym.
- **Window manager for `:1`** (disable with `-nowm`):
  - every top-level window fills the screen, with no decorations;
  - dialogs (transient, or `_NET_WM_WINDOW_TYPE_DIALOG`) are centred;
  - dock windows keep their own geometry, and their `_NET_WM_STRUT` bottom is
    reserved;
  - `_NET_WM_STATE` requests (fullscreen, maximize) are acknowledged by
    updating the property. Browsers only enter fullscreen when a WM confirms it.
- **32-bit gotcha.** `long` is 32 bits on the Kindle. Timestamps use `int64_t`
  and `CLOCK_MONOTONIC`, because `tv_sec * 1000` overflows a 32-bit value.

## Kindle Touch Kit (`extension/`)

A Manifest V3 extension that loads in both browsers: `background.service_worker`
for Chromium, `background.scripts` for Firefox.

- **UI isolation.** The UI lives in a *closed* shadow root appended to `<html>`,
  not `<body>`, so page zoom and transforms on `body` don't affect it.
- **CSP-proof styling.**
  - Styles go in through constructable stylesheets (`adoptedStyleSheets`),
    because strict page CSPs block `<style>` elements and `style` attributes.
    Firefox content scripts create the sheet in the page's realm
    (`window.wrappedJSObject` + `cloneInto`).
  - Host positioning uses `element.style` (CSSOM), not `setAttribute("style")`.
  - On zoomed-out or pinch-zoomed pages, the bar tracks `visualViewport` so it
    keeps its physical size.
- **Keyboard.** It types with `document.execCommand("insertText")`, which fires
  real `beforeinput`/`input` events that React and Vue controlled inputs
  accept. It falls back to `setRangeText` plus a synthetic `input` event. Enter
  dispatches key events, then `form.requestSubmit()`. Tapping an already
  focused field (autofocus) also opens the keyboard.
- **Drag-to-scroll** acts only on `pointerType === "mouse"`, which is what taps
  look like after kview/XTEST. It suppresses the click that follows a drag.
- **Fullscreen (⤢).**
  - Chromium: `windows.update(state: fullscreen/maximized)`.
  - Firefox: its `windows.update` state changes are ignored in this setup, so
    the extension sets a window `titlePreface` as a signal. Privileged
    `kbrowser.cfg` watches the `titlepreface` attribute and toggles
    `window.fullScreen`, exactly as F11 does.
- **Stale service worker.** Chromium keeps running a cached copy of an unpacked
  extension's service worker after its files change. `kbrowser-session` hashes
  `/opt/kbrowser/touchkit` and deletes the profile's `Service Worker/` cache when
  the hash changes.

## Browser tuning

- **Chromium** (`rootfs/etc/chromium/kbrowser.conf`, `policies/managed/kbrowser.json`):
  - `--no-sandbox` (no user namespaces on Kindle kernels) and `--test-type`
    (hides the warning bar that flag causes);
  - touch UI, `--force-device-scale-factor`, no smooth scrolling, no GPU;
  - renderer limit, `--process-per-site`, a 100 MB disk cache;
  - the Touch Kit loaded unpacked, uBlock Origin Lite force-installed;
  - policies: downloads to `/mnt/us/documents/Downloads`, local `.crx`
    installs allowed.
- **Firefox ESR** (`rootfs/usr/lib/firefox-esr/kbrowser.cfg` autoconfig + `policies.json`):
  - touch density, 2× scale, frame rate 10, no animations or caret blink;
  - no Fission, 2 content processes, unload tabs on low memory;
  - unsigned Touch Kit allowed (ESR only), uBlock Origin bundled;
  - silent session restore.
