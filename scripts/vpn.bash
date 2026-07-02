#!/usr/bin/env bash
set -u

is_root_action() {
  case "${1:-}" in
    cleanup-external-tuns-root|configure-routes-root|cleanup-routes-root|fix-service-root|install-config-root|install-core-root|refresh-config-root|restart-service-root|start-service-root|stop-service-root) return 0 ;;
    *) return 1 ;;
  esac
}

if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" && -z "${VPN_KEEP_ROOT:-}" ]] && ! is_root_action "${1:-}"; then
  exec /usr/bin/env -u TERMINFO -u TERMINFO_DIRS /usr/bin/sudo -u "$SUDO_USER" -- "$0" "$@"
fi

SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_PATH="$(readlink -f "$SCRIPT_SOURCE" 2>/dev/null || printf '%s' "$SCRIPT_SOURCE")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
DEFAULT_USER_HOME="${VPN_USER_HOME:-/home/glebkiva}"

SERVICE="${VPN_SERVICE:-xray.service}"
CONFIG_ARGS_FILE="${VPN_CONFIG_ARGS_FILE:-${DEFAULT_USER_HOME}/scripts/goxray_cli_args}"
CONFIG_GENERATOR="${VPN_CONFIG_GENERATOR:-${SCRIPT_DIR}/xray-vless-config.bash}"
CONFIG_PATH="${VPN_CONFIG_PATH:-/etc/xray/config.json}"
CONFIG_OWNER="${VPN_CONFIG_OWNER:-root}"
CONFIG_GROUP="${VPN_CONFIG_GROUP:-root}"
CONFIG_MODE="${VPN_CONFIG_MODE:-0644}"
CONFIG_DIR_MODE="${VPN_CONFIG_DIR_MODE:-0755}"
TOGGLE_HELPER="${VPN_TOGGLE_HELPER:-${DEFAULT_USER_HOME}/scripts/vpn_toggle.bash}"
SERVICE_UNIT_PATH="${VPN_SERVICE_UNIT_PATH:-/etc/systemd/system/${SERVICE}}"
XRAY_INSTALL_DIR="${VPN_XRAY_INSTALL_DIR:-/usr/local/lib/xray}"
XRAY_BIN_PATH="${VPN_XRAY_BIN_PATH:-/usr/local/bin/xray}"
ROOT_HELPER_DIR="${VPN_ROOT_HELPER_DIR:-/usr/local/lib/xray-vpn}"
ROOT_HELPER="${VPN_ROOT_HELPER:-${ROOT_HELPER_DIR}/vpn.bash}"
ROOT_CONFIG_GENERATOR="${VPN_ROOT_CONFIG_GENERATOR:-${ROOT_HELPER_DIR}/xray-vless-config.bash}"
XRAY="${XRAY:-${XRAY_BIN_PATH}}"
XRAY_LOCATION_ASSET="${XRAY_LOCATION_ASSET:-${XRAY_INSTALL_DIR}}"
LEGACY_PROCESS_PATTERN="${VPN_LEGACY_PROCESS_PATTERN:-(^|/)(goxray_cli_linux_amd64|goxray)( |$)}"
CONFLICT_SERVICES="${VPN_CONFLICT_SERVICES:-v2ray.service sing-box.service}"
SYSTEMCTL="${SYSTEMCTL:-/usr/bin/systemctl}"
SUDO="${SUDO:-/usr/bin/sudo}"
TIMEOUT="${TIMEOUT:-/usr/bin/timeout}"
CURL="${CURL:-/usr/bin/curl}"
UNZIP="${UNZIP:-/usr/bin/unzip}"
IP="${IP:-/usr/bin/ip}"
BASH_BIN="${BASH_BIN:-/usr/bin/bash}"
RESTORECON="${RESTORECON:-/usr/sbin/restorecon}"
TUN_IFACE="${VPN_TUN_IFACE:-xray0}"
EXTERNAL_TUN_IFACES="${VPN_EXTERNAL_TUN_IFACES:-tun0 v2ray0}"
TUN_ADDRESS="${VPN_TUN_ADDRESS:-198.18.0.1/30}"
TUN_ROUTES="${VPN_TUN_ROUTES:-0.0.0.0/1 128.0.0.0/1}"
TUN_ROUTE_METRIC="${VPN_TUN_ROUTE_METRIC:-50}"
OUTBOUND_MARK="${VPN_OUTBOUND_MARK:-2}"
MARK_TABLE="${VPN_MARK_TABLE:-100}"
MARK_PRIORITY="${VPN_MARK_PRIORITY:-100}"

