#!/bin/sh
# Check if any backlight device has non-zero brightness or is active
ACTIVE_DEV=""
for d in /sys/class/backlight/*; do
    [ -d "$d" ] || continue
    cur=$(cat "$d/brightness" 2>/dev/null || echo 0)
    if [ "$cur" -gt 0 ]; then
        ACTIVE_DEV=$(basename "$d")
        break
    fi
done

# If none had > 0 (or all at 0%), fall back to first device found
if [ -z "$ACTIVE_DEV" ]; then
    for d in /sys/class/backlight/*; do
        [ -d "$d" ] || continue
        ACTIVE_DEV=$(basename "$d")
        break
    done
fi

if [ -n "$ACTIVE_DEV" ]; then
    brightnessctl -d "$ACTIVE_DEV" set "$@"
else
    brightnessctl set "$@"
fi
