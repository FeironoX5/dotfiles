#!/usr/bin/env bash
set -u

systemctl --user import-environment \
    DISPLAY \
    WAYLAND_DISPLAY \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_TYPE \
    NIRI_SOCKET

dbus-update-activation-environment --systemd \
    DISPLAY \
    WAYLAND_DISPLAY \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_TYPE \
    NIRI_SOCKET

systemctl --user start xdg-desktop-portal-gnome.service
systemctl --user restart xdg-desktop-portal.service