export XRAY_LOCATION_ASSET

RUN_DIR="${VPN_RUN_DIR:-/run/user/$(id -u)}"
WAYBAR_SIGNAL="8"
SYSTEMCTL_TIMEOUT="8s"
INSTALL_TIMEOUT="${VPN_INSTALL_TIMEOUT:-300s}"

set_run_paths() {
  STATE="${RUN_DIR}/xray.state"
  DESIRED_STATE="${RUN_DIR}/xray_desired.state"
  LOCK="${RUN_DIR}/xray_toggle.lock"
}

set_run_paths

mkdir_run_dir() {
  local probe

  if mkdir -p "$RUN_DIR" 2>/dev/null; then
    probe="${RUN_DIR}/.vpn-write-test.$$"
    if touch "$probe" >/dev/null 2>&1; then
      rm -f "$probe" 2>/dev/null || true
      return
    fi
  fi

  RUN_DIR="${VPN_FALLBACK_RUN_DIR:-/tmp/xray-vpn-$(id -u)}"
  set_run_paths
  mkdir -p "$RUN_DIR" 2>/dev/null || true
}

service_state() {
  local state

  state="$("$SYSTEMCTL" is-active "$SERVICE" 2>/dev/null || true)"
  if [[ -n "$state" ]]; then
    printf '%s\n' "$state"
    return
  fi

  if xray_process_running && is_tun_up; then
    printf '%s\n' "active"
    return
  fi

  printf '%s\n' "inactive"
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
    jq -e --arg iface "$TUN_IFACE" '
      any(.inbounds[]?; .protocol == "tun" and .settings.name == $iface) and
      any(.outbounds[]?; .protocol == "vless")
    ' "$CONFIG_PATH" >/dev/null 2>&1
  else
    VPN_TUN_IFACE="$TUN_IFACE" VPN_CONFIG_PATH="$CONFIG_PATH" python3 - <<'PY' >/dev/null 2>&1
import json
import os

with open(os.environ["VPN_CONFIG_PATH"], "r", encoding="utf-8") as config_file:
    config = json.load(config_file)

if not any(
    inbound.get("protocol") == "tun"
    and inbound.get("settings", {}).get("name") == os.environ["VPN_TUN_IFACE"]
    for inbound in config.get("inbounds", [])
):
    raise SystemExit(1)
if not any(outbound.get("protocol") == "vless" for outbound in config.get("outbounds", [])):
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

tun_iface_up() {
  local iface=$1
  local operstate

  if [[ -d "/sys/class/net/${iface}" ]]; then
    operstate="$(cat "/sys/class/net/${iface}/operstate" 2>/dev/null || true)"
    [[ "$operstate" != "down" ]] && return 0
  fi

  "$IP" link show "$iface" 2>/dev/null | grep -qE "state (UP|UNKNOWN)"
}

is_tun_up() {
  tun_iface_up "$TUN_IFACE"
}

refresh_waybar() {
  pkill -RTMIN+"$WAYBAR_SIGNAL" -x waybar 2>/dev/null || true
}

json() {
  printf '{"text":"%s","class":"%s","alt":"%s","tooltip":"%s"}\n' "$1" "$2" "$2" "$3"
}

sudo_service_action() {
  local action=$1

  "$TIMEOUT" "$SYSTEMCTL_TIMEOUT" /usr/bin/env -u TERMINFO -u TERMINFO_DIRS \
    "$SUDO" -n "$TOGGLE_HELPER" "${action}-service-root"
}

sudo_command() {
  "$TIMEOUT" "$SYSTEMCTL_TIMEOUT" /usr/bin/env -u TERMINFO -u TERMINFO_DIRS \
    "$SUDO" -n "$@"
}

sudo_long_command() {
  "$TIMEOUT" "$INSTALL_TIMEOUT" /usr/bin/env -u TERMINFO -u TERMINFO_DIRS \
    "$SUDO" -n "$@"
}

ensure_service_policy() {
  sudo_command "$TOGGLE_HELPER" fix-service-root >/dev/null 2>&1 || true
}

ensure_core_installed() {
  if [[ -x "$XRAY" && "${VPN_FORCE_XRAY_INSTALL:-0}" != "1" ]] && xray_supports_tun; then
    return 0
  fi

  if sudo_long_command "$TOGGLE_HELPER" install-core-root >/dev/null 2>&1; then
    if xray_supports_tun; then
      return 0
    fi

    json "Err" "failed" "Installed Xray-core does not support TUN inbound"
    return 1
  fi

  json "Err" "failed" "Cannot install Xray-core from GitHub releases"
  return 1
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

managed_conflict_services_running() {
  local service state found

  found=1
  for service in $CONFLICT_SERVICES; do
    [[ -n "$service" ]] || continue
    [[ "$service" == "$SERVICE" ]] && continue
    state="$("$SYSTEMCTL" is-active "$service" 2>/dev/null || true)"
    case "$state" in
      active|activating|reloading)
        printf '%s\n' "$service"
        found=0
        ;;
    esac
  done

  return "$found"
}

managed_conflict_running() {
  managed_conflict_services_running >/dev/null
}

xray_process_running() {
  local comm name

  for comm in /proc/[0-9]*/comm; do
    [[ -r "$comm" ]] || continue
    name="$(cat "$comm" 2>/dev/null || true)"
    [[ "$name" == "xray" ]] && return 0
  done

  return 1
}

external_tun_running() {
  local iface

  for iface in $EXTERNAL_TUN_IFACES; do
    [[ "$iface" == "$TUN_IFACE" ]] && continue
    tun_iface_up "$iface" && return 0
  done

  return 1
}

external_owner_running() {
  legacy_process_running || managed_conflict_running
}

external_vpn_running() {
  external_owner_running || external_tun_running
}

stale_external_tun_running() {
  ! external_owner_running && external_tun_running
}

external_vpn_label() {
  local label service iface

  label=
  if legacy_process_running; then
    label="goxray"
  fi

  while IFS= read -r service; do
    [[ -n "$service" ]] || continue
    if [[ -n "$label" ]]; then
      label="${label}, ${service}"
    else
      label="$service"
    fi
  done < <(managed_conflict_services_running)

  if [[ -z "$label" ]]; then
    for iface in $EXTERNAL_TUN_IFACES; do
      [[ "$iface" == "$TUN_IFACE" ]] && continue
      tun_iface_up "$iface" || continue
      if [[ -n "$label" ]]; then
        label="${label}, tun:${iface}"
      else
        label="tun:${iface}"
      fi
    done
  fi

  printf '%s\n' "${label:-external VPN}"
}

cleanup_stale_external_tuns() {
  stale_external_tun_running || return
  sudo_command "$TOGGLE_HELPER" cleanup-external-tuns-root >/dev/null 2>&1 || true
}

cleanup_external_tuns() {
  local external

  if external_owner_running; then
    external="$(external_vpn_label)"
    json "Ext" "connected" "External VPN (${external}) is running; external TUN cleanup was not run"
    return 0
  fi

  if sudo_command "$TOGGLE_HELPER" cleanup-external-tuns-root >/dev/null 2>&1; then
    status
    return 0
  fi

  json "Err" "failed" "Cannot clean external TUN interfaces; check sudoers"
  return 1
}

cleanup_stale_tun() {
  case "$(service_state)" in
    active|activating|reloading|deactivating) return ;;
  esac
  is_tun_up || return
  sudo_command "$TOGGLE_HELPER" cleanup-routes-root >/dev/null 2>&1 || true
}

