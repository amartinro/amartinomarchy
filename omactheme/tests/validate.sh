#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

jq empty "$root/dock/manifest.json"
bash -n "$root/bin/tahoe-window" "$root/hooks/theme-set" "$root/install.sh" \
  "$root/finish-install.sh" "$root/enable-mission-control.sh" "$root/uninstall.sh"
python3 - "$root/theme/tahoe-dark/colors.toml" "$root/theme/tahoe-dark/shell.toml" <<'PY'
import sys, tomllib
for path in sys.argv[1:]:
    with open(path, "rb") as handle:
        tomllib.load(handle)
PY
test -s "$root/theme/tahoe-dark/backgrounds/tahoe-night-glass.png"
file "$root/theme/tahoe-dark/backgrounds/tahoe-night-glass.png" | grep -q 'PNG image data'
echo "Tahoe Dark static validation passed"
