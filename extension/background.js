// Kindle Touch Kit - background (service worker in Chromium, event page in Firefox).
const api = globalThis.browser ?? globalThis.chrome;
const IS_FIREFOX = typeof globalThis.browser !== "undefined" && !!api.runtime.getBrowserInfo;

api.runtime.onMessage.addListener((msg, sender, reply) => {
  const tabId = sender.tab && sender.tab.id;
  (async () => {
    switch (msg.cmd) {
      case "tabs": {
        const tabs = await api.tabs.query({ currentWindow: true });
        return tabs.map((t) => ({ id: t.id, title: t.title, url: t.url, active: t.active }));
      }
      case "activate": await api.tabs.update(msg.id, { active: true }); return true;
      case "close": await api.tabs.remove(msg.id); return true;
      case "new": await api.tabs.create({}); return true;
      // Closing every window quits the browser; kbrowser.sh then restores the Kindle UI.
      case "quit":
        for (const w of await api.windows.getAll()) await api.windows.remove(w.id);
        return true;
      // Window fullscreen (not the page Fullscreen API): hides tabs + toolbar and
      // survives navigation. Toggles.
      case "fullscreen": {
        const w = await api.windows.get(sender.tab ? sender.tab.windowId : api.windows.WINDOW_ID_CURRENT);
        if (IS_FIREFOX) {
          // Firefox's windows.update ignores state changes here; kbrowser.cfg (privileged)
          // watches for this title preface and toggles window.fullScreen like F11 does.
          await api.windows.update(w.id, { titlePreface: "kbrowser-fullscreen:" + Date.now() });
          return "toggled";
        }
        await api.windows.update(w.id, { state: w.state === "fullscreen" ? "maximized" : "fullscreen" });
        return (await api.windows.get(w.id)).state;
      }
      // Pages can't navigate to about:/chrome:/extension URLs themselves.
      case "open": await api.tabs.update(tabId, { url: msg.url }); return true;
      case "topSites": return (api.topSites ? await api.topSites.get() : []).slice(0, 12);
    }
    return null;
  })().then(reply, (e) => reply({ error: String(e) }));
  return true; // async reply
});