xray_test_config() {
  local config=$1

  [[ -x "$XRAY" ]] || return 127

  "$XRAY" run -dump -config "$config" >/dev/null 2>&1 ||
    "$XRAY" run -dump -c "$config" >/dev/null 2>&1 ||
    "$XRAY" run -test -config "$config" >/dev/null 2>&1 ||
    "$XRAY" run -test -c "$config" >/dev/null 2>&1
}

xray_supports_tun() {
  local tmp status

  [[ -x "$XRAY" ]] || return 1
  tmp="$(mktemp /tmp/xray-tun-check.XXXXXX.json)" || return 1
  printf '%s\n' '{"inbounds":[{"tag":"tun-in","protocol":"tun","port":0,"settings":{"name":"xray0","mtu":1500}}],"outbounds":[{"tag":"direct","protocol":"freedom"}]}' > "$tmp"
  xray_test_config "$tmp"
  status=$?
  rm -f "$tmp" 2>/dev/null || true
  return "$status"
}

refresh_config() {
  local tmp err reason config_dir config_mode_norm config_dir_mode_norm
  mkdir_run_dir
  tmp="${RUN_DIR}/xray-config.json"
  err="${tmp}.err"
  config_dir="$(dirname "$CONFIG_PATH")"
  config_mode_norm="${CONFIG_MODE#0}"
  config_dir_mode_norm="${CONFIG_DIR_MODE#0}"

  if [[ ! -r "$CONFIG_GENERATOR" ]]; then
    json "Err" "failed" "Config generator is missing: ${CONFIG_GENERATOR}"
    return 1
  fi

  if [[ ! -r "$CONFIG_ARGS_FILE" ]]; then
    json "Err" "failed" "VLESS args file is missing: ${CONFIG_ARGS_FILE}"
    return 1
  fi

  if ! "$BASH_BIN" "$CONFIG_GENERATOR" "$CONFIG_ARGS_FILE" > "$tmp" 2>"$err"; then
    reason="$(tail -n 1 "$err" 2>/dev/null || true)"
    json "Err" "failed" "${reason:-Cannot generate Xray config from ${CONFIG_ARGS_FILE}}"
    return 1
  fi

  if ! xray_test_config "$tmp"; then
    json "Err" "failed" "Generated Xray config did not pass Xray validation"
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

  json "Err" "failed" "Cannot install current config to ${CONFIG_PATH}; check sudoers/systemd"
  return 1
}

