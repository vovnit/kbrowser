const api = globalThis.browser ?? globalThis.chrome;
const SHORTCUTS = [
  ["Wikipedia", "https://en.m.wikipedia.org/"],
  ["Hacker News", "https://news.ycombinator.com/"],
  ["DuckDuckGo (lite)", "https://lite.duckduckgo.com/lite/"],
  ["Project Gutenberg", "https://www.gutenberg.org/"],
  ["Firefox add-ons", "https://addons.mozilla.org/firefox/"],
  ["Chrome Web Store", "https://chromewebstore.google.com/"],
];

function tile(title, url) {
  const a = document.createElement("a");
  a.href = url;
  a.textContent = title;
  const s = document.createElement("small");
  s.textContent = url.replace(/^https?:\/\//, "");
  a.append(s);
  return a;
}

const isFirefox = typeof browser !== "undefined" && location.protocol === "moz-extension:";
for (const [t, u] of SHORTCUTS) {
  if (isFirefox && u.includes("chromewebstore")) continue;
  if (!isFirefox && u.includes("addons.mozilla")) continue;
  document.getElementById("fixed").append(tile(t, u));
}

api.runtime.sendMessage({ cmd: "topSites" }).then((sites) => {
  const box = document.getElementById("top");
  for (const s of sites || []) box.append(tile(s.title || s.url, s.url));
  if (!box.children.length) box.previousElementSibling.hidden = true;
});

const q = document.getElementById("q");
document.getElementById("f").addEventListener("submit", (e) => {
  e.preventDefault();
  globalThis.__touchkitApi.go(q.value);
});
// Tapping the box shows the on-screen keyboard (kit.js handles focusin).
