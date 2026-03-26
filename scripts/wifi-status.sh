#!/usr/bin/env bash
set -euo pipefail

# JSON escape helper
json_escape() {
  # escapes \ " and newlines
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g'
}

# 1) Найти Wi‑Fi интерфейс (один)
get_wifi_iface() {
  nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}'
}

dev="$(get_wifi_iface || true)"

if [[ -z "${dev:-}" ]]; then
  text='WiFi N/A'
  tooltip='No Wi‑Fi device found'
  printf '{"text":"%s","tooltip":"%s"}\n' \
    "$(printf '%s' "$text" | json_escape)" \
    "$(printf '%s' "$tooltip" | json_escape)"
  exit 0
fi

# 2) Состояние интерфейса и активное подключение
# Формат: DEVICE:STATE:CONNECTION
line="$(nmcli -t -f DEVICE,STATE,CONNECTION device 2>/dev/null | awk -F: -v d="$dev" '$1==d{print $0; exit}')"

state="unknown"
con=""
if [[ -n "$line" ]]; then
  IFS=: read -r _dev state con <<<"$line"
fi

# 3) Если подключены — соберём SSID, сигнал и IP
if [[ "$state" == "connected" || "$state" == connected* ]]; then
  ssid="$con"  # для Wi‑Fi соединений имя обычно совпадает с SSID

  # Попробуем взять RSSI через iw
  rssi="$(iw dev "$dev" link 2>/dev/null | awk '/signal:/ {print $2; exit}')"
  pct=""
  if [[ -n "${rssi:-}" ]]; then
    # rssi в dBm (отрицательное число). Простейшее отображение в 0..100
    # -90 -> 0, -40 -> 100 (прибл.)
    val=$(( 2 * (rssi + 90) ))
    (( val < 0 )) && val=0
    (( val > 100 )) && val=100
    pct="$val"
  else
    # Фоллбэк через nmcli (скан) — может быть тяжелее, но разово сойдёт
    sig="$(nmcli -t -f IN-USE,SSID,SIGNAL dev wifi 2>/dev/null | awk -F: '/^\*/{print $3; exit}')"
    if [[ -n "${sig:-}" ]]; then
      pct="$sig"
    fi
  fi

  ip="$(nmcli -t -f IP4.ADDRESS device show "$dev" 2>/dev/null | awk -F: 'NR==1{print $2}')"

  text="$ssid ${pct:-?}%"
  tooltip=$'SSID: '"$ssid"$'\nSignal: '"${pct:-?}"$'%\nIP: '"${ip:-N/A}"$'\nDev: '"$dev"

  printf '{"text":"%s","tooltip":"%s"}\n' \
    "$(printf '%s' "&#xF12F;" | json_escape)" \
    "$(printf '%s' "$tooltip" | json_escape)"
  exit 0
fi

# 4) Если отключены — покажем статус
radio="$(nmcli -t -f WIFI radio 2>/dev/null || true)"
if [[ "${radio,,}" == "disabled" ]]; then
  text="&#xF135;"
  tooltip="Wi‑Fi radio is disabled (device: $dev)"
else
  text="&#xF12B;"
  tooltip="Wi‑Fi not connected (device: $dev)"
fi

printf '{"text":"%s","tooltip":"%s"}\n' \
  "$(printf '%s' "$text" | json_escape)" \
  "$(printf '%s' "$tooltip" | json_escape)"