install_config_root() {
  local src=${1:-} config_dir src_owner config_mode_norm

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "install-config-root must run as root" >&2
    return 1
  fi

  case "$src" in
    /run/user/*/xray-config.json|/run/xray-vpn/xray-config.json|/tmp/xray-vpn-*/xray-config.json) ;;
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

  if ! xray_test_config "$src"; then
    echo "generated config did not pass Xray validation" >&2
    return 1
  fi

  config_dir="$(dirname "$CONFIG_PATH")"
  /usr/bin/install -d -o "$CONFIG_OWNER" -g "$CONFIG_GROUP" -m "$CONFIG_DIR_MODE" "$config_dir"
  /usr/bin/install -o "$CONFIG_OWNER" -g "$CONFIG_GROUP" -m "$CONFIG_MODE" "$src" "$CONFIG_PATH"

  config_mode_norm="${CONFIG_MODE#0}"
  [[ "$(stat -c '%U:%G:%a' "$CONFIG_PATH" 2>/dev/null)" == "${CONFIG_OWNER}:${CONFIG_GROUP}:${config_mode_norm}" ]]
}

detect_xray_asset() {
  case "$(uname -m)" in
    x86_64|amd64) printf '%s\n' "Xray-linux-64.zip" ;;
    aarch64|arm64) printf '%s\n' "Xray-linux-arm64-v8a.zip" ;;
    armv7l) printf '%s\n' "Xray-linux-arm32-v7a.zip" ;;
    *)
      echo "unsupported architecture for Xray release asset: $(uname -m)" >&2
      return 1
      ;;
  esac
}

