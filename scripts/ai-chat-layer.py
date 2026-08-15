#!/usr/bin/env python3

import fcntl
import json
import os
import signal
import time
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
gi.require_version("Vte", "2.91")

from gi.repository import Gdk, Gio, GLib, Gtk, GtkLayerShell, Vte


WIDTH = 680
VISIBLE_MARGIN = 0
FRAME_MS = 16
PIXELS_PER_SECOND = 1_800
MIN_DURATION_MS = 220
MAX_DURATION_MS = 650
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/user-{os.getuid()}"))
STATE_FILE = RUNTIME_DIR / "ai-chat-layer.json"
PID_FILE = RUNTIME_DIR / "ai-chat-layer.pid"
LOCK_FILE = RUNTIME_DIR / "ai-chat-layer.lock"
HERDR = Path.home() / ".local/bin/herdr"
PI_SHELL = Path.home() / ".dotfiles/scripts/pi-herdr-shell.bash"


class ChatLayer:
    def __init__(self) -> None:
        self.window = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
        self.terminal = Vte.Terminal()
        self.margin = -WIDTH
        self.animation_source = 0
        self.child_pid = 0
        self.target_visible = False

        self.window.set_decorated(False)
        self.window.set_resizable(False)
        self.window.set_size_request(WIDTH, -1)
        self.window.add(self.terminal)
        self.window.connect("destroy", self.quit)
        self.terminal.connect("child-exited", self.on_child_exited)
        self.terminal.set_scrollback_lines(20_000)
        background = Gdk.RGBA()
        foreground = Gdk.RGBA()
        background.parse("#0d1117")
        foreground.parse("#e6edf3")
        self.terminal.set_color_background(background)
        self.terminal.set_color_foreground(foreground)

        GtkLayerShell.init_for_window(self.window)
        GtkLayerShell.set_namespace(self.window, "ai-chat")
        GtkLayerShell.set_layer(self.window, GtkLayerShell.Layer.TOP)
        GtkLayerShell.set_exclusive_zone(self.window, 0)
        GtkLayerShell.set_anchor(self.window, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_anchor(self.window, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self.window, GtkLayerShell.Edge.BOTTOM, True)
        GtkLayerShell.set_keyboard_mode(self.window, GtkLayerShell.KeyboardMode.NONE)
        self.set_margin(self.margin)
        self.write_state("hidden")

    def ensure_terminal(self) -> None:
        if self.child_pid:
            return

        environment = dict(os.environ)
        environment["SHELL"] = str(PI_SHELL)
        environment["PATH"] = (
            f"{Path.home()}/.local/bin:/usr/local/bin:/usr/bin:/bin:"
            f"{environment.get('PATH', '')}"
        )
        envv = [f"{key}={value}" for key, value in environment.items()]
        _spawned, self.child_pid = self.terminal.spawn_sync(
            Vte.PtyFlags.DEFAULT,
            str(Path.home()),
            [str(HERDR), "--session", "desktop-ai"],
            envv,
            GLib.SpawnFlags.DEFAULT,
            None,
            self,
            Gio.Cancellable(),
        )

    def on_child_exited(self, _terminal, _status: int) -> None:
        self.child_pid = 0

    def set_margin(self, margin: int) -> None:
        self.margin = margin
        GtkLayerShell.set_margin(self.window, GtkLayerShell.Edge.LEFT, margin)

    def measured_width(self) -> int:
        return max(WIDTH, self.window.get_allocated_width())

    def animate(self, destination: int, showing: bool) -> None:
        if self.animation_source:
            GLib.source_remove(self.animation_source)
            self.animation_source = 0

        origin = self.margin
        distance = abs(destination - origin)
        duration_ms = max(
            MIN_DURATION_MS,
            min(MAX_DURATION_MS, round(distance / PIXELS_PER_SECOND * 1_000)),
        )
        started = time.monotonic()
        self.write_state("showing" if showing else "hiding")

        def advance() -> bool:
            elapsed_ms = (time.monotonic() - started) * 1_000
            progress = min(1.0, elapsed_ms / duration_ms)
            eased = progress * progress * (3.0 - 2.0 * progress)
            self.set_margin(round(origin + (destination - origin) * eased))
            if progress < 1.0:
                return GLib.SOURCE_CONTINUE

            self.animation_source = 0
            if showing:
                self.write_state("visible")
                self.terminal.grab_focus()
            else:
                self.window.hide()
                self.write_state("hidden")
            return GLib.SOURCE_REMOVE

        self.animation_source = GLib.timeout_add(FRAME_MS, advance)

    def show(self) -> None:
        self.ensure_terminal()
        self.target_visible = True
        GtkLayerShell.set_keyboard_mode(self.window, GtkLayerShell.KeyboardMode.ON_DEMAND)
        if not self.window.get_visible():
            self.set_margin(-self.measured_width())
            self.window.show_all()
        GLib.idle_add(self.animate, VISIBLE_MARGIN, True)

    def hide(self) -> None:
        self.target_visible = False
        GtkLayerShell.set_keyboard_mode(self.window, GtkLayerShell.KeyboardMode.NONE)
        self.animate(-self.measured_width(), False)

    def toggle(self) -> bool:
        if self.target_visible:
            self.hide()
        else:
            self.show()
        return GLib.SOURCE_CONTINUE

    def write_state(self, state: str) -> None:
        temporary = STATE_FILE.with_suffix(".tmp")
        temporary.write_text(json.dumps({"state": state}) + "\n", encoding="utf-8")
        temporary.replace(STATE_FILE)

    def quit(self, *_args) -> bool:
        Gtk.main_quit()
        return GLib.SOURCE_REMOVE


def main() -> None:
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    with LOCK_FILE.open("w", encoding="utf-8") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return

        GLib.set_prgname("ai-chat-layer")
        layer = ChatLayer()
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR1, layer.toggle)
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, layer.quit)

        def mark_ready() -> bool:
            PID_FILE.write_text(f"{os.getpid()}\n", encoding="utf-8")
            return GLib.SOURCE_REMOVE

        GLib.idle_add(mark_ready)
        try:
            Gtk.main()
        finally:
            PID_FILE.unlink(missing_ok=True)
            STATE_FILE.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
