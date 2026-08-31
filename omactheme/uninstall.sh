#!/bin/bash
set -euo pipefail

STATE_DIR="$HOME/.local/state/omactheme"
LATEST="$STATE_DIR/latest-backup"
[[ -f "$LATEST" ]] || { echo "No Tahoe Dark installer backup found" >&2; exit 1; }
BACKUP="$(<"$LATEST")"
[[ -d "$BACKUP" ]] || { echo "Backup does not exist: $BACKUP" >&2; exit 1; }

restore_path() {
  local source="$BACKUP/$1" dest="$2" absent="$BACKUP/.absent/$1"
  if [[ -e "$source" || -L "$source" ]]; then
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -a "$source" "$dest"
  elif [[ -e "$absent" ]]; then
    rm -rf "$dest"
  fi
}

restore_path "theme" "$HOME/.config/omarchy/themes/tahoe-dark"
restore_path "dock" "$HOME/.config/omarchy/plugins/dock"
restore_path "bin/tahoe-window" "$HOME/.local/bin/tahoe-window"
restore_path "hooks/80-tahoe-dark" "$HOME/.config/omarchy/hooks/theme-set.d/80-tahoe-dark"
restore_path "hypr/tahoe-overrides.lua" "$HOME/.config/hypr/tahoe-overrides.lua"
restore_path "hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.lua"

hyprpm disable hyprbars >/dev/null 2>&1 || true
previous="$(<"$BACKUP/previous-theme")"
if [[ -n "$previous" ]]; then omarchy theme set "$previous"; fi
hyprctl reload
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
echo "Tahoe Dark removed; restored $BACKUP"
