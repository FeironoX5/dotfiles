#!/usr/bin/env bash
# ~/scripts/vpn_check.bash
# Returns JSON for waybar custom/vpn module

PID_FILE="/tmp/nekobox-vpn.pid"
LOG_FILE="${HOME}/.local/log/nekobox-vpn.log"

# Check if nekobox_core is actually running
if pgrep -x nekobox_core >/dev/null 2>&1; then
    # Get connection info from log if available
    if [[ -f "$LOG_FILE" ]]; then
        # Check for errors in last 10 lines
        if tail -10 "$LOG_FILE" 2>/dev/null | grep -qi "error\|failed\|disconnect"; then
            echo '{"text": "ERR", "tooltip": "VPN error. Check logs.", "class": "error"}'
            exit 0
        fi
    fi
    echo '{"text": "ON", "tooltip": "NekoBox VPN active\nSOCKS: 127.0.0.1:2080", "class": "connected"}'
else
    echo '{"text": "OFF", "tooltip": "VPN disconnected", "class": "disconnected"}'
fi
