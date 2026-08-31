-- Loaded after user looknfeel.lua so Tahoe keeps its larger continuous corners.
local state = os.getenv("HOME") .. "/.local/state/omarchy/current/theme.name"
local file = io.open(state, "r")
local theme = file and (file:read("*l") or "") or ""
if file then file:close() end

if theme == "tahoe-dark" then
  hl.config({
    decoration = {
      rounding = 18,
      rounding_power = 3.0,
    },
  })
end
