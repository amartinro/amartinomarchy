#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
STATE_DIR="$HOME/.local/state/omactheme"
BACKUP="$STATE_DIR/backups/$STAMP"
THEME_DEST="$HOME/.config/omarchy/themes/tahoe-dark"
DOCK_DEST="$HOME/.config/omarchy/plugins/dock"
HOOK_DEST="$HOME/.config/omarchy/hooks/theme-set.d/80-tahoe-dark"

mkdir -p "$BACKUP" "$STATE_DIR" "$HOME/.config/omarchy/themes" \
  "$HOME/.config/omarchy/plugins" "$HOME/.config/omarchy/hooks/theme-set.d" \
  "$HOME/.config/hypr" "$HOME/.local/bin"

backup_path() {
  local path="$1" label="$2"
  if [[ -e "$path" || -L "$path" ]]; then
    mkdir -p "$BACKUP/$(dirname "$label")"
    cp -a "$path" "$BACKUP/$label"
  else
    mkdir -p "$BACKUP/.absent/$(dirname "$label")"
    : > "$BACKUP/.absent/$label"
  fi
}

previous_theme="$(omarchy theme current 2>/dev/null || true)"
printf '%s\n' "$previous_theme" > "$BACKUP/previous-theme"

backup_path "$THEME_DEST" "theme"
backup_path "$DOCK_DEST" "dock"
backup_path "$HOME/.local/bin/tahoe-window" "bin/tahoe-window"
backup_path "$HOOK_DEST" "hooks/80-tahoe-dark"
backup_path "$HOME/.config/hypr/tahoe-overrides.lua" "hypr/tahoe-overrides.lua"
backup_path "$HOME/.config/hypr/hyprland.lua" "hypr/hyprland.lua"

rm -rf "$THEME_DEST"
mkdir -p "$THEME_DEST"
cp -a "$ROOT/theme/tahoe-dark/." "$THEME_DEST/"

rm -rf "$DOCK_DEST"
mkdir -p "$DOCK_DEST"
cp -a "$ROOT/dock/." "$DOCK_DEST/"

install -m 0755 "$ROOT/bin/tahoe-window" "$HOME/.local/bin/tahoe-window"
install -m 0755 "$ROOT/hooks/theme-set" "$HOOK_DEST"
install -m 0644 "$ROOT/config/tahoe-overrides.lua" "$HOME/.config/hypr/tahoe-overrides.lua"

if ! grep -q 'require("hypr.tahoe-overrides")' "$HOME/.config/hypr/hyprland.lua"; then
  printf '\n-- Tahoe Dark post-user look overrides (installed by omactheme).\nrequire("hypr.tahoe-overrides")\n' \
    >> "$HOME/.config/hypr/hyprland.lua"
fi

printf '%s\n' "$BACKUP" > "$STATE_DIR/latest-backup"

if ! hyprpm list 2>/dev/null | grep -q '^hyprbars'; then
  hyprpm update
  hyprpm add https://github.com/hyprwm/hyprland-plugins
fi
hyprpm enable hyprbars

omarchy theme set tahoe-dark
hyprctl reload
errors="$(hyprctl configerrors)"
if [[ -n "${errors//[[:space:]]/}" ]]; then
  printf 'Hyprland reported configuration errors:\n%s\n' "$errors" >&2
  exit 1
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy-dock reload >/dev/null 2>&1 || true
printf 'Tahoe Dark installed. Backup: %s\n' "$BACKUP"
