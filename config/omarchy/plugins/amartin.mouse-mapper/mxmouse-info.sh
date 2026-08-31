#!/usr/bin/env bash
# Detect the Logitech MX Master 3 and report its buttons as JSON.
# Output: {"connected":bool,"device":"/dev/input/eventN","buttons":[272,...]}
set -u

for d in /sys/class/input/event*; do
  name=$(cat "$d/device/name" 2>/dev/null) || continue
  [[ "$name" == *"MX Master 3"* ]] || continue

  key=$(cat "$d/device/capabilities/key" 2>/dev/null) || key=""
  buttons=""
  for code in 272 273 274 275 276; do
    word=$((code / 64))
    bit=$((code % 64))
    w=$(echo "$key" | awk -v w="$word" '{print $(w + 1)}')
    if [[ -n "$w" ]] && (( (0x"$w" >> bit) & 1 )); then
      buttons+="${buttons:+,}$code"
    fi
  done

  printf '{"connected":true,"path":"/dev/input/%s","buttons":[%s]}\n' "$(basename "$d")" "$buttons"
  exit 0
done

printf '{"connected":false,"device":"","buttons":[]}\n'
