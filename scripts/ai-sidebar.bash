#!/usr/bin/env bash

set -euo pipefail
export PATH="${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

readonly DAEMON="${HOME}/.dotfiles/scripts/ai-chat-layer.py"
readonly PID_FILE="${XDG_RUNTIME_DIR:-/tmp/user-${UID}}/ai-chat-layer.pid"
readonly STATE_FILE="${XDG_RUNTIME_DIR:-/tmp/user-${UID}}/ai-chat-layer.json"
readonly LOG_FILE="${XDG_CACHE_HOME:-${HOME}/.cache}/ai-chat-layer.log"

daemon_pid() {
    [[ -f "$PID_FILE" ]] && cat "$PID_FILE"
}

daemon_running() {
    local pid cmdline
    pid="$(daemon_pid || true)"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    [[ -r "/proc/${pid}/cmdline" ]] || return 1
    cmdline="$(tr '\0' ' ' <"/proc/${pid}/cmdline")"
    [[ "$cmdline" == *ai-chat-layer.py* ]]
}

start_daemon() {
    daemon_running && return
    mkdir -p "${LOG_FILE%/*}"
    setsid -f "$DAEMON" >"$LOG_FILE" 2>&1
    for _ in {1..30}; do daemon_running && return; sleep 0.1; done
    notify-send "AI chat" "Layer daemon did not start; see $LOG_FILE"
    return 1
}

toggle() {
    start_daemon
    kill -USR1 "$(daemon_pid)"
    pkill -RTMIN+9 waybar 2>/dev/null || true
}

status() {
    local class="offline" layer_state="stopped" tip="AI: stopped"
    if daemon_running; then
        layer_state="$(jq -r '.state // "hidden"' "$STATE_FILE" 2>/dev/null || printf hidden)"
        case "$layer_state" in
            visible | showing) class="visible" ;;
            hiding | hidden) class="hidden" ;;
            error) class="blocked" ;;
        esac
        tip="AI: $layer_state"
    fi
    jq -cn --arg text "✦" --arg tooltip "$tip" --arg class "$class" \
        '{text: $text, tooltip: $tooltip, class: $class}'
}

case "${1:-}" in
    toggle) toggle ;;
    status) status ;;
    *) printf 'Usage: %s {toggle|status}\n' "${0##*/}" >&2; exit 2 ;;
esac
