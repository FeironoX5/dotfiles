#!/usr/bin/env bash
set -u

if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" && -z "${VPN_KEEP_ROOT:-}" && "${1:-}" != "install-config-root" && "${1:-}" != "fix-service-root" ]]; then
  exec /usr/bin/env -u TERMINFO -u TERMINFO_DIRS /usr/bin/sudo -u "$SUDO_USER" -- "$0" "$@"
fi

SERVICE="${VPN_SERVICE:-sing-box.service}"
LEGACY_SERVICE="${VPN_LEGACY_SERVICE:-xray-vpn}"
LEGACY_PROCESS_PATTERN="${VPN_LEGACY_PROCESS_PATTERN:-(^|/)goxray_cli_linux_amd64( |$)}"
CONFIG_ARGS_FILE="${VPN_CONFIG_ARGS_FILE:-${HOME}/scripts/goxray_cli_args}"
CONFIG_GENERATOR="${VPN_CONFIG_GENERATOR:-${HOME}/scripts/sing-box-vless-config.bash}"
CONFIG_PATH="${VPN_CONFIG_PATH:-/etc/sing-box/config.json}"
CONFIG_OWNER="${VPN_CONFIG_OWNER:-root}"
CONFIG_GROUP="${VPN_CONFIG_GROUP:-root}"
CONFIG_MODE="${VPN_CONFIG_MODE:-0644}"
CONFIG_DIR_MODE="${VPN_CONFIG_DIR_MODE:-0755}"
TOGGLE_HELPER="${VPN_TOGGLE_HELPER:-/home/glebkiva/scripts/vpn_toggle.bash}"
SERVICE_DROPIN_DIR="${VPN_SERVICE_DROPIN_DIR:-/etc/systemd/system/sing-box.service.d}"
SERVICE_RECONNECT_DROPIN="${VPN_SERVICE_RECONNECT_DROPIN:-${SERVICE_DROPIN_DIR}/10-reconnect.conf}"
SING_BOX="${SING_BOX:-/usr/bin/sing-box}"
SYSTEMCTL="${SYSTEMCTL:-/usr/bin/systemctl}"
SUDO="${SUDO:-/usr/bin/sudo}"
TIMEOUT="${TIMEOUT:-/usr/bin/timeout}"
TUN_IFACE="${VPN_TUN_IFACE:-tun0}"

RUN_DIR="/run/user/$(id -u)"
STATE="${RUN_DIR}/sing_box.state"
DESIRED_STATE="${RUN_DIR}/sing_box_desired.state"
LOCK="${RUN_DIR}/sing_box_toggle.lock"
WAYBAR_SIGNAL="8"
SYSTEMCTL_TIMEOUT="8s"

mkdir_run_dir() {
  mkdir -p "$RUN_DIR" 2>/dev/null || true
}

service_state() {
  "$SYSTEMCTL" is-active "$SERVICE" 2>/dev/null || true
}

service_result() {
  "$SYSTEMCTL" show "$SERVICE" -P Result 2>/dev/null || true
}

service_substate() {
  "$SYSTEMCTL" show "$SERVICE" -P SubState 2>/dev/null || true
}

service_restarts() {
  "$SYSTEMCTL" show "$SERVICE" -P NRestarts 2>/dev/null || true
}

config_has_vless_tun() {
  if command -v jq >/dev/null 2>&1; then
    jq -e '
      any(.inbounds[]?; .type == "tun") and
      any(.outbounds[]?; .type == "vless")
    ' /etc/sing-box/config.json >/dev/null 2>&1
  else
    python3 - <<'PY' >/dev/null 2>&1
import json
with open("/etc/sing-box/config.json", "r", encoding="utf-8") as f:
    config = json.load(f)
if not any(item.get("type") == "tun" for item in config.get("inbounds", [])):
    raise SystemExit(1)
if not any(item.get("type") == "vless" for item in config.get("outbounds", [])):
    raise SystemExit(1)
PY
  fi
}

set_state() {
  mkdir_run_dir
  printf '%s' "$1" > "$STATE" 2>/dev/null || true
}

clear_state() {
  rm -f "$STATE" 2>/dev/null || true
}

