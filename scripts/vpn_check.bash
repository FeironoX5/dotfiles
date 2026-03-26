#!/usr/bin/env bash
# vpn_check.bash — Waybar status script for goxray VPN
# Determines status via: process presence + tun interface state
# No log file dependency.

BIN="/home/glebkiva/scripts/goxray_cli_linux_amd64"
TUN_IFACE="tun0"
STATE="/run/user/$(id -u)/goxray_cli.state"

# --- Checks ---

is_process_running() {
  pgrep -f -- "^${BIN}( |$)" >/dev/null 2>&1
}

is_tun_up() {
  ip link show "$TUN_IFACE" 2>/dev/null | grep -q "state UP\|UNKNOWN"
}

is_connecting() {
  [[ -f "$STATE" ]] && [[ "$(< "$STATE")" == "connecting" ]]
}

# --- Main logic ---

proc=false
tun=false

is_process_running && proc=true
is_tun_up         && tun=true

if $proc && $tun; then
  state="connected"
  text="On"
  tooltip="VPN connected (${TUN_IFACE} up)"

elif $proc && ! $tun; then
  # Process is alive but interface not yet up — still connecting
  state="loading"
  text="..."
  tooltip="VPN connecting..."

elif ! $proc && is_connecting; then
  # Race window: toggle just fired, process not yet visible
  state="loading"
  text="..."
  tooltip="VPN starting..."

else
  # Clean up stale state file if process is gone
  rm -f "$STATE" 2>/dev/null || true
  state="disconnected"
  text="Off"
  tooltip="VPN disconnected"
fi

printf '{"text":"%s","class":"%s","alt":"%s","tooltip":"%s"}\n' \
  "$text" "$state" "$state" "$tooltip"