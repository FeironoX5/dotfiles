#!/usr/bin/env bash
source "$(dirname "$0")/vpn_common.bash"

# --- Lock: prevent double-invocation on rapid clicks ---
acquire_lock() {
  if ! mkdir "$LOCK" 2>/dev/null; then
    echo "VPN toggle already in progress, aborting." >&2
    exit 0
  fi
  trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
}

# --- Background watcher: clears "connecting" once tun is up or process dies ---
wait_for_tun_and_notify() {
  local deadline=$(( $(date +%s) + CONNECT_TIMEOUT ))
  while (( $(date +%s) < deadline )); do
    if ! is_process_running; then
      clear_state; refresh_waybar; return
    fi
    if is_tun_up; then
      clear_state; refresh_waybar; return
    fi
    sleep 1
  done
  clear_state; refresh_waybar
}

# Hard memory cap: kernel enforces this via cgroupv2 — no polling needed.
MEMORY_MAX_BYTES=$(( 300 * 1024 * 1024 ))  # 300 MB

# Write memory limit directly into goxray's cgroupv2 hierarchy.
# Requires cgroup delegation — see cgroup-delegation.conf if this logs a warning.
apply_cgroup_limit() {
  local pid=$1
  local cg
  cg=$(awk -F: '/^0::/{print $3}' "/proc/${pid}/cgroup" 2>/dev/null)
  [[ -z "$cg" ]] && return

  local cg_dir="/sys/fs/cgroup${cg}"
  if [[ -w "${cg_dir}/memory.max" ]]; then
    echo "$MEMORY_MAX_BYTES" > "${cg_dir}/memory.max"
    echo "0"                 > "${cg_dir}/memory.swap.max"
    logger -t vpn-watchdog "cgroup memory.max=${MEMORY_MAX_BYTES} applied to pid ${pid}"
  else
    logger -t vpn-watchdog "cannot write cgroup memory.max for pid ${pid} — delegation not enabled"
  fi
}

# Background monitor: restarts goxray if it dies while desired=on.
# Does nothing if desired=off or desired=suspending (lid closed, system sleeping).
restart_on_death() {
  local pid=$1
  while [[ -d "/proc/${pid}" ]]; do
    sleep 2
  done

  local desired
  desired=$(< "$DESIRED_STATE" 2>/dev/null) || true
  [[ "$desired" != "on" ]] && return

  logger -t vpn-watchdog "goxray pid ${pid} exited (OOM or crash), restarting"
  sleep 1
  start_vpn
}

start_vpn() {
  local args=""
  [[ -f "$ARGS_FILE" ]] && args=$(< "$ARGS_FILE")

  printf 'on' > "$DESIRED_STATE"
  set_state "connecting"
  refresh_waybar

  # shellcheck disable=SC2086
  nohup "$BIN" $args >/dev/null 2>&1 &
  local goxray_pid=$!

  apply_cgroup_limit "$goxray_pid"

  wait_for_tun_and_notify &
  restart_on_death "$goxray_pid" &
  echo "VPN connecting…"
}

stop_vpn() {
  printf 'off' > "$DESIRED_STATE"
  pkill -f -- "^${BIN}( |$)" 2>/dev/null || true
  clear_state
  refresh_waybar
  echo "VPN disconnected"
}

main() {
  acquire_lock
  if is_process_running; then stop_vpn; else start_vpn; fi
}

main "$@"
