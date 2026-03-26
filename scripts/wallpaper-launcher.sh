#!/bin/bash
wall_dir="${HOME}/Images/wallpapers/"
cacheDir="${HOME}/.cache/wallpaper"
rofi_theme="${HOME}/.config/rofi/wallTheme.rasi"  # Fixed filename

# Create cache dir
mkdir -p "${cacheDir}"

# Fixed thumbnail size (no dynamic calc)
thumb_size=256
rofi_override="element-icon{size:${thumb_size}px;border-radius:0px;}"

# Convert with magick
for imagen in "$wall_dir"/*.{jpg,jpeg,png,webp}; do
    if [ -f "$imagen" ]; then
        nombre_archivo=$(basename "$imagen")
        if [ ! -f "${cacheDir}/${nombre_archivo}" ]; then
            magick "$imagen" -strip -thumbnail 500x500^ -gravity center -extent 500x500 "${cacheDir}/${nombre_archivo}"
        fi
    fi
done

# Fixed rofi command - proper quoting + your theme
wall_selection=$(find "${wall_dir}" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) -exec basename {} \; | sort | while read -r A ; do echo -en "$A\x00icon\x1f${cacheDir}/$A\n" ; done | rofi -dmenu -theme "$rofi_theme" -theme-str "$rofi_override" -p "Select wallpaper" -i -lines 4 -columns 6)

# Set wallpaper
[[ -n "$wall_selection" ]] && {
    pkill swaybg
    echo "${wall_dir}/${wall_selection}" > "${HOME}/.config/wallpaper-last.txt"
    sed -i "s|path = .*|path = ${wall_dir}/${wall_selection}|" "$HOME/.config/hypr/hyprlock.conf"
    swaybg -o eDP-1 -i $(cat ~/.config/wallpaper-last.txt) -m fill
}
