#!/bin/sh
STATE_FILE="/tmp/hypr_touchpad_state"
DEV="ftcs0038:00-2808:0106-touchpad"

# If a specific argument is passed (enable or disable), honor it
if [ "$1" = "enable" ]; then
    NEW_STATE=true
elif [ "$1" = "disable" ]; then
    NEW_STATE=false
else
    # Toggle state
    if [ -f "$STATE_FILE" ]; then
        CUR_STATE=$(cat "$STATE_FILE")
    else
        CUR_STATE="true"
    fi
    if [ "$CUR_STATE" = "true" ]; then
        NEW_STATE=false
    else
        NEW_STATE=true
    fi
fi

echo "$NEW_STATE" > "$STATE_FILE"
hyprctl repl "return hl.device({ name = \"$DEV\", enabled = $NEW_STATE })"