install_core_root() {
  local asset url tmp status

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "install-core-root must run as root" >&2
    return 1
  fi

  if [[ -x "$XRAY_BIN_PATH" && "${VPN_FORCE_XRAY_INSTALL:-0}" != "1" ]] && xray_supports_tun; then
    return 0
  fi

  if [[ ! -x "$CURL" ]]; then
    echo "curl is required to install Xray-core" >&2
    return 1
  fi
  if [[ ! -x "$UNZIP" ]]; then
    echo "unzip is required to install Xray-core" >&2
    return 1
  fi

  asset="${VPN_XRAY_ASSET:-$(detect_xray_asset)}" || return 1
  url="${VPN_XRAY_RELEASE_URL:-https://github.com/XTLS/Xray-core/releases/latest/download/${asset}}"
  tmp="$(mktemp -d /tmp/xray-core.XXXXXX)" || return 1

  (
    set -e
    mkdir -p "${tmp}/unpack"
    "$CURL" -fL --retry 5 --retry-delay 2 --connect-timeout 20 --max-time 240 -o "${tmp}/${asset}" "$url"
    "$UNZIP" -q "${tmp}/${asset}" -d "${tmp}/unpack"
    /usr/bin/install -d -o root -g root -m 0755 "$XRAY_INSTALL_DIR"
    /usr/bin/install -o root -g root -m 0755 "${tmp}/unpack/xray" "${XRAY_INSTALL_DIR}/xray"
    [[ -f "${tmp}/unpack/geoip.dat" ]] && /usr/bin/install -o root -g root -m 0644 "${tmp}/unpack/geoip.dat" "${XRAY_INSTALL_DIR}/geoip.dat"
    [[ -f "${tmp}/unpack/geosite.dat" ]] && /usr/bin/install -o root -g root -m 0644 "${tmp}/unpack/geosite.dat" "${XRAY_INSTALL_DIR}/geosite.dat"
    /usr/bin/install -d -o root -g root -m 0755 "$(dirname "$XRAY_BIN_PATH")"
    rm -f "$XRAY_BIN_PATH"
    /usr/bin/install -o root -g root -m 0755 "${tmp}/unpack/xray" "$XRAY_BIN_PATH"
    [[ -x "$RESTORECON" ]] && "$RESTORECON" "$XRAY_BIN_PATH" "$XRAY_INSTALL_DIR" || true
  )
  status=$?
  rm -rf "$tmp"
  return "$status"
}

fix_service_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "fix-service-root must run as root" >&2
    return 1
  fi

  /usr/bin/install -d -o root -g root -m 0755 "$ROOT_HELPER_DIR"
  /usr/bin/install -o root -g root -m 0755 "$SCRIPT_PATH" "$ROOT_HELPER"
  /usr/bin/install -o root -g root -m 0755 "$CONFIG_GENERATOR" "$ROOT_CONFIG_GENERATOR"
  if [[ -L "$XRAY_BIN_PATH" && -x "${XRAY_INSTALL_DIR}/xray" ]]; then
    rm -f "$XRAY_BIN_PATH"
    /usr/bin/install -o root -g root -m 0755 "${XRAY_INSTALL_DIR}/xray" "$XRAY_BIN_PATH"
  fi
  if [[ -x "$XRAY_BIN_PATH" ]]; then
    chown root:root "$XRAY_BIN_PATH" 2>/dev/null || true
    chmod 0755 "$XRAY_BIN_PATH" 2>/dev/null || true
  fi
  [[ -x "$RESTORECON" ]] && "$RESTORECON" "$ROOT_HELPER_DIR" "$ROOT_HELPER" "$ROOT_CONFIG_GENERATOR" "$XRAY_BIN_PATH" 2>/dev/null || true
  /usr/bin/install -d -o root -g root -m 0755 "$(dirname "$SERVICE_UNIT_PATH")"
  cat > "$SERVICE_UNIT_PATH" <<EOF