transient_state() {
  cat "$STATE" 2>/dev/null || true
}

set_desired() {
  mkdir_run_dir
  printf '%s' "$1" > "$DESIRED_STATE" 2>/dev/null || true
}

desired_state() {
  cat "$DESIRED_STATE" 2>/dev/null || true
}

is_tun_up() {
  ip link show "$TUN_IFACE" 2>/dev/null | grep -qE "state (UP|UNKNOWN)"
}

refresh_waybar() {
  pkill -RTMIN+"$WAYBAR_SIGNAL" -x waybar 2>/dev/null || true
}

json() {
  printf '{"text":"%s","class":"%s","alt":"%s","tooltip":"%s"}\n' "$1" "$2" "$2" "$3"
}

sudo_systemctl() {
  "$TIMEOUT" "$SYSTEMCTL_TIMEOUT" /usr/bin/env -u TERMINFO -u TERMINFO_DIRS \
    "$SUDO" -n "$SYSTEMCTL" "$@" "$SERVICE"
}

sudo_command() {
  "$TIMEOUT" "$SYSTEMCTL_TIMEOUT" /usr/bin/env -u TERMINFO -u TERMINFO_DIRS \
    "$SUDO" -n "$@"
}

sudo_systemctl_unit() {
  "$TIMEOUT" "$SYSTEMCTL_TIMEOUT" /usr/bin/env -u TERMINFO -u TERMINFO_DIRS \
    "$SUDO" -n "$SYSTEMCTL" "$@"
}

ensure_service_policy() {
  sudo_command "$TOGGLE_HELPER" fix-service-root >/dev/null 2>&1 || true
}

acquire_lock() {
  mkdir_run_dir
  if ! mkdir "$LOCK" 2>/dev/null; then
    return 1
  fi
  trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
}

legacy_process_running() {
  pgrep -f -- "$LEGACY_PROCESS_PATTERN" >/dev/null 2>&1
}

wait_for_legacy_exit() {
  local attempt
  for attempt in 1 2 3 4 5; do
    legacy_process_running || return 0
    sleep 0.2
  done
  return 1
}

stop_legacy_vpn() {
  sudo_systemctl_unit stop "$LEGACY_SERVICE" >/dev/null 2>&1 || true
  pkill -f -- "$LEGACY_PROCESS_PATTERN" >/dev/null 2>&1 || true
  if legacy_process_running; then
    sudo_command /usr/bin/pkill -f goxray_cli_linux_amd64 >/dev/null 2>&1 || true
  fi
  wait_for_legacy_exit >/dev/null 2>&1 || true
}

cleanup_stale_tun() {
  legacy_process_running && return
  case "$(service_state)" in
    active|activating|reloading|deactivating) return ;;
  esac
  is_tun_up || return
  sudo_command /usr/sbin/ip link delete "$TUN_IFACE" >/dev/null 2>&1 || \
    sudo_command /usr/bin/ip link delete "$TUN_IFACE" >/dev/null 2>&1 || true
}

