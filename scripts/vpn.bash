#!/usr/bin/env bash
# ~/.dotfiles/scripts/vpn.bash
# NekoBox headless VPN wrapper + waybar integration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${HOME}/.config/nekoray"
LOG_DIR="${HOME}/.local/log"
mkdir -p "$LOG_DIR"

PID_FILE="/tmp/nekobox-vpn.pid"
LOG_FILE="${LOG_DIR}/nekobox-vpn.log"
DISPLAY_NUM=":99"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN${NC} $*" | tee -a "$LOG_FILE"
}

err() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ERR${NC} $*" | tee -a "$LOG_FILE"
}

is_running() {
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null
}

core_running() {
    pgrep -x nekobox_core >/dev/null 2>&1
}

find_xvfb() {
    if command -v xvfb-run >/dev/null 2>&1; then
        echo "xvfb-run"
    elif command -v Xvfb >/dev/null 2>&1; then
        echo "xvfb"
    else
        echo ""
    fi
}

start_vpn() {
    if is_running; then
        log "VPN already running (PID: $(cat "$PID_FILE"))"
        return 0
    fi

    if ! command -v nekobox >/dev/null 2>&1; then
        err "nekobox not found in PATH"
        return 1
    fi

    local xvfb_tool
    xvfb_tool=$(find_xvfb)
    if [[ -z "$xvfb_tool" ]]; then
        err "Xvfb not found. Install: sudo dnf install xorg-x11-server-Xvfb"
        return 1
    fi

    log "Starting nekobox headless VPN..."

    rm -f /tmp/.X99-lock

    export QT_QPA_PLATFORM=xcb
    export QT_QPA_PLATFORMTHEME=gtk2
    export DISPLAY="${DISPLAY_NUM}"

    if [[ "$xvfb_tool" == "xvfb-run" ]]; then
        nohup xvfb-run -a --server-args="-screen 0 1x1x24 -ac +extension GLX +render -noreset" \
            nekobox > "$LOG_FILE" 2>&1 &
    else
        nohup Xvfb "${DISPLAY_NUM}" -screen 0 1x1x24 -ac +extension GLX +render -noreset \
            > "${LOG_DIR}/xvfb.log" 2>&1 &
        sleep 1
        nohup nekobox > "$LOG_FILE" 2>&1 &
    fi

    local pid=$!
    echo "$pid" > "$PID_FILE"

    log "Waiting for nekobox_core to start..."
    for i in {1..30}; do
        if core_running; then
            log "VPN active! SOCKS: 127.0.0.1:2080"
            return 0
        fi
        sleep 1
    done

    err "nekobox_core failed to start. Check: $LOG_FILE"
    stop_vpn
    return 1
}

stop_vpn() {
    log "Stopping VPN..."
    sudo killall nekobox_core 2>/dev/null || true
    sleep 1
    killall nekobox 2>/dev/null || true
    killall Xvfb 2>/dev/null || true
    rm -f "$PID_FILE" /tmp/.X99-lock
    gsettings set org.gnome.system.proxy mode 'none' 2>/dev/null || true
    log "VPN stopped."
}

toggle_vpn() {
    if core_running; then
        stop_vpn
    else
        start_vpn
    fi
}

status_vpn() {
    if core_running; then
        log "VPN: RUNNING | SOCKS: 127.0.0.1:2080"
    else
        log "VPN: STOPPED"
    fi
}

repair_service() {
    log "Repairing..."
    stop_vpn
    sleep 1
    rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
    if [[ -f /usr/bin/nekobox_core ]]; then
        sudo chmod u-s /usr/bin/nekobox_core 2>/dev/null || true
        sudo setcap cap_net_admin=ep /usr/bin/nekobox_core 2>/dev/null || true
    fi
    start_vpn
}

restart_vpn() {
    stop_vpn
    sleep 2
    start_vpn
}

logs() {
    [[ -f "$LOG_FILE" ]] && tail -f "$LOG_FILE" || err "No log file"
}

# ─── Waybar JSON output ───
waybar_status() {
    if core_running; then
        echo '{"text": "ON", "tooltip": "NekoBox VPN active\nSOCKS: 127.0.0.1:2080", "class": "connected"}'
    else
        echo '{"text": "OFF", "tooltip": "VPN disconnected", "class": "disconnected"}'
    fi
}

waybar_toggle() {
    toggle_vpn >/dev/null 2>&1
    pkill -RTMIN+8 waybar 2>/dev/null || true
}

case "${1:-status}" in
    start|up|on)      start_vpn ;;
    stop|down|off)    stop_vpn ;;
    restart|reload)   restart_vpn ;;
    toggle)           toggle_vpn ;;
    status|st)        status_vpn ;;
    repair)           repair_service ;;
    logs|log)         logs ;;
    waybar)           waybar_status ;;
    waybar-toggle)    waybar_toggle ;;
    *)
        echo "Usage: $(basename "$0") {start|stop|restart|toggle|status|repair|logs|waybar|waybar-toggle}"
        exit 1
        ;;
esac
