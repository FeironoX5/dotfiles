#!/bin/bash

APP_ID="io.github.focustimerhq.FocusTimer"
APP_CMD="flatpak run $APP_ID"

# Получаем список окон в JSON
WINDOWS=$(niri msg --json windows 2>/dev/null)

# Ищем окно по App ID
WINDOW_ID=$(echo "$WINDOWS" | jq -r --arg app "$APP_ID" '.[] | select(.app_id == $app) | .id' | head -n1)

if [ -n "$WINDOW_ID" ]; then
    niri msg action focus-window --id "$WINDOW_ID"
    niri msg action close-window
else
    $APP_CMD &
fi
