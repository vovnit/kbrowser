# Research notes

## Options considered

| Option | Extensions | Verdict |
|---|---|---|
| Built-in Kindle browser (Chromium-based since FW 5.16.4) | none | Tweakable only: fullscreen, UA, search engine |
| Full Alpine desktop in a chroot (alpine-kindle, alpine_kindle, xfce forks) | yes | Works, but the desktop alone uses 145 MB (JWM) to 216 MB (MATE) on a PW5 |
| **Single browser in a chroot, no desktop** (this project) | **yes** | Chosen |
| NetSurf / Dillo / links | no | No modern JS |
| WebKitGTK browsers (Epiphany, badwolf, vimb, surf) | no WebExtensions | — |
| qutebrowser / Falkon (QtWebEngine) | userscripts only | Chromium engine plus Qt/Python overhead |

Alpine packages both browsers for **armv7** (`kindlehf` = armhf). Checked
v3.22, v3.23 and edge: `chromium` 142 → 149 → 152, `firefox-esr` 140.

## Chromium vs Firefox ESR

Measured in the VM (2× Cortex-A7, 1 GB):

| | Chromium 149 | Firefox ESR 140 |
|---|---|---|
| Window appears | ~20 s | ~40–65 s |
| Memory (PSS, one tab) | ~280–400 MB (MANGA Plus viewer: ~430 MB total) | ~500 MB with uBO (plus a ~300 MB spike on uBO's first filter build) |
| Ad blocking | uBlock Origin Lite (MV3) | full uBlock Origin |
| Extensions | Chrome Web Store (MV3) | addons.mozilla.org, unsigned allowed on ESR |

On the real device, Firefox felt noticeably worse, so Chromium is the default.

## Findings from the device

- **KPM on the device** (0.2.x) only accepts **manifest v2**, and can't
  upgrade packages that were installed from a file.
- **The X root is 8-bit, 1272×1696.** Browsers ran but drew black, which led
  to `kview`.
- **No swap is active** on the device, unlike the 128 MB zram seen on a PW5.

## Web apps and Android apps

- **MANGA Plus** (web): loads, and the chapter viewer (decrypted pages) works
  in Chromium and Firefox. An early "Aw, Snap" in Chromium traced to shared
  memory filling the 128 MB `/tmp` (`--disable-dev-shm-usage`); fixed with a
  dedicated `/dev/shm`.
- **PressReader** has a web reader. Not verified here.
- **Android apps** through Android Translation Layer were investigated and
  parked:
  - Alpine's armv7 ATL and ART are compiled hard-float, but ART's JNI glue
    passes floats soft-float. Every native method that takes or returns floats
    breaks.
  - The ATL side can be fixed by building with `JNICALL` =
    `__attribute__((pcs("aapcs")))`. ART's own natives (e.g.
    `Float_intBitsToFloat` in `libopenjdk.so`) need the same rebuild.
  - Apps that need Google Play Services or Widevine DRM (PressReader and
    MANGA Plus apps, store readers) wouldn't run under ATL on any architecture.