[Unit]
Description=Xray VPN client
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target nss-lookup.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
Environment="VPN_KEEP_ROOT=1"
Environment="VPN_CONFIG_ARGS_FILE=${CONFIG_ARGS_FILE}"
Environment="VPN_CONFIG_GENERATOR=${ROOT_CONFIG_GENERATOR}"
Environment="VPN_CONFIG_PATH=${CONFIG_PATH}"
Environment="VPN_RUN_DIR=/run/xray-vpn"
Environment="VPN_TUN_IFACE=${TUN_IFACE}"
Environment="VPN_EXTERNAL_TUN_IFACES=${EXTERNAL_TUN_IFACES}"
Environment="VPN_CONFLICT_SERVICES=${CONFLICT_SERVICES}"
Environment="VPN_TUN_ADDRESS=${TUN_ADDRESS}"
Environment="VPN_TUN_ROUTES=${TUN_ROUTES}"
Environment="VPN_OUTBOUND_MARK=${OUTBOUND_MARK}"
Environment="VPN_MARK_TABLE=${MARK_TABLE}"
Environment="VPN_MARK_PRIORITY=${MARK_PRIORITY}"
Environment="VPN_TUN_ROUTE_METRIC=${TUN_ROUTE_METRIC}"
Environment="XRAY_LOCATION_ASSET=${XRAY_LOCATION_ASSET}"
ExecStartPre=/usr/bin/bash ${ROOT_HELPER} install-core-root
ExecStart=${XRAY_BIN_PATH} run -config ${CONFIG_PATH}
ExecStartPost=/usr/bin/bash ${ROOT_HELPER} configure-routes-root
ExecStopPost=/usr/bin/bash ${ROOT_HELPER} cleanup-routes-root
Restart=always
RestartSec=5s
KillSignal=SIGTERM
KillMode=control-group
LimitNOFILE=1048576
SELinuxContext=-system_u:system_r:unconfined_service_t:s0
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=false

[Install]
WantedBy=multi-user.target
EOF
  "$SYSTEMCTL" daemon-reload
}

tun_routes() {
  printf '%s\n' $TUN_ROUTES
}

wait_for_tun() {
  local attempt
  for attempt in $(seq 1 50); do
    "$IP" link show "$TUN_IFACE" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

configure_mark_route_root() {
  local default_route

  [[ "$OUTBOUND_MARK" == "0" ]] && return 0

  default_route="$("$IP" -4 route show default 0.0.0.0/0 2>/dev/null | head -n 1)"
  if [[ -z "$default_route" ]]; then
    echo "cannot configure Xray policy route: no IPv4 default route" >&2
    return 1
  fi

  "$IP" -4 route replace table "$MARK_TABLE" $default_route
  "$IP" rule add fwmark "$OUTBOUND_MARK" priority "$MARK_PRIORITY" table "$MARK_TABLE" 2>/dev/null || true
}

physical_default_route_parts() {
  "$IP" -4 route show default 0.0.0.0/0 2>/dev/null | head -n 1
}

route_field() {
  local route=$1 field=$2
  local token previous

  previous=
  for token in $route; do
    if [[ "$previous" == "$field" ]]; then
      printf '%s\n' "$token"
      return 0
    fi
    previous=$token
  done

  return 1
}

proxy_server_addresses() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.outbounds[]? | select(.tag == "proxy") | .settings.vnext[]?.address // empty' "$CONFIG_PATH" 2>/dev/null
  else
    VPN_CONFIG_PATH="$CONFIG_PATH" python3 - <<'PY' 2>/dev/null
import json
import os

with open(os.environ["VPN_CONFIG_PATH"], "r", encoding="utf-8") as config_file:
    config = json.load(config_file)

for outbound in config.get("outbounds", []):
    if outbound.get("tag") != "proxy":
        continue
    for vnext in outbound.get("settings", {}).get("vnext", []):
        address = vnext.get("address")
        if address:
            print(address)
PY
  fi
}

