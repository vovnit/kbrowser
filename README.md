# kbrowser

A real browser on a jailbroken Kindle: **Chromium** (or Firefox ESR), with
extensions, run as a single app. There's no Linux desktop around it. You tap
**Chromium** in your library, browse, and quit back to the Kindle UI.

Built for the **Kindle Paperwhite 2024 (12th gen)**: 1 GB RAM, armhf firmware,
Véra jailbreak, KPM. It should work on other `kindlehf` Kindles with a touch
screen.

- **Full Chromium 149** with Chrome Web Store extensions (MV3). Firefox ESR 140
  is available as an alternative, with full uBlock Origin.
- **Kindle Touch Kit** extension, preinstalled:
  - a bottom bar: back, forward, reload, **page up/down** (turn a page instead of
    scrolling, which suits e-ink), keyboard, Go, tabs and **fullscreen**;
  - an **on-screen keyboard** for web page fields, with EN / RU / FR / DE layouts
    and symbols;
  - drag-to-scroll, a tab switcher, a start page, and an "e-ink mode" that turns
    off animations.
- **E-ink tuning:** grayscale output, no smooth scrolling or animations, updates
  gathered before each redraw, 2× scale.
- **Memory tuning** for about 1 GB: limited renderer processes, and RAM-backed
  `/tmp` and `/dev/shm`. Optionally the Kindle UI is stopped while browsing.

> Status: works on a PW 2024 (Chromium tested there) and in the bundled test VM.
> It's a hobby project that runs as root on your device. Use at your own risk.

---

## Install

### From a release (no build needed)

1. Download from the [Releases](../../releases) page:
   - `kbrowser-chromium.ext3.zip` (recommended; `kbrowser-full` also has Firefox ESR)
   - `kbrowser_<ver>_kindlehf.kpkg`
2. Unzip the image and copy it over USB to `/mnt/us/kbrowser/kbrowser.ext3`.
   Keep that exact file name.
3. Install the `.kpkg` with KPM, then tap **Chromium** in your library. See steps
   3–4 below.

### Build it yourself

You need:
- a jailbroken Kindle with **KPM**, and Wi-Fi;
- a Mac or Linux PC with **Docker** that can run `linux/arm/v7` containers
  (OrbStack and Docker Desktop both can), plus `python3`.

1. **Build**
   ```sh
   ./build.sh                        # out/kbrowser.ext3 (~1.5 GB) + out/kbrowser_<ver>_kindlehf.kpkg
   BROWSERS=chromium ./build.sh      # Chromium only: about half the size
   ```
2. **Copy the image** over USB to `/mnt/us/kbrowser/kbrowser.ext3`, which is the
   `kbrowser/` folder at the Kindle's USB root.
3. **Install the package** `out/kbrowser_<ver>_kindlehf.kpkg` with KPM. From
   kterm or SSH:
   ```sh
   /var/local/kmc/bin/kpm install file:///mnt/us/kbrowser_0.1.3_kindlehf.kpkg
   ```
   This adds **Chromium** and **Firefox** items to your library.
4. Tap **Chromium**.

### Updating

KPM 0.2.x can't upgrade a package that was installed from a file: it fails with
"Could not resolve dependency graph". So **uninstall first**, then install the
new `.kpkg`:
```sh
/var/local/kmc/bin/kpm uninstall kbrowser
/var/local/kmc/bin/kpm install file:///mnt/us/kbrowser_<ver>_kindlehf.kpkg
```
Uninstalling keeps `/mnt/us/kbrowser/` (image, settings, profiles). Replace
`kbrowser.ext3` only when the image changed. Doing so resets the browser
profiles, which live inside the image.

---

## Using it

The Touch Kit bar sits at the bottom of every web page:

| Button | Does |
|---|---|
| ◀ ▶ ↻ | back, forward, reload |
| ▲ ▼ | page up / page down (90% of a screen, no animation) |
| ⌨ | show or hide the on-screen keyboard. It also pops up when you tap a text field. |
| **Go** | type an address or a search (DuckDuckGo by default) |
| ▦ | tabs: switch, close, **+ New tab**, **Quit browser (back to Kindle)** |
| ⤢ | fullscreen: hides tabs and toolbar, and stays on as you navigate |
| ▾ | hide the bar; a small ▴ brings it back |

