#!/usr/bin/env bash

SPECIAL_WS="anchor"

current_line="$(niri msg workspaces | sed -n 's/^ \*\(.*\)$/\1/p' | head -n1)"

if echo "$current_line" | grep -q "\"$SPECIAL_WS\""; then
    niri msg action focus-workspace-previous
else
    niri msg action focus-workspace "$SPECIAL_WS"
fi
