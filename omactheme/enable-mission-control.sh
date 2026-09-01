#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.config/hypr/mission-control.lua"
MAIN="$HOME/.config/hypr/hyprland.lua"
STATE="$HOME/.local/state/omactheme"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$STATE/backups/mission-control-$STAMP"

mkdir -p "$BACKUP" "$(dirname "$TARGET")"
cp -a "$MAIN" "$BACKUP/hyprland.lua"
if [[ -e "$TARGET" ]]; then cp -a "$TARGET" "$BACKUP/mission-control.lua"; fi

# Remove the incompatible 0.55-only repository left by older installer runs.
if hyprpm list 2>/dev/null | grep -q 'Repository hyprexpo'; then
  hyprpm remove colonelpanic8/hyprexpo 2>/dev/null || \
    hyprpm remove hyprexpo 2>/dev/null || true
fi

hyprpm update
if ! hyprpm list 2>/dev/null | grep -q 'Repository hymission'; then
  hyprpm add https://github.com/gfhdhytghd/hymission
fi
hyprpm enable hymission
hyprpm reload

install -m 0644 "$ROOT/config/mission-control.lua" "$TARGET"
if ! grep -q 'require("hypr.mission-control")' "$MAIN"; then
  printf '\n-- Tahoe Mission Control (installed by omactheme).\nrequire("hypr.mission-control")\n' >> "$MAIN"
fi

# Ensure hyprpm plugins (hymission, hyprbars) are loaded on every Hyprland start.
# Without this, the plugins only load for the current session and the
# plugin.* config keys error out after every reboot.
AUTOSTART="$HOME/.config/hypr/autostart.lua"
if ! grep -q 'o.exec_on_start("hyprpm reload")' "$AUTOSTART" 2>/dev/null; then
  printf '\n-- Load hyprpm plugins (hyprbars, hymission) on every Hyprland start.\no.exec_on_start("hyprpm reload")\n' >> "$AUTOSTART"
fi

hyprctl reload
errors="$(hyprctl configerrors)"
if [[ -n "${errors//[[:space:]]/}" ]]; then
  printf 'Hyprland reported configuration errors:\n%s\n' "$errors" >&2
  exit 1
fi

printf 'Mission Control enabled. Backup: %s\n' "$BACKUP"
printf 'Gestures: 3-finger horizontal = workspaces; 4-finger vertical = overview.\n'
printf 'Keyboard: F3 or SUPER+grave = overview.\n'
