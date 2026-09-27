// Kindle Touch Kit - content script (also loaded directly by newtab.html).
//
// Adds, inside a closed shadow root so pages can't restyle it:
//   * a bottom bar: back, forward, reload, page up/down, keyboard, go-to/search, tabs
//   * an on-screen keyboard that types into the focused field of the page
//   * drag-to-scroll for mouse-style input (what a touch panel looks like through
//     Xephyr or a pointer-only X server); real touch input is left to the browser
//   * "e-ink mode": kills CSS animations/transitions/smooth scrolling
(() => {
  if (window.top !== window || globalThis.__touchkit) return;
  globalThis.__touchkit = true;

  const api = globalThis.browser ?? globalThis.chrome;
  const LAYOUTS = globalThis.TOUCHKIT_LAYOUTS;
  const BOTTOM = globalThis.TOUCHKIT_BOTTOM_ROW;
  const DEFAULTS = {
    showBar: true,
    autoKeyboard: true,
    dragScroll: "follow", // "follow" | "page" | "off"
    einkMode: true,
    pageOverlap: 0.1, // fraction of a screen repeated after a page turn
    layouts: ["en", "ru", "fr"],
    searchUrl: "https://duckduckgo.com/html/?q=%s",
    barPosition: "bottom",
  };
  let cfg = { ...DEFAULTS };

  // ---------------------------------------------------------------- helpers --
  const $ = (sel) => root.querySelector(sel);
  const deepTarget = (e) => (e.composedPath ? e.composedPath()[0] : e.target);
  const TEXT_TYPES = /^(text|search|email|url|tel|password|number|)$/i;
  function isEditable(el) {
    if (!el || el.nodeType !== 1) return false;
    if (el.isContentEditable) return true;
    if (el.tagName === "TEXTAREA") return !el.readOnly && !el.disabled;
    if (el.tagName === "INPUT") return TEXT_TYPES.test(el.type || "") && !el.readOnly && !el.disabled;
    return false;
  }
  function deepActive() {
    let a = document.activeElement;
    while (a && a.shadowRoot && a.shadowRoot.activeElement) a = a.shadowRoot.activeElement;
    return a;
  }
  function scrollerAt(x, y) {
    let el = document.elementFromPoint(x, y);
    while (el && el !== document.body && el !== document.documentElement) {
      const s = getComputedStyle(el);
      if (/(auto|scroll)/.test(s.overflowY) && el.scrollHeight > el.clientHeight + 4) return el;
      el = el.parentElement || (el.getRootNode() && el.getRootNode().host);
    }
    return document.scrollingElement || document.documentElement;
  }
  const send = (msg) => api.runtime.sendMessage(msg).catch?.(() => {});

  // ------------------------------------------------------------------- DOM --
  const host = document.createElement("touchkit-root");
  // Via CSSOM, not setAttribute("style"): a strict page CSP blocks style attributes.
  host.style.cssText = "all:initial;position:fixed;left:0;right:0;bottom:0;z-index:2147483647;display:block;transform-origin:0 0;";
  const root = host.attachShadow({ mode: "closed" });
  root.innerHTML = `
<div id="toast" class="panel" hidden></div>
<div id="tabs" class="panel" hidden></div>
<div id="url" class="panel" hidden>
  <form><input type="text" autocomplete="off" spellcheck="false" placeholder="Search or address"><button type="submit">Go</button></form>
</div>
<div id="kb" class="panel" hidden></div>
<div id="bar" class="panel">
  <button data-a="back" title="Back">&#9664;</button>
  <button data-a="fwd" title="Forward">&#9654;</button>
  <button data-a="reload" title="Reload">&#8635;</button>
  <button data-a="up" title="Page up">&#9650;</button>
  <button data-a="down" title="Page down">&#9660;</button>
  <button data-a="kb" title="Keyboard">&#9000;</button>
  <button data-a="url" class="wide" title="Go to / search">Go</button>
  <button data-a="tabs" title="Tabs">&#9638;</button>
  <button data-a="fs" title="Full screen">&#10530;</button>
  <button data-a="hidebar" title="Hide bar">&#9662;</button>
</div>
<button id="mini" data-a="showbar" title="Show bar" hidden>&#9652;</button>`;

  // Styles go in through CSSOM (constructable sheets): unlike <style> elements
  // they are not blocked by a page's Content-Security-Policy.
  function adoptCss(target, css) {
    const tryRealm = (Sheet, t, wrapArr) => {
      const sheet = new Sheet();
      sheet.replaceSync(css);
      t.adoptedStyleSheets = wrapArr([...t.adoptedStyleSheets, sheet]);
      return sheet;
    };
    try { return tryRealm(CSSStyleSheet, target, (a) => a); } catch (_) {}
    try { // Firefox content scripts: create the sheet in the page's realm
      const w = window.wrappedJSObject;
      return tryRealm(w.CSSStyleSheet, target.wrappedJSObject || target, (a) => cloneInto(a, w));
    } catch (_) {}
    const st = document.createElement("style"); // last resort
    st.textContent = css;
    (target === document ? document.head || document.documentElement : target).append(st);
    return st;
  }
  const KIT_CSS = `
  :host { all: initial; position: fixed !important; z-index: 2147483647 !important; display: block !important; }
  * { box-sizing: border-box; font-family: "DejaVu Sans", sans-serif; color: #000; }
  .panel { background: #fff; border-top: 2px solid #000; padding: 4px; }
  [hidden] { display: none !important; }
  button { background: #fff; border: 1.5px solid #000; border-radius: 6px; font-size: 18px;
           min-height: 44px; padding: 0 4px; margin: 0; touch-action: manipulation; -webkit-user-select: none; user-select: none; }
  button:active, button.on { background: #000; color: #fff; }
  #bar { display: flex; gap: 3px; }
  #bar button { flex: 1 1 0; font-size: 20px; }
  #bar button.wide { flex: 1.6 1 0; font-size: 16px; }
  #mini { position: absolute; right: 4px; bottom: 4px; width: 44px; opacity: .85; }
  .row { display: flex; gap: 3px; margin-bottom: 3px; }
  .row button { flex: 1 1 0; font-size: 20px; min-width: 0; min-height: 48px; }
  .row button.fn { flex: 1.5 1 0; font-size: 15px; }
  .row button.space { flex: 5 1 0; }
  #url form { display: flex; gap: 4px; margin-bottom: 4px; }
  #url input { flex: 1; min-width: 0; font-size: 18px; min-height: 44px; border: 1.5px solid #000; border-radius: 6px; padding: 0 8px; background: #fff; }
  #tabs { max-height: 60vh; overflow-y: auto; }
  #toast { font-size: 15px; padding: 8px; }
  .tab { display: flex; gap: 4px; margin-bottom: 4px; }
  .tab button.t { flex: 1; text-align: left; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; font-size: 16px; }
  .tab button.t.active { font-weight: bold; border-width: 3px; }
  .tab button.x { width: 48px; }
`;
  adoptCss(root, KIT_CSS);

  const urlInput = $("#url input");
  let editTarget = null; // element the keyboard types into
  let layoutIdx = 0, shift = false, sym = false;

  // Keep focus where it is when our buttons are pressed.
  root.addEventListener("mousedown", (e) => {
    if (deepTarget(e) !== urlInput) e.preventDefault();
  });

  // --------------------------------------------------------------- keyboard --
  function renderKeyboard() {
    const lay = sym ? LAYOUTS.sym : LAYOUTS[cfg.layouts[layoutIdx % cfg.layouts.length]] || LAYOUTS.en;
    const rows = [...lay.rows, BOTTOM];
    const kb = $("#kb");
    kb.textContent = "";
    for (const r of rows) {
      const row = document.createElement("div");
      row.className = "row";
      for (const key of r) {
        const b = document.createElement("button");
        if (typeof key === "string") {
          const ch = shift ? key.toUpperCase() : key;
          b.textContent = ch;
          b.dataset.ch = ch;
        } else {
          b.dataset.k = key.k;
          b.className = "fn";
          b.textContent = {
            shift: "⇧", bksp: "⌫", sym: sym ? "ABC" : "123", space: " ",
            enter: "↵", hide: "⌵",
            lang: (LAYOUTS[cfg.layouts[(layoutIdx + 1) % cfg.layouts.length]] || LAYOUTS.en).label,
          }[key.k];
          if (key.k === "space") b.className = "space";
          if (key.k === "shift" && shift) b.classList.add("on");
        }
        row.append(b);
      }
      kb.append(row);
    }
  }

  function typeInto(el, text) {
    if (!el) return;
    if (deepActive() !== el && el !== urlInput) el.focus({ preventScroll: true });
    // execCommand keeps undo history and fires real beforeinput/input events,
    // which keeps React/Vue-controlled inputs in sync.
    let ok = false;
    if (el !== urlInput) try { ok = document.execCommand("insertText", false, text); } catch (_) {}
    if (!ok && "value" in el) {
      try {
        const s = el.selectionStart ?? el.value.length, e = el.selectionEnd ?? s;
        el.setRangeText(text, s, e, "end");
      } catch (_) { el.value += text; }
      el.dispatchEvent(new InputEvent("input", { bubbles: true, composed: true, inputType: "insertText", data: text }));
    }
  }
  function backspace(el) {
    if (!el) return;
    let ok = false;
    if (el !== urlInput) try { ok = document.execCommand("delete", false); } catch (_) {}
    if (!ok && "value" in el) {
      try {
        let s = el.selectionStart, e = el.selectionEnd;
        if (s === e && s > 0) s -= 1;
        el.setRangeText("", s, e, "end");
      } catch (_) { el.value = el.value.slice(0, -1); }
      el.dispatchEvent(new InputEvent("input", { bubbles: true, composed: true, inputType: "deleteContentBackward" }));
    }
  }
  function enter(el) {
    if (!el) return;
    if (el === urlInput) return go(urlInput.value);
    if (el.tagName === "TEXTAREA" || el.isContentEditable) return typeInto(el, "\n");
    const opts = { key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true, cancelable: true, composed: true };
    const notCancelled = el.dispatchEvent(new KeyboardEvent("keydown", opts));
    el.dispatchEvent(new KeyboardEvent("keypress", opts));
    el.dispatchEvent(new KeyboardEvent("keyup", opts));
    if (notCancelled && el.form) {
      try { el.form.requestSubmit(); } catch (_) { el.form.submit(); }
    }
  }

  $("#kb").addEventListener("click", (e) => {
    const b = deepTarget(e).closest("button");
    if (!b) return;
    const el = editTarget;
    if (b.dataset.ch) {
      typeInto(el, b.dataset.ch);
      if (shift) { shift = false; renderKeyboard(); }
      return;
    }
    switch (b.dataset.k) {
      case "shift": shift = !shift; break;
      case "sym": sym = !sym; shift = false; break;
      case "lang": layoutIdx = (layoutIdx + 1) % cfg.layouts.length; sym = false; break;
      case "space": typeInto(el, " "); return;
      case "bksp": backspace(el); return;
      case "enter": enter(el); return;
      case "hide": showKeyboard(false); return;
    }
    renderKeyboard();
  });

  function showKeyboard(on, target) {
    if (target) editTarget = target;
    if (on) renderKeyboard();
    $("#kb").hidden = !on;
    $('[data-a="kb"]').classList.toggle("on", on);
    if (on && editTarget && editTarget !== urlInput) {
      // Keep the field visible above the keyboard.
      requestAnimationFrame(() => {
        const r = editTarget.getBoundingClientRect();
        const kbTop = innerHeight - host.getBoundingClientRect().height;
        if (r.bottom > kbTop - 8 || r.top < 0) {
          scrollerAt(r.left + 1, Math.max(1, Math.min(r.top, innerHeight - 1))).scrollBy({ top: r.bottom - kbTop + 40, behavior: "instant" });
        }
      });
    }
  }

  document.addEventListener("focusin", (e) => {
    const el = deepTarget(e);
    if (host.contains(el) || el === host) return;
    if (isEditable(el)) {
      editTarget = el;
      if (cfg.autoKeyboard) { closePanels(); showKeyboard(true, el); }
    }
  }, true);
  // A tap on a field that already has focus (e.g. autofocus) fires no focusin.
  document.addEventListener("click", (e) => {
    const el = deepTarget(e);
    if (cfg.autoKeyboard && isEditable(el) && $("#kb").hidden && !host.contains(el)) {
      closePanels();
      showKeyboard(true, el);
    }
  }, true);
  document.addEventListener("focusout", (e) => {
    const el = deepTarget(e);
    if (el !== editTarget) return;
    setTimeout(() => {
      const a = deepActive();
      if (!isEditable(a) && $("#url").hidden) showKeyboard(false);
    }, 150);
  }, true);

  // ------------------------------------------------------------ navigation --
  function page(dir) {
    const barH = host.getBoundingClientRect().height;
    const sc = scrollerAt(innerWidth / 2, Math.max(1, (innerHeight - barH) / 2));
    const view = sc === document.scrollingElement || sc === document.documentElement
      ? innerHeight - barH : Math.min(sc.clientHeight, innerHeight - barH);
    sc.scrollBy({ top: dir * view * (1 - cfg.pageOverlap), behavior: "instant" });
  }
  function go(text) {
    text = (text || "").trim();
    if (!text) return;
    let url;
    if (/^[a-z][a-z0-9+.-]*:/i.test(text) && !/\s/.test(text)) url = text;
    else if (/^[^\s/]+\.[a-z]{2,}(:\d+)?(\/\S*)?$/i.test(text) || /^localhost(:\d+)?(\/|$)/.test(text)) url = "https://" + text;
    else url = cfg.searchUrl.replace("%s", encodeURIComponent(text));
    closePanels();
    if (/^(about|chrome|moz-extension|chrome-extension):/.test(url)) send({ cmd: "open", url });
    else location.href = url;
  }
  $("#url form").addEventListener("submit", (e) => { e.preventDefault(); go(urlInput.value); });

  function closePanels() {
    $("#url").hidden = true;
    $("#tabs").hidden = true;
  }
  async function showTabs() {
    const list = await api.runtime.sendMessage({ cmd: "tabs" });
    const box = $("#tabs");
    box.textContent = "";
    const add = document.createElement("button");
    add.textContent = "+ New tab";
    add.style.width = "100%";
    add.style.marginBottom = "4px";
    add.onclick = () => send({ cmd: "new" });
    const quit = document.createElement("button");
    quit.textContent = "Quit browser (back to Kindle)";
    quit.style.width = "100%";
    quit.style.marginBottom = "4px";
    quit.onclick = () => send({ cmd: "quit" });
    box.append(add, quit);
    for (const t of list || []) {
      const row = document.createElement("div");
      row.className = "tab";
      const b = document.createElement("button");
      b.className = "t" + (t.active ? " active" : "");
      b.textContent = t.title || t.url;
      b.onclick = () => { send({ cmd: "activate", id: t.id }); closePanels(); };
      const x = document.createElement("button");
      x.className = "x";
      x.textContent = "✕";
      x.onclick = async () => { await send({ cmd: "close", id: t.id }); row.remove(); };
      row.append(b, x);
      box.append(row);
    }
    box.hidden = false;
  }

  root.addEventListener("click", (e) => {
    const b = deepTarget(e).closest("[data-a]");
    if (!b) return;
    switch (b.dataset.a) {
      case "back": history.back(); break;
      case "fwd": history.forward(); break;
      case "reload": location.reload(); break;
      case "up": page(-1); break;
      case "down": page(1); break;
      case "kb":
        if ($("#kb").hidden) showKeyboard(true, isEditable(deepActive()) ? deepActive() : editTarget);
        else showKeyboard(false);
        break;
      case "url": {
        const open = $("#url").hidden;
        closePanels();
        if (open) {
          $("#url").hidden = false;
          urlInput.value = /^(moz|chrome)-extension:/.test(location.href) ? "" : location.href;
          urlInput.focus();
          urlInput.select();
          showKeyboard(true, urlInput);
        } else showKeyboard(false);
        break;
      }
      case "tabs":
        if ($("#tabs").hidden) { closePanels(); showKeyboard(false); showTabs(); } else closePanels();
        break;
      case "fs":
        api.runtime.sendMessage({ cmd: "fullscreen" }).then((r) => { if (r && r.error) toast(r.error); }, (e) => toast(String(e)));
        break;
      case "hidebar": cfg.showBar = false; applyBar(); break;
      case "showbar": cfg.showBar = true; applyBar(); break;
    }
  });
  urlInput.addEventListener("focus", () => { editTarget = urlInput; });

  function toast(text) {
    const t = $("#toast");
    t.textContent = text;
    t.hidden = false;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => (t.hidden = true), 5000);
  }

  function applyBar() {
    $("#bar").hidden = !cfg.showBar;
    $("#mini").hidden = cfg.showBar;
  }

  // ----------------------------------------------------- drag to scroll ------
  // Only for mouse-type pointers: with a real touch device the browser scrolls
  // natively (and pointerType is "touch").
  let drag = null, suppressClick = false;
  window.addEventListener("pointerdown", (e) => {
    if (cfg.dragScroll === "off" || e.pointerType !== "mouse" || e.button !== 0) return;
    const t = deepTarget(e);
    if (host.contains(t) || t === host || isEditable(t)) return;
    if (t.closest && t.closest("input,select,textarea,video,audio,[draggable=true],canvas")) return;
    drag = { x: e.clientX, y: e.clientY, lastY: e.clientY, lastX: e.clientX, moved: false, sc: scrollerAt(e.clientX, e.clientY) };
  }, true);
  window.addEventListener("pointermove", (e) => {
    if (!drag) return;
    if (!drag.moved && Math.hypot(e.clientX - drag.x, e.clientY - drag.y) < 12) return;
    drag.moved = true;
    getSelection()?.removeAllRanges();
    if (cfg.dragScroll === "follow") {
      drag.sc.scrollBy({ left: drag.lastX - e.clientX, top: drag.lastY - e.clientY, behavior: "instant" });
    }
    drag.lastX = e.clientX; drag.lastY = e.clientY;
    e.preventDefault();
  }, { capture: true, passive: false });
  window.addEventListener("pointerup", (e) => {
    if (!drag) return;
    if (drag.moved) {
      suppressClick = true;
      setTimeout(() => (suppressClick = false), 400);
      if (cfg.dragScroll === "page") {
        const dy = e.clientY - drag.y;
        if (Math.abs(dy) > 60) page(dy < 0 ? 1 : -1);
      }
    }
    drag = null;
  }, true);
  window.addEventListener("click", (e) => {
    if (suppressClick) { e.preventDefault(); e.stopPropagation(); suppressClick = false; }
  }, true);
  window.addEventListener("dragstart", (e) => {
    if (drag) e.preventDefault(); // no link/image drag-and-drop while scrolling
  }, true);
  window.addEventListener("selectstart", (e) => {
    if (drag && drag.moved) e.preventDefault();
  }, true);

  // --------------------------------------------------------------- e-ink ----
  let einkSheet = null;
  function applyEink() {
    if (cfg.einkMode && !einkSheet) {
      einkSheet = adoptCss(document, `*,*::before,*::after{animation-duration:0s!important;animation-delay:0s!important;
        transition:none!important;scroll-behavior:auto!important}`);
    }
    if (einkSheet) einkSheet.disabled = !cfg.einkMode;
  }

  // ------------------------------------------------------------- settings ---
  function applyAll() {
    applyBar();
    applyEink();
    if (!$("#kb").hidden) renderKeyboard();
  }
  api.storage.local.get(DEFAULTS).then((v) => { cfg = { ...DEFAULTS, ...v }; applyAll(); });
  api.storage.onChanged.addListener((changes) => {
    for (const [k, { newValue }] of Object.entries(changes)) cfg[k] = newValue;
    applyAll();
  });

  // Attach to <html>, not <body>: pages that set CSS zoom/transform on body would
  // otherwise shrink or misplace the bar. (Don't try to undo zoom from computed
  // styles: Firefox reports its own device scale there.)
  const attach = () => document.documentElement.append(host);

  // Stay the same physical size and glued to the bottom of what's visible when
  // the page is pinch-zoomed or zoomed out to fit (visual viewport != layout viewport).
  const vv = globalThis.visualViewport;
  function fitViewport() {
    if (!vv) return;
    const s = vv.scale || 1;
    if (Math.abs(s - 1) < 0.01 && vv.offsetLeft === 0 && vv.offsetTop === 0) {
      host.style.zoom = host.style.width = host.style.top = host.style.transform = "";
      host.style.left = host.style.right = host.style.bottom = "0";
      return;
    }
    // CSS zoom scales the host's own lengths too, hence the "* s".
    host.style.zoom = String(1 / s);
    host.style.left = vv.offsetLeft * s + "px";
    host.style.width = vv.width * s + "px";
    host.style.top = (vv.offsetTop + vv.height) * s + "px";
    host.style.bottom = host.style.right = "auto";
    host.style.transform = "translateY(-100%)";
  }
  if (vv) {
    vv.addEventListener("resize", fitViewport);
    vv.addEventListener("scroll", fitViewport);
  }
  attach();
  fitViewport();
  if (isEditable(deepActive())) editTarget = deepActive(); // autofocus fields
  new MutationObserver(() => { if (!host.isConnected) attach(); })
    .observe(document.documentElement, { childList: true });

  globalThis.__touchkitApi = { showKeyboard, go, page };
})();
