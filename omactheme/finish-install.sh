#!/bin/bash
set -euo pipefail

# Run from a normal terminal so sudo/fprintd can authenticate interactively.
if ! hyprpm list 2>/dev/null | grep -q 'hyprland-plugins'; then
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
echo "Tahoe Dark is active"
