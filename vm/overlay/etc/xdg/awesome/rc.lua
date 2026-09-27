-- lab126-style awesome configuration for the Kindle VM.
--
-- The real Kindle WM is awesome patched with /etc/xdg/awesome/lab126LayerLogic.lua.
-- It places windows purely from their WM_NAME, formatted as
--     L:<layer>_N:<role>_ID:<app id>[_PC:<chrome>][_WS:true][_O:<orientation>]
-- and clients are NOT allowed to move/resize themselves. Behaviour reproduced
-- here (from observations on PW5 firmware 5.19.x, see README):
--   L:A + (WS:true | PC:N)  -> full screen 1236x1648+0+0
--   L:A otherwise           -> below the 101px title/status chrome
--   L:D                     -> dialog layer; kept at its requested size, centred, on top
--   L:KB                    -> keyboard layer (guess): bottom-anchored, on top
--   anything else           -> left as a 100x100 stamp in the corner (as seen on device)
-- Names are parsed once, when the window is mapped. Every decision is logged to
-- /var/log/lab126-wm.log so tests can assert on it.

local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
beautiful.init(gears.filesystem.get_themes_dir() .. "default/theme.lua")
beautiful.border_width = 0
beautiful.useless_gap = 0

local CHROME_TOP = 101
local LOG = "/var/log/lab126-wm.log"
local REPARSE = os.getenv("LAB126_REPARSE_ON_RENAME") == "1"

-- One floating tag: awesome only shows clients that are on a selected tag.
awful.layout.layouts = { awful.layout.suit.floating }
awful.screen.connect_for_each_screen(function(s)
  awful.tag({ "kindle" }, s, awful.layout.suit.floating)
  s.tags[1].selected = true
end)

local function log(msg)
  local f = io.open(LOG, "a")
  if f then f:write(os.date("%H:%M:%S "), msg, "\n"); f:close() end
end

local function parse(name)
  if not name or not name:match("^L:") then return nil end
  local t, last = {}, nil
  for tok in (name .. "_"):gmatch("(.-)_") do
    local k, v = tok:match("^(%u+):(.*)$")
    if k then t[k] = v; last = k
    elseif last then t[last] = t[last] .. "_" .. tok end
  end
  return t
end

local function target_geometry(c, t)
  local g = c.screen.geometry
  if not t then
    return { x = 0, y = 0, width = 100, height = 100 }, "unrecognised title -> 100x100 stamp"
  end
  if t.L == "A" then
    if t.WS == "true" or t.PC == "N" then
      return { x = g.x, y = g.y, width = g.width, height = g.height }, "application, fullscreen"
    end
    return { x = g.x, y = g.y + CHROME_TOP, width = g.width, height = g.height - CHROME_TOP }, "application, under chrome"
  elseif t.L == "D" then
    local w, h = math.min(c.width, g.width), math.min(c.height, g.height)
    return { x = g.x + (g.width - w) // 2, y = g.y + (g.height - h) // 2, width = w, height = h }, "dialog"
  elseif t.L == "KB" then
    local h = math.min(c.height, g.height // 2)
    return { x = g.x, y = g.y + g.height - h, width = g.width, height = h }, "keyboard"
  end
  return { x = 0, y = 0, width = 100, height = 100 }, "unknown layer " .. tostring(t.L)
end

local function place(c)
  local t = parse(c.name)
  local geo, why = target_geometry(c, t)
  c._lab126 = geo
  c.border_width = 0
  c.size_hints_honor = false
  c.floating = true
  c.ontop = t ~= nil and (t.L == "D" or t.L == "KB")
  c:geometry(geo)
  log(string.format("manage pid=%s name=%q -> %dx%d+%d+%d (%s)",
    tostring(c.pid), tostring(c.name), geo.width, geo.height, geo.x, geo.y, why))
end

client.connect_signal("manage", function(c)
  place(c)
  if c._lab126.width > 100 then
    client.focus = c
    c:raise()
  end
end)

-- Clients may not move/resize themselves: snap back to the WM's geometry.
client.connect_signal("property::geometry", function(c)
  local g = c._lab126
  if not g or c._snapping then return end
  local cur = c:geometry()
  if cur.x ~= g.x or cur.y ~= g.y or cur.width ~= g.width or cur.height ~= g.height then
    c._snapping = true
    gears.timer.delayed_call(function()
      if c.valid then c:geometry(g) end
      c._snapping = false
    end)
  end
end)

client.connect_signal("property::name", function(c)
  if not c._lab126 then return end
  log(string.format("rename pid=%s name=%q%s", tostring(c.pid), tostring(c.name),
    REPARSE and " (re-placing)" or " (ignored, parsed only at map)"))
  if REPARSE then place(c) end
end)

client.connect_signal("unmanage", function(c)
  log(string.format("unmanage pid=%s name=%q", tostring(c.pid), tostring(c.name)))
end)

-- Tap-to-focus like the device.
client.connect_signal("button::press", function(c) client.focus = c end)

-- A stand-in for the Kindle home screen, drawn under every client.
local home = wibox({
  x = 0, y = 0, width = screen.primary.geometry.width, height = screen.primary.geometry.height,
  visible = true, ontop = false, below = true, type = "desktop", bg = "#ffffff", fg = "#000000",
})
local label = wibox.widget.textbox()
label.align, label.valign = "center", "center"
label.font = "DejaVu Sans 22"
home:setup({ label, layout = wibox.layout.flex.vertical })

local function readfile(p)
  local f = io.open(p); if not f then return "?" end
  local s = f:read("*l"); f:close(); return s or "?"
end
gears.timer({
  timeout = 2, autostart = true, call_now = true,
  callback = function()
    label.markup = string.format(
      "<b>Kindle VM</b>\n(simulated home screen)\n\nlab126_gui: %s\npillow: %s\n\nssh -p 2222 root@localhost",
      readfile("/run/kindle-sim/lab126_gui"), readfile("/run/kindle-sim/pillow"))
  end,
})

log("awesome (lab126 emulation) started, screen " ..
  screen.primary.geometry.width .. "x" .. screen.primary.geometry.height)
