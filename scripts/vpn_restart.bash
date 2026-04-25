#!/usr/bin/env bash
# Called by Niri on lid-open (after resume).
# Restores desired=on (was set to suspending on lid-close) and
# starts VPN if it's not already up.
#
# restart_on_death won't have fired during sleep (desired was suspending),
# so we start goxray directly here, with a short wait as a safety margin.
source "$(dirname "$0")/vpn_common.bash"

TOGGLE="$(dirname "$0")/vpn_toggle.bash"

desired=$(< "$DESIRED_STATE" 2>/dev/null) || true

# Only act if we were the ones who set it to suspending.
# If desired=off, user turned VPN off before closing lid — leave it off.
[[ "$desired" != "suspending" ]] && exit 0

logger -t vpn-lid "lid opened — restoring desired=on, starting VPN"
printf 'on' > "$DESIRED_STATE"

# Brief wait for network interfaces to come back up after resume
sleep 2

exec "$TOGGLE"
