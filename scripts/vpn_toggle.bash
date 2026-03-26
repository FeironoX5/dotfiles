#!/usr/bin/env bash
# vpn_toggle.bash — Toggle goxray VPN on/off for Waybar button
# Status is determined via process presence + tun interface, no log file needed.

BIN="/home/glebkiva/scripts/goxray_cli_linux_amd64"
ARGS_FILE="/home/glebkiva/scripts/goxray_cli_args"
TUN_IFACE="tun0"
STATE="/run/user/$(id -u)/goxray_cli.state"
WAYBAR_SIGNAL="8"
CONNECT_TIMEOUT=15  # seconds to wait for tun0 before giving up

# --- Helpers ---

refresh_waybar() {
  pkill -RTMIN+"$WAYBAR_SIGNAL" -x waybar 2>/dev/null || true
}

is_process_running() {
  pgrep -f -- "^${BIN}( |$)" >/dev/null 2>&1
}

is_tun_up() {
  ip link show "$TUN_IFACE" 2>/dev/null | grep -q "state UP\|UNKNOWN"
}

set_state() {
  mkdir -p "$(dirname "$STATE")"
  printf '%s' "$1" > "$STATE"
}

clear_state() {
  rm -f "$STATE" 2>/dev/null || true
}

# Background watcher: polls until tun0 is up (or process dies / timeout),
# then signals waybar once so it redraws with "connected" (or "disconnected").
wait_for_tun_and_notify() {
  local deadline=$(( $(date +%s) + CONNECT_TIMEOUT ))

  while (( $(date +%s) < deadline )); do
    if ! is_process_running; then
      # Process died unexpectedly — clean up and notify
      clear_state
      refresh_waybar
      return
    fi

    if is_tun_up; then
      # Interface is up — connected!
      clear_state
      refresh_waybar
      return
    fi

    sleep 1
  done

  # Timeout reached — tun never came up; clean up
  clear_state
  refresh_waybar
}

# --- Actions ---

start_vpn() {
  local args=""
  [[ -f "$ARGS_FILE" ]] && args=$(< "$ARGS_FILE")

  # Signal waybar immediately so it shows "connecting"
  set_state "connecting"
  refresh_waybar

  # Launch detached; discard output (no log accumulation)
  nohup "$BIN" $args >/dev/null 2>&1 &

  # Spawn background watcher — signals waybar once tun0 is up
  wait_for_tun_and_notify &

  echo "VPN connecting"
}

stop_vpn() {
  pkill -f -- "^${BIN}( |$)" 2>/dev/null || true
  clear_state
  refresh_waybar
  echo "VPN disconnected"
}

# --- Main ---

main() {
  if is_process_running; then
    stop_vpn
  else
    start_vpn
  fi
}

main "$@"