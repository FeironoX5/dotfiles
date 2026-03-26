#!/usr/bin/env bash
set -euo pipefail

# ——— Pretty macOS‑like Control Center via wofi/rofi ———

pick_menu() {
  if command -v wofi >/dev/null 2>&1; then
    MENU=(wofi --dmenu -i -p "Control Center" --allow-markup)
  elif command -v rofi >/dev/null 2>&1; then
    MENU=(rofi -dmenu -i -p "Control Center")
  elif command -v fuzzel >/dev/null 2>&1; then
    MENU=(fuzzel --dmenu --prompt "Control Center: ")
  else
    echo "No wofi/rofi/fuzzel installed" >&2
    exit 1
  fi
}

# Helpers
wifi_iface() { nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}'; }
wifi_state() {
  local dev; dev=$(wifi_iface || true)
  [[ -z "$dev" ]] && { echo "N/A"; return; }
  nmcli -t -f DEVICE,STATE,CONNECTION device | awk -F: -v d="$dev" '$1==d{print $2"|" $3; exit}'
}
bt_power() { bluetoothctl show | awk -F': ' '/Powered:/{print tolower($2); exit}'; }
bt_connected_count() { bluetoothctl info $(bluetoothctl paired-devices | awk '{print $2}') 2>/dev/null | awk -F': ' '/Connected: yes/{c++} END{print c+0}'; }
dnd_state() {
  # swaync-client state (best-effort)
  if command -v swaync-client >/dev/null 2>&1; then
    # Try to query through dbus (fallback: read cache)
    swaync-client --get-dnd 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}
vpn_state() {
  if out=$(sudo -n /home/glebkiva/scripts/vpn_check.bash 2>/dev/null); then
    case "$out" in
      *'"class":"connected"') echo "connected" ;;
      *'"class":"loading"') echo "loading" ;;
      *) echo "disconnected" ;;
    esac
  else
    echo "disconnected"
  fi
}
vol_pct() {
  if command -v pamixer >/dev/null 2>&1; then
    pamixer --get-volume
  else
    pactl get-sink-volume @DEFAULT_SINK@ | awk '{print $5}' | tr -d '%'
  fi
}
bright_pct() {
  if command -v brightnessctl >/dev/null 2>&1; then
    brightnessctl -m | awk -F, '{gsub(/[%]/,"",$4); print $4}'
  else
    echo "?"
  fi
}

toggle_wifi() {
  local r; r=$(nmcli -t -f WIFI radio)
  if [[ "${r,,}" == "enabled" ]]; then nmcli radio wifi off; else nmcli radio wifi on; fi
}
toggle_bt() {
  if [[ "$(bt_power)" == "yes" ]]; then bluetoothctl power off >/dev/null; else bluetoothctl power on >/dev/null; fi
}
toggle_dnd() { command -v swaync-client >/dev/null 2>&1 && swaync-client -d -sw >/dev/null; }
toggle_vpn() { sudo -n /home/glebkiva/scripts/vpn_toggle.bash >/dev/null; }

vol_up() { if command -v pamixer >/dev/null 2>&1; then pamixer -i 5; else pactl set-sink-volume @DEFAULT_SINK@ +5%; fi }
vol_down(){ if command -v pamixer >/dev/null 2>&1; then pamixer -d 5; else pactl set-sink-volume @DEFAULT_SINK@ -5%; fi }
vol_mute(){ if command -v pamixer >/dev/null 2>&1; then pamixer -t; else pactl set-sink-mute @DEFAULT_SINK@ toggle; fi }

bright_up(){ command -v brightnessctl >/dev/null 2>&1 && brightnessctl set +5% >/dev/null; }
bright_down(){ command -v brightnessctl >/dev/null 2>&1 && brightnessctl set 5%- >/dev/null; }

open_wifi_menu(){ /home/glebkiva/scripts/wifi-menu.sh >/dev/null 2>&1 & }
open_bt_menu(){ /home/glebkiva/scripts/bluetooth-menu.sh >/dev/null 2>&1 & }
open_volume_menu(){ /home/glebkiva/scripts/volume-menu.sh >/dev/null 2>&1 & }

loop_menu() {
  pick_menu
  while true; do
    wifi="$(wifi_state)"
    wifi_s="${wifi%%|*}"; ssid="${wifi#*|}"
    [[ "$wifi" == "N/A" ]] && wifi_s="off" && ssid="No device"
    bt_p="$(bt_power)"
    bt_c="$(bt_connected_count)"
    dnd="$(dnd_state)"
    vpn="$(vpn_state)"
    vol="$(vol_pct)"
    br="$(bright_pct)"

    # icons: Nerd Fonts recommended
    wifi_icon=""; [[ "$wifi_s" == "connected" || "$wifi_s" == connected* ]] || wifi_icon="睊"
    bt_icon=""; [[ "$bt_p" == "yes" ]] || bt_icon="󰂲"
    dnd_icon=""
    vpn_icon="󰯄"
    vol_icon=""
    bri_icon=""

    items=(
      "󰀂  Close"
      "────────────"
      "$wifi_icon  Wi‑Fi: ${wifi_s^^}${ssid:+  ($ssid)}"
      "$bt_icon  Bluetooth: $( [[ "$bt_p" == "yes" ]] && echo ON || echo OFF )  ($bt_c)"
      "$dnd_icon  Do Not Disturb: $( [[ "$dnd" == "true" ]] && echo ON || echo OFF )"
      "$vpn_icon  VPN: $vpn"
      "$vol_icon  Volume: ${vol}%"
      "$bri_icon  Brightness: ${br}%"
      "────────────"
      "直  Open Wi‑Fi menu…"
      "  Open Bluetooth menu…"
      "  Sound output…"
      "────────────"
      "  Wi‑Fi toggle"
      "  Bluetooth toggle"
      "  DND toggle"
      "  VPN toggle"
      "  Volume +5%"
      "  Volume -5%"
      "  Mute/Unmute"
      "  Brightness +5%"
      "  Brightness -5%"
    )

    choice="$(printf '%s\n' "${items[@]}" | "${MENU[@]}")" || exit 0
    case "$choice" in
      "󰀂  Close"|"" ) exit 0 ;;
      "直  Open Wi‑Fi menu…") open_wifi_menu ;;
      "  Open Bluetooth menu…") open_bt_menu ;;
      "  Sound output…") open_volume_menu ;;
      "  Wi‑Fi toggle") toggle_wifi ;;
      "  Bluetooth toggle") toggle_bt ;;
      "  DND toggle") toggle_dnd ;;
      "  VPN toggle") toggle_vpn ;;
      "  Volume +5%") vol_up ;;
      "  Volume -5%") vol_down ;;
      "  Mute/Unmute") vol_mute ;;
      "  Brightness +5%") bright_up ;;
      "  Brightness -5%") bright_down ;;
      *) : ;;
    esac
    # Перерисовать меню с обновлёнными значениями
  done
}

loop_menu
