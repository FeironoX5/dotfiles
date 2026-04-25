#!/usr/bin/env bash
# Waybar status provider. Called on interval + RTMIN+8 signal.
source "$(dirname "$0")/vpn_common.bash"

is_connecting() {
  [[ -f "$STATE" ]] && [[ "$(< "$STATE")" == "connecting" ]]
}

desired=$(< "$DESIRED_STATE" 2>/dev/null) || true
proc=false; tun=false
is_process_running && proc=true
is_tun_up         && tun=true

if $proc && $tun; then
  state="connected"
  text="On"
  tooltip="VPN connected (${TUN_IFACE} up)"
elif $proc && ! $tun; then
  state="loading"
  text="…"
  tooltip="VPN connecting…"
elif [[ "$desired" == "suspending" ]]; then
  # System went to sleep with VPN on — show as off until lid-open restores it
  state="disconnected"
  text="Off"
  tooltip="VPN suspended (lid closed)"
elif ! $proc && is_connecting; then
  # Race window: toggle fired but process not yet visible
  state="loading"
  text="…"
  tooltip="VPN starting…"
else
  clear_state
  state="disconnected"
  text="Off"
  tooltip="VPN disconnected"
fi

printf '{"text":"%s","class":"%s","alt":"%s","tooltip":"%s"}\n' \
  "$text" "$state" "$state" "$tooltip"