refresh_config() {
  local tmp config_dir config_mode_norm config_dir_mode_norm
  mkdir_run_dir
  tmp="${RUN_DIR}/sing-box-config.json"
  config_dir="$(dirname "$CONFIG_PATH")"
  config_mode_norm="${CONFIG_MODE#0}"
  config_dir_mode_norm="${CONFIG_DIR_MODE#0}"

  if [[ ! -x "$CONFIG_GENERATOR" ]]; then
    json "Err" "failed" "Config generator is missing: ${CONFIG_GENERATOR}"
    return 1
  fi

  if ! "$CONFIG_GENERATOR" "$CONFIG_ARGS_FILE" > "$tmp"; then
    json "Err" "failed" "Cannot generate sing-box config from ${CONFIG_ARGS_FILE}"
    return 1
  fi

  if ! "$SING_BOX" check -c "$tmp" >/dev/null 2>&1; then
    json "Err" "failed" "Generated sing-box config did not pass sing-box check"
    return 1
  fi

  if [[ -r "$CONFIG_PATH" ]] &&
    cmp -s "$tmp" "$CONFIG_PATH" &&
    [[ "$(stat -c '%U:%G:%a' "$CONFIG_PATH" 2>/dev/null)" == "${CONFIG_OWNER}:${CONFIG_GROUP}:${config_mode_norm}" ]] &&
    [[ "$(stat -c '%U:%G:%a' "$config_dir" 2>/dev/null)" == "${CONFIG_OWNER}:${CONFIG_GROUP}:${config_dir_mode_norm}" ]]; then
    return 0
  fi

  if /usr/bin/install -d -o "$CONFIG_OWNER" -g "$CONFIG_GROUP" -m "$CONFIG_DIR_MODE" "$config_dir" >/dev/null 2>&1 &&
    /usr/bin/install -o "$CONFIG_OWNER" -g "$CONFIG_GROUP" -m "$CONFIG_MODE" "$tmp" "$CONFIG_PATH" >/dev/null 2>&1; then
    return 0
  fi

  if sudo_command "$TOGGLE_HELPER" install-config-root "$tmp" >/dev/null 2>&1; then
    return 0
  fi

  if ! sudo_command /usr/bin/install -d -o "$CONFIG_OWNER" -g "$CONFIG_GROUP" -m "$CONFIG_DIR_MODE" "$config_dir" >/dev/null 2>&1 ||
    ! sudo_command /usr/bin/install -o "$CONFIG_OWNER" -g "$CONFIG_GROUP" -m "$CONFIG_MODE" "$tmp" "$CONFIG_PATH" >/dev/null 2>&1; then
    json "Err" "failed" "Cannot install current config to ${CONFIG_PATH}; run sudo install"
    return 1
  fi
}

