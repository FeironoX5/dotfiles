CONFIG_FILE="$HOME/.config/hypr/hyprpaper.conf"
CONFIG_FILE2="$HOME/.config/hypr/hyprlock.conf"

WALLPAPERS=($(find /home/glebkiva/Images/wallpapers -maxdepth 1 -type f | sort))

sed -i '/^preload = /d' "$CONFIG_FILE"
for wallpaper in "${WALLPAPERS[@]}"; do
    sed -i "1i preload = ${wallpaper}" "$CONFIG_FILE"
done

SELECTED_WALLPAPER=${WALLPAPERS[RANDOM % ${#WALLPAPERS[@]}]}
hyprctl hyprpaper wallpaper ", $SELECTED_WALLPAPER"
sed -i "s|^wallpaper = .*|wallpaper = , $SELECTED_WALLPAPER|" "$CONFIG_FILE"
sed -i "s|path = .*|path = $SELECTED_WALLPAPER|" "$CONFIG_FILE2"