Notes:
- **Downloads** go to `/mnt/us/documents/Downloads`.
- **Extensions:** install from the Chrome Web Store as usual. uBlock Origin
  Lite is installed automatically on first run. A `.crx` in Downloads can be
  opened from `file:///mnt/us/documents/Downloads/`.
- **Touch Kit settings** (layouts, search engine, drag behaviour, e-ink mode)
  are on the extension's options page: chrome://extensions → Kindle Touch Kit →
  Details → Extension options.

### Settings: `/mnt/us/kbrowser/kbrowser.conf`

This file is created on first run. Edit it over USB.

| Setting | Default | Meaning |
|---|---|---|
| `BROWSER` | `chromium` | used when a launcher doesn't name one |
| `MODE` | `auto` | `auto` picks `kview` on the Kindle's 8-bit screen, `direct` on a 24-bit one; `xephyr` is also available |
| `REFRESH_MS` | `80` | how long changes are gathered before a screen update (fewer e-ink flashes) |
| `SCALE` | `2.0` | CSS pixel ratio: 2.0 ≈ 636 CSS px wide; 1.5 fits more text |
| `STOP_FRAMEWORK` | `0` | `1` stops the Kindle reader UI while browsing (frees ~100–150 MB); it's restarted on exit |
| `USER_AGENT` | empty | `mobile` for phone versions of sites, or a full user-agent string |
| `START_URL` | empty | page to open at start (empty = Touch Kit start page) |
| `RENDERERS` / `LOW_END` | `2` / `0` | Chromium renderer process limit / low-end-device mode |
| `TMP_MB` / `SHM_MB` | `128` / `256` | size caps of the RAM-backed `/tmp` and `/dev/shm` |
| `SWAP_IMAGE` | empty | path to an extra swap block image on `/mnt/us` |

### Command line (SSH / kterm)

```sh
K=/mnt/us/kmc/kpm/packages/kbrowser/kbrowser.sh
sh $K start [chromium|firefox]   # what the library items do
sh $K stop                       # quit the browser, restore the Kindle UI, unmount
sh $K cleanup                    # unmount leftovers after a crash
sh $K shell                      # root shell inside the image (apk add ..., edit configs)
```

---

## Troubleshooting

Start with the log, `/mnt/us/kbrowser/kbrowser.log`. The previous run is kept
as `kbrowser.prev.log`.

| Symptom | Likely cause / fix |
|---|---|
| Black screen, the browser "does nothing" | The Kindle's X server is 8-bit, and browsers draw black there. `MODE=auto` or `kview` handles this; older confs saying `direct` are switched automatically. Look for `mode=kview` in the log. |
| "Aw, Snap!" on heavy sites | The renderer ran out of shared memory. Fixed in 0.1.3 with a dedicated `/dev/shm` (`SHM_MB`). If it persists, try `STOP_FRAMEWORK=1`. |
| KPM: "Invalid manifest version" | Your KPM only accepts manifest v2. Packages built by this repo are v2. |
| KPM: "Could not resolve dependency graph" | Uninstall kbrowser first, then install (see [Updating](#updating)). |
| Kindle UI missing after a crash | `sh …/kbrowser.sh cleanup`, or reboot. |
| An extension update has no effect in Chromium | The launcher drops Chromium's cached extension service worker whenever the Touch Kit files change. For other unpacked extensions, clear `Service Worker/` in the profile. |

### Known limitations

- **The browser's own address bar and settings pages.** The on-screen keyboard
  covers web page fields and the kit's **Go** box. It doesn't reach the
  browser's own address bar or its built-in settings pages (`chrome://…`,
  `about:…`); use **Go**.
- **First launch** shows the browser's own new tab page once. The Touch Kit
  start page is used after that.
- **Chromium shows an "Esc to exit full screen" hint** for a few seconds after
  ⤢. It can't be turned off.
- **DRM video (Widevine)** doesn't exist for 32-bit ARM Linux, so DRM-protected
  video won't play.

---

## How it works (short)

```
Kindle home → scriptlet → package/kbrowser.sh (Kindle side, root)
  ├─ loop-mounts /mnt/us/kbrowser/kbrowser.ext3 (Alpine armv7 + browser)
  ├─ binds /dev /proc /sys /mnt/us + X socket; RAM-backed /tmp and /dev/shm
  └─ chroot → rootfs/usr/local/bin/kbrowser-session
       ├─ Xvfb :1 (24-bit, private)  ← browser draws here
       └─ kview: copies changed areas to ONE window on the Kindle's X :0,
                 converting to 8-bit gray; forwards taps; also a minimal
                 window manager for :1 (fullscreen, dialogs, no decorations)
```

The details are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): the Kindle
window manager's title convention, the 8-bit screen, kview, how the Touch Kit
works, and how fullscreen works.

