#!/usr/bin/env bash
# Called by Niri on lid-close (before suspend).
# Kills goxray and sets desired=suspending so restart_on_death
# knows not to restart — the system is going to sleep.
source "$(dirname "$0")/vpn_common.bash"

desired=$(< "$DESIRED_STATE" 2>/dev/null) || true
[[ "$desired" != "on" ]] && exit 0

logger -t vpn-lid "lid closed — killing goxray, setting desired=suspending"
pkill -f -- "^${BIN}( |$)" 2>/dev/null || true
printf 'suspending' > "$DESIRED_STATE"
