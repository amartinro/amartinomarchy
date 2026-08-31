-- Tahoe Dark: compositor chrome and motion.
local active_border = "rgba(9ca4b31f)"
local inactive_border = "rgba(ffffff0d)"

hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 7,
    border_size = 1,
    resize_on_border = true,
    col = {
      active_border = active_border,
      inactive_border = inactive_border,
    },
  },
  decoration = {
    rounding = 18,
    rounding_power = 3.0,
    active_opacity = 1.0,
    inactive_opacity = 0.965,
    fullscreen_opacity = 1.0,
    shadow = {
      enabled = true,
      range = 34,
      render_power = 3,
      color = "rgba(00000078)",
      color_inactive = "rgba(00000042)",
      offset = { 0, 8 },
      scale = 0.97,
    },
    blur = {
      enabled = true,
      -- A light glass diffusion: shapes and color remain legible behind
      -- menus instead of collapsing into a dense frosted wash.
      size = 7,
      passes = 2,
      noise = 0.012,
      contrast = 0.98,
      brightness = 0.96,
      vibrancy = 0.12,
      vibrancy_darkness = 0.08,
      popups = true,
      popups_ignorealpha = 0.16,
      new_optimizations = true,
      xray = false,
    },
  },
  group = {
    col = {
      border_active = active_border,
      border_inactive = inactive_border,
    },
  },
  plugin = {
    hyprbars = {
      enabled = true,
      bar_color = "rgba(25272eee)",
      bar_height = 38,
      bar_blur = true,
      col = { text = "rgba(f2f3f7e6)" },
      bar_title_enabled = true,
      bar_text_size = 13,
      bar_text_weight = "medium",
      bar_text_font = "Sans",
      bar_text_align = "center",
      bar_buttons_alignment = "left",
      bar_part_of_window = true,
      bar_precedence_over_border = false,
      bar_padding = 12,
      bar_button_padding = 7,
      icon_on_hover = true,
      inactive_button_color = "rgba(777982ff)",
      on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
    },
  },
})

hl.curve("tahoeEase", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1 } } })
hl.curve("tahoeSpring", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
-- Hyprland measures this value in deciseconds, so lower means faster.
-- These durations are roughly 25% shorter than the original Tahoe profile.
hl.animation({ leaf = "windows", enabled = true, speed = 4.2, bezier = "tahoeEase" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.3, bezier = "tahoeSpring", style = "popin 95%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4.8, bezier = "tahoeEase", style = "popin 97%" })
hl.animation({ leaf = "fade", enabled = true, speed = 4.5, bezier = "tahoeEase" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 4.2, bezier = "tahoeEase" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 4.0, bezier = "tahoeEase" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.9, bezier = "tahoeEase", style = "fade" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 3.6, bezier = "tahoeEase", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 3.2, bezier = "tahoeEase", style = "fade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4.3, bezier = "tahoeEase", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4.3, bezier = "tahoeEase", style = "slidevert" })

hl.layer_rule({ match = { namespace = ".*omarchy.*" }, blur = true, blur_popups = true, ignore_alpha = 0.12 })
hl.layer_rule({ match = { namespace = "local-dock" }, blur = true, blur_popups = true, ignore_alpha = 0.08 })

-- Fullscreen content should have no visible frame or titlebar.
hl.window_rule({ match = { fullscreen = true }, border_size = 0, rounding = 0 })

-- hyprbars declarations are ordered right-to-left. With left alignment this
-- yields the canonical red, yellow, green traffic-light order.
pcall(function()
  hl.plugin.hyprbars.add_button({
    bg_color = "rgb(28C840)", fg_color = "rgb(163C1D)", size = 13, icon = "+",
    action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
  })
  hl.plugin.hyprbars.add_button({
    bg_color = "rgb(FEBC2E)", fg_color = "rgb(765B10)", size = 13, icon = "−",
    action = [[hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })']],
  })
  hl.plugin.hyprbars.add_button({
    bg_color = "rgb(FF5F57)", fg_color = "rgb(791D19)", size = 13, icon = "×",
    action = [[hyprctl dispatch 'hl.dsp.window.close()']],
  })
end)