## Repository layout

| Path | What |
|---|---|
| `build.sh` | builds the image, the package, or `kview` |
| `container/build-rootfs.sh` | image build (runs in an Alpine armv7 container) |
| `package/` | KPM package: launcher `kbrowser.sh`, default `kbrowser.conf`, hooks, manifest |
| `rootfs/` | files overlaid into the image: session script, Chromium flags and policies, Firefox autoconfig and policies |
| `kview/kview.c` | 24-bit → Kindle screen bridge + minimal window manager (C, Xlib) |
| `extension/` | Kindle Touch Kit (MV3, Chromium + Firefox) |
| `vm/` | Kindle-like QEMU test VM: see [docs/VM.md](docs/VM.md) |
| `docs/` | architecture, VM, research notes |
| `.github/workflows/release.yml` | builds and publishes a release on `v*` tags |

## Releasing

Bump `version` in `package/manifest.json`, add a `## x.y.z` section to
`CHANGELOG.md`, then tag:
```sh
git tag v0.1.3 && git push origin v0.1.3
```
`.github/workflows/release.yml` builds both image flavours on GitHub (ARM
emulated with QEMU, which takes a while) and publishes a release with:
- the zipped images;
- the `.kpkg`;
- `SHA256SUMS`;
- the CHANGELOG section as release notes.

The workflow fails if the tag doesn't match the package version. Running it
manually from the Actions tab builds the same files as downloadable artifacts
without releasing.

## Testing without a Kindle

`vm/` builds a QEMU armv7 VM that behaves like the Kindle in the ways that
matter: 1 GB RAM, an 8-bit X server at 1272×1696, the lab126-style window
manager, a FAT32 `/mnt/us`, and fake `initctl`/`lipc`. You can view it over VNC.

```sh
vm/build.sh && ./build.sh && vm/install-kbrowser.sh
vm/run.sh --headless
open vnc://localhost:5910          # the "Kindle screen"; click = tap
vm/ssh.sh 'cd /mnt/us/kmc/kpm/packages/kbrowser && sh install.sh'
vm/ssh.sh sh /mnt/us/documents/kbrowser-chromium.sh
```

See [docs/VM.md](docs/VM.md) for the dev loop (`vm/sync-kbrowser.sh`),
screenshots, and debugging Chromium through its remote debugger.

## Credits

- [adiglase/alpine-kindle](https://github.com/adiglase/alpine-kindle) and
  [schuhumi/alpine_kindle](https://github.com/schuhumi/alpine_kindle): Alpine
  chroot on Kindle, the WM title convention, and the pillow/UI notes.
- [bfabiszewski/kterm](https://github.com/bfabiszewski/kterm): the lab126 window title.
- [KindleModding](https://kindlemodding.org/) (KPM, scriptlets).
- Alpine Linux, for armv7 builds of Chromium and Firefox ESR.

## License

[GPL-3.0](LICENSE). The browsers, Alpine packages and extensions that the build
downloads keep their own licenses.
