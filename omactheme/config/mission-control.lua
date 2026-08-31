-- Tahoe Mission Control for Omarchy.
-- Requires hymission, installed through hyprpm by enable-mission-control.sh.

hl.config({
  gestures = {
    workspace_swipe_distance = 240,
    workspace_swipe_cancel_ratio = 0.34,
    workspace_swipe_min_speed_to_force = 24,
    workspace_swipe_create_new = true,
    workspace_swipe_direction_lock = true,
    workspace_swipe_direction_lock_threshold = 10,
    workspace_swipe_forever = false,
  },
  plugin = {
    hymission = {
      outer_padding_top = 70,
      outer_padding_right = 28,
      outer_padding_bottom = 30,
      outer_padding_left = 28,
      row_spacing = 24,
      column_spacing = 24,
      min_window_length = 120,
      min_preview_short_edge = 32,
      small_window_boost = 1.30,
      max_preview_scale = 0.94,
      workspace_overview_max_preview_scale = 0.94,
      min_slot_scale = 0.10,
      one_workspace_per_row = 0,
      layout_engine = "mission-control",
      layout_engine_forceall = "mission-control",
      layout_engine_all = "mission-control",
      layout_engine_onlycurrentworkspace = "mission-control",

      multi_workspace_sort_recent_first = 1,
      only_active_workspace = 0,
      only_active_monitor = 0,
      show_special = 0,
      workspace_change_keeps_overview = 1,
      selected_expand_scale = 1.12,
      hover_expand_scale = 1.08,
      overview_focus_follows_mouse = 1,
      show_focus_indicator = 0,
      grouped_windows_policy = "expanded",
      hover_relayout_duration = 110,
      hover_relayout_curve = "ease_out_cubic",
      gesture_invert_vertical = 0,

      workspace_strip_anchor = "top",
      workspace_strip_empty_mode = "existing",
      workspace_strip_thickness = 138,
      workspace_strip_gap = 18,
      hide_bar_when_strip = 1,
      hide_hyprbars_during_overview = 1,
      bar_single_mission_control = 0,
      hide_bar_animation = 1,
      hide_bar_animation_blur = 1,
      hide_bar_animation_move_multiplier = 0.75,
      hide_bar_animation_scale_divisor = 1.08,
      hide_bar_animation_alpha_end = 0,

      backdrop_blur = 1,
      backdrop_color = "rgba(08090c70)",
      focus_hover_color = "rgba(f2f3f78c)",
      focus_selected_color = "rgba(7c91fff2)",
      focus_hover_thickness = 2,
      focus_selected_thickness = 3,
      workspace_strip_inactive_tint_color = "rgba(08090c42)",
      window_decoration_enabled = 1,
      close_button_enabled = 0,
      pick_labels_enabled = 0,
      toggle_switch_mode = 0,
    },
  },
})

-- Direct 1:1 workspace navigation. Hymission keeps this working in overview.
hl.plugin.hymission.gesture({
  fingers = 3,
  direction = "horizontal",
  action = "workspace",
})

-- macOS-style Mission Control: windows from the current desktop in the main
-- area and the persistent desktop strip above them.
hl.plugin.hymission.gesture({
  fingers = 4,
  direction = "vertical",
  action = "toggle",
  args = "onlycurrentworkspace",
})

local function toggle_mission_control()
  hl.plugin.hymission.toggle("onlycurrentworkspace")
end

-- Both keys were unassigned in the current Omarchy setup.
o.bind("F3", "Mission Control", toggle_mission_control)
o.bind("SUPER + GRAVE", "Mission Control", toggle_mission_control)
