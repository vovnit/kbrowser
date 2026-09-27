const api = globalThis.browser ?? globalThis.chrome;
const DEFAULTS = {
  showBar: true, autoKeyboard: true, dragScroll: "follow", einkMode: true,
  pageOverlap: 0.1, layouts: ["en", "ru", "fr"], searchUrl: "https://duckduckgo.com/html/?q=%s",
};

function read(id) {
  const el = document.getElementById(id);
  if (el.type === "checkbox") return el.checked;
  if (id === "pageOverlap") return Number(el.value);
  if (id === "layouts") {
    const l = el.value.split(",").map((s) => s.trim().toLowerCase()).filter((s) => s in globalThis.TOUCHKIT_LAYOUTS && s !== "sym");
    return l.length ? l : ["en"];
  }
  return el.value;
}

api.storage.local.get(DEFAULTS).then((cfg) => {
  for (const [k, v] of Object.entries(cfg)) {
    const el = document.getElementById(k);
    if (!el) continue;
    if (el.type === "checkbox") el.checked = v;
    else el.value = Array.isArray(v) ? v.join(", ") : String(v);
    el.addEventListener("change", async () => {
      await api.storage.local.set({ [k]: read(k) });
      document.getElementById("saved").textContent = "Saved.";
    });
  }
});
