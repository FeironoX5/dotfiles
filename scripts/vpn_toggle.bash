#!/usr/bin/env bash
# ~/scripts/vpn_toggle.bash
# Toggles VPN on/off for waybar click

SCRIPT="${HOME}/.dotfiles/scripts/vpn.bash"

if pgrep -x nekobox_core >/dev/null 2>&1; then
    "$SCRIPT" stop
else
    "$SCRIPT" start
fi

# Signal waybar to refresh immediately
pkill -RTMIN+8 waybar 2>/dev/null || true
