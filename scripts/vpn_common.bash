#!/usr/bin/env bash
# vpn_common.bash — source this in all VPN scripts, do not execute directly

BIN="/usr/local/bin/goxray"
ARGS_FILE="/home/glebkiva/scripts/goxray_cli_args"
TUN_IFACE="tun0"

_RUN_DIR="/run/user/$(id -u)"
STATE="${_RUN_DIR}/goxray_cli.state"
DESIRED_STATE="${_RUN_DIR}/goxray_desired.state"
LOCK="${_RUN_DIR}/goxray_toggle.lock"

WAYBAR_SIGNAL="8"
CONNECT_TIMEOUT=15

# Possible values for DESIRED_STATE:
#   on         — user wants VPN running
#   off        — user wants VPN stopped
#   suspending — lid closed, system going to sleep; restart_on_death must not restart

is_process_running() {
  pgrep -f -- "^${BIN}( |$)" >/dev/null 2>&1
}

is_tun_up() {
  ip link show "$TUN_IFACE" 2>/dev/null | grep -qE "state (UP|UNKNOWN)"
}

set_state() {
  mkdir -p "$_RUN_DIR"
  printf '%s' "$1" > "$STATE"
}

clear_state() {
  rm -f "$STATE"
}

refresh_waybar() {
  pkill -RTMIN+"$WAYBAR_SIGNAL" -x waybar 2>/dev/null || true
}