install_config_root() {
  local src=$1 config_dir src_owner config_mode_norm

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "install-config-root must run as root" >&2
    return 1
  fi

  case "$src" in
    /run/user/*/sing-box-config.json) ;;
    *)
      echo "refusing to install unexpected config path: ${src}" >&2
      return 1
      ;;
  esac

  if [[ ! -r "$src" ]]; then
    echo "config source is not readable: ${src}" >&2
    return 1
  fi

  if [[ -n "${SUDO_UID:-}" ]]; then
    src_owner="$(stat -c '%u' "$src" 2>/dev/null || true)"
    if [[ "$src_owner" != "$SUDO_UID" ]]; then
      echo "config source is not owned by sudo user: ${src}" >&2
      return 1
    fi
  fi

  if ! "$SING_BOX" check -c "$src" >/dev/null 2>&1; then
    echo "generated config did not pass sing-box check" >&2
    return 1
  fi

  config_dir="$(dirname "$CONFIG_PATH")"
  /usr/bin/install -d -o "$CONFIG_OWNER" -g "$CONFIG_GROUP" -m "$CONFIG_DIR_MODE" "$config_dir"
  /usr/bin/install -o "$CONFIG_OWNER" -g "$CONFIG_GROUP" -m "$CONFIG_MODE" "$src" "$CONFIG_PATH"

  config_mode_norm="${CONFIG_MODE#0}"
  [[ "$(stat -c '%U:%G:%a' "$CONFIG_PATH" 2>/dev/null)" == "${CONFIG_OWNER}:${CONFIG_GROUP}:${config_mode_norm}" ]]
}

fix_service_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "fix-service-root must run as root" >&2
    return 1
  fi

  /usr/bin/install -d -o root -g root -m 0755 "$SERVICE_DROPIN_DIR"
  cat > "$SERVICE_RECONNECT_DROPIN" <<'EOF'
[Service]
Environment=ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true
Restart=on-failure
RestartSec=10s
EOF
  "$SYSTEMCTL" daemon-reload
}

run_action() {
  local action=$1 desired=$2 transient=$3

  set_desired "$desired"
  set_state "$transient"
  refresh_waybar

  if ! sudo_systemctl "$action" >/dev/null 2>&1; then
    set_state "failed"
    refresh_waybar
    json "Err" "failed" "Cannot ${action} ${SERVICE}; check sudoers/systemd"
    return 1
  fi

  refresh_waybar
  status
}

start_vpn() {
  ensure_service_policy
  stop_legacy_vpn
  cleanup_stale_tun
  refresh_config || return 1
  run_action start on connecting
}

stop_vpn() {
  ensure_service_policy
  stop_legacy_vpn
  run_action stop off disconnecting
  cleanup_stale_tun
}

restart_vpn() {
  ensure_service_policy
  stop_legacy_vpn
  cleanup_stale_tun
  refresh_config || return 1
  run_action restart on connecting
}

toggle_vpn() {
  case "$(service_state)" in
    active|activating|reloading) stop_vpn ;;
    *) start_vpn ;;
  esac
}

suspend_vpn() {
  case "$(service_state)" in
    active|activating|reloading)
      set_desired suspending
      run_action stop suspending disconnecting
      ;;
    *) exit 0 ;;
  esac
}

resume_vpn() {
  [[ "$(desired_state)" == "suspending" ]] || exit 0
  sleep 2
  start_vpn
}

status() {
  local state substate transient desired result restarts tooltip
  state="$(service_state)"
  substate="$(service_substate)"
  transient="$(transient_state)"
  desired="$(desired_state)"
  result="$(service_result)"
  restarts="$(service_restarts)"

  if legacy_process_running; then
    case "$state" in
      active|activating|reloading)
        json "Mix" "failed" "Legacy goxray and ${SERVICE} are both running"
        return
        ;;
      *)
        json "Old" "failed" "Legacy goxray is still running; click to replace it with sing-box"
        return
        ;;
    esac
  fi

  case "$state:$transient:$desired" in
    active:*)
      clear_state
      if ! config_has_vless_tun; then
        json "Err" "failed" "sing-box active, but /etc/sing-box/config.json has no VLESS/TUN"
        return
      fi
      if ! is_tun_up; then
        json "Err" "failed" "${SERVICE} is active, but ${TUN_IFACE} is down"
        return
      fi
      tooltip="VPN connected (${SERVICE}, ${TUN_IFACE} up)"
      json "On" "connected" "$tooltip"
      ;;
    activating:*:*)
      if [[ "$substate" == "auto-restart" && "$result" != "success" ]]; then
        tooltip="VPN restart loop (${SERVICE}: ${result:-failed}"
        [[ -n "$restarts" ]] && tooltip="${tooltip}, restarts=${restarts}"
        json "Err" "failed" "${tooltip})"
      else
        json "..." "loading" "VPN connecting (${SERVICE})"
      fi
      ;;
    inactive:disconnecting:*|failed:disconnecting:*)
      clear_state
      json "Off" "disconnected" "VPN disconnected (${SERVICE})"
      ;;
    reloading:*|*:connecting:*)
      json "..." "loading" "VPN connecting (${SERVICE})"
      ;;
    deactivating:*|*:disconnecting:*)
      json "..." "loading" "VPN disconnecting (${SERVICE})"
      ;;
    failed:*|*:failed:*)
      tooltip="VPN service failed (${SERVICE}"
      [[ -n "$result" ]] && tooltip="${tooltip}: ${result}"
      json "Err" "failed" "${tooltip})"
      ;;
    *:*:suspending)
      json "Off" "disconnected" "VPN suspended"
      ;;
    *)
      clear_state
      json "Off" "disconnected" "VPN disconnected (${SERVICE})"
      ;;
  esac
}

main() {
  case "${1:-status}" in
    fix-service-root)
      fix_service_root
      ;;
    install-config-root)
      install_config_root "${2:-}"
      ;;
    status) status ;;
    start)
      acquire_lock || exit 0
      start_vpn
      ;;
    stop)
      acquire_lock || exit 0
      stop_vpn
      ;;
    restart)
      acquire_lock || exit 0
      restart_vpn
      ;;
    toggle)
      acquire_lock || exit 0
      toggle_vpn
      ;;
    suspend)
      acquire_lock || exit 0
      suspend_vpn
      ;;
    resume)
      acquire_lock || exit 0
      resume_vpn
      ;;
    *)
      echo "Usage: $0 [status|start|stop|restart|toggle|suspend|resume]" >&2
      return 2
      ;;
  esac
}

main "$@"