configure_proxy_server_routes_root() {
  local default_route gateway dev src server

  default_route="$(physical_default_route_parts)"
  if [[ -z "$default_route" ]]; then
    echo "cannot configure Xray server route: no IPv4 default route" >&2
    return 1
  fi

  gateway="$(route_field "$default_route" via || true)"
  dev="$(route_field "$default_route" dev || true)"
  src="$(route_field "$default_route" src || true)"
  if [[ -z "$dev" ]]; then
    echo "cannot configure Xray server route: default route has no device" >&2
    return 1
  fi

  while IFS= read -r server; do
    [[ "$server" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    if [[ -n "$gateway" && -n "$src" ]]; then
      "$IP" route replace "${server}/32" via "$gateway" dev "$dev" src "$src" metric 1
    elif [[ -n "$gateway" ]]; then
      "$IP" route replace "${server}/32" via "$gateway" dev "$dev" metric 1
    elif [[ -n "$src" ]]; then
      "$IP" route replace "${server}/32" dev "$dev" src "$src" metric 1
    else
      "$IP" route replace "${server}/32" dev "$dev" metric 1
    fi
  done < <(proxy_server_addresses)
}

configure_routes_root() {
  local route external

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "configure-routes-root must run as root" >&2
    return 1
  fi

  if external_owner_running; then
    external="$(external_vpn_label)"
    echo "external VPN (${external}) is running; refusing to install Xray routes over it" >&2
    return 1
  fi

  cleanup_external_tuns_root
  configure_proxy_server_routes_root || return 1
  configure_mark_route_root || return 1
  wait_for_tun || {
    echo "tun interface did not appear: ${TUN_IFACE}" >&2
    return 1
  }

  "$IP" addr add "$TUN_ADDRESS" dev "$TUN_IFACE" 2>/dev/null || true
  "$IP" link set "$TUN_IFACE" up
  while IFS= read -r route; do
    [[ -n "$route" ]] || continue
    "$IP" route replace "$route" dev "$TUN_IFACE" metric "$TUN_ROUTE_METRIC"
  done < <(tun_routes)
}

cleanup_external_tuns_root() {
  local iface external

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "cleanup-external-tuns-root must run as root" >&2
    return 1
  fi

  if external_owner_running; then
    external="$(external_vpn_label)"
    echo "external VPN (${external}) is running; refusing to delete external TUN interfaces" >&2
    return 1
  fi

  for iface in $EXTERNAL_TUN_IFACES; do
    [[ "$iface" == "$TUN_IFACE" ]] && continue
    "$IP" link delete "$iface" 2>/dev/null || true
  done
}

cleanup_routes_root() {
  local route server

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "cleanup-routes-root must run as root" >&2
    return 1
  fi

  while IFS= read -r route; do
    [[ -n "$route" ]] || continue
    "$IP" route del "$route" dev "$TUN_IFACE" 2>/dev/null || true
  done < <(tun_routes)

  if ! external_vpn_running; then
    while IFS= read -r server; do
      [[ "$server" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
      "$IP" route del "${server}/32" 2>/dev/null || true
    done < <(proxy_server_addresses)

    if [[ "$OUTBOUND_MARK" != "0" ]]; then
      "$IP" rule del fwmark "$OUTBOUND_MARK" priority "$MARK_PRIORITY" table "$MARK_TABLE" 2>/dev/null || true
      "$IP" route flush table "$MARK_TABLE" 2>/dev/null || true
    fi
  fi

  "$IP" link delete "$TUN_IFACE" 2>/dev/null || true
}

refresh_config_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "refresh-config-root must run as root" >&2
    return 1
  fi

  refresh_config
}

service_action_root() {
  local action=$1

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "${action}-service-root must run as root" >&2
    return 1
  fi

  "$SYSTEMCTL" "$action" "$SERVICE"
}

run_action() {
  local action=$1 desired=$2 transient=$3

  set_desired "$desired"
  set_state "$transient"
  refresh_waybar

  if ! sudo_service_action "$action" >/dev/null 2>&1; then
    set_state "failed"
    refresh_waybar
    json "Err" "failed" "Cannot ${action} ${SERVICE}; check sudoers/systemd"
    return 1
  fi

  refresh_waybar
  status
}

start_vpn() {
  local external

  if external_vpn_running; then
    clear_state
    external="$(external_vpn_label)"
    json "Ext" "connected" "External VPN (${external}) is running; ${SERVICE} was not started"
    return 0
  fi
  ensure_service_policy
  ensure_core_installed || return 1
  cleanup_stale_external_tuns
  cleanup_stale_tun
  refresh_config || return 1
  run_action start on connecting
}

stop_vpn() {
  ensure_service_policy
  run_action stop off disconnecting
  cleanup_stale_tun
}

restart_vpn() {
  local external

  if external_vpn_running; then
    clear_state
    external="$(external_vpn_label)"
    json "Ext" "connected" "External VPN (${external}) is running; ${SERVICE} was not restarted"
    return 0
  fi
  ensure_service_policy
  ensure_core_installed || return 1
  cleanup_stale_external_tuns
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
  local state substate transient desired result restarts tooltip external
  state="$(service_state)"
  substate="$(service_substate)"
  transient="$(transient_state)"
  desired="$(desired_state)"
  result="$(service_result)"
  restarts="$(service_restarts)"

  if external_vpn_running; then
    external="$(external_vpn_label)"
    case "$state" in
      active|activating|reloading)
        json "Mix" "failed" "External VPN (${external}) and ${SERVICE} are both running"
        return
        ;;
      *)
        clear_state
        json "Ext" "connected" "External VPN (${external}) is running; ${SERVICE} is inactive"
        return
        ;;
    esac
  fi

  case "$state:$transient:$desired" in
    active:*)
      clear_state
      if ! config_has_vless_tun; then
        json "Err" "failed" "${SERVICE} active, but ${CONFIG_PATH} has no VLESS/${TUN_IFACE}"
        return
      fi
      if ! is_tun_up; then
        json "Err" "failed" "${SERVICE} is active, but ${TUN_IFACE} is down"
        return
      fi
      tooltip="VPN connected (${SERVICE}, ${TUN_IFACE} up"
      [[ -n "$restarts" ]] && tooltip="${tooltip}, restarts=${restarts}"
      json "On" "connected" "${tooltip})"
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
    cleanup-external-tuns-root)
      cleanup_external_tuns_root
      ;;
    cleanup-external-tuns)
      cleanup_external_tuns
      ;;
    cleanup-routes-root)
      cleanup_routes_root
      ;;
    configure-routes-root)
      configure_routes_root
      ;;
    fix-service-root)
      fix_service_root
      ;;
    install-config-root)
      install_config_root "${2:-}"
      ;;
    install-core-root)
      install_core_root
      ;;
    refresh-config-root)
      refresh_config_root
      ;;
    restart-service-root)
      service_action_root restart
      ;;
    start-service-root)
      service_action_root start
      ;;
    stop-service-root)
      service_action_root stop
      ;;
    refresh-config)
      ensure_core_installed || return 1
      refresh_config
      ;;
    install-core)
      ensure_core_installed
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
      echo "Usage: $0 [status|start|stop|restart|toggle|suspend|resume|cleanup-external-tuns|refresh-config|install-core]" >&2
      return 2
      ;;
  esac
}

main "$@"
