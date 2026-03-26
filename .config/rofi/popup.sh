#!/bin/bash
choice=$(echo -e "Wi-Fi\nBluetooth\nVolume\nNotifications" | rofi -dmenu -p "Control Panel" -theme ~/.config/rofi/theme.rasi)

case "$choice" in
  "Wi-Fi") nm-connection-editor ;;
  "Bluetooth") blueman-manager ;;
  "Volume") pavucontrol ;;
  "Notifications") makoctl dismiss ;;
esac
