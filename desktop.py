#!/usr/bin/env python3
"""Drift Tool — Flask + GTK WebKit window + native .bak picker.

pywebview's GTK backend leaves the WebKit input surface at 1x1, so clicks
never hit the page. Own the Gtk.Window and expand the view.
"""
import os
import queue
import sys
import threading
import time
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
LOG = os.path.join(os.path.expanduser("~"), ".drift-tool-desktop.log")

CHOOSER_ENABLED = False
_CHOOSER_LOCK = threading.Lock()
_MAIN_WIN = None


def log(m):
    with open(LOG, "a") as f:
        f.write(f"{time.strftime('%H:%M:%S')} {m}\n")


def chooser_available() -> bool:
    return CHOOSER_ENABLED


def enable_desktop_chooser():
    global CHOOSER_ENABLED
    CHOOSER_ENABLED = True


def _has_display() -> bool:
    return bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


def _run_dialog_on_gtk_main() -> str | None:
    from gi.repository import Gtk

    dialog = Gtk.FileChooserNative.new(
        "Select SQL Server backup",
        _MAIN_WIN,
        Gtk.FileChooserAction.OPEN,
        "_Open",
        "_Cancel",
    )
    dialog.set_modal(True)
    filt = Gtk.FileFilter()
    filt.set_name("SQL Server backups (*.bak)")
    filt.add_pattern("*.bak")
    dialog.add_filter(filt)
    log("bak chooser showing")
    resp = dialog.run()
    path = None
    if resp == Gtk.ResponseType.ACCEPT:
        path = dialog.get_filename()
    dialog.destroy()
    log(f"bak chooser done path={path!r}")
    return path


def pick_bak_blocking(timeout: float = 300.0) -> str | None:
    """Block until the user picks a .bak (GTK main thread). Desktop only."""
    if not CHOOSER_ENABLED or not _has_display():
        return None
    from gi.repository import GLib

    result_q: queue.Queue = queue.Queue(maxsize=1)

    def _idle():
        try:
            result_q.put(_run_dialog_on_gtk_main())
        except Exception as e:
            log(f"bak chooser error: {e}")
            result_q.put(None)
        return False

    with _CHOOSER_LOCK:
        GLib.idle_add(_idle)
        try:
            return result_q.get(timeout=timeout)
        except queue.Empty:
            return None


log("started")
log(f"DISPLAY={os.environ.get('DISPLAY', '(unset)')}")
log(f"WAYLAND_DISPLAY={os.environ.get('WAYLAND_DISPLAY', '(unset)')}")
log(f"cwd={os.getcwd()}")

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import Gtk, WebKit2

from app import app

HOST = "127.0.0.1"
PORT = 5057


def start_flask():
    log("flask thread starting")
    try:
        app.run(host=HOST, port=PORT, debug=False, threaded=True, use_reloader=False)
    except Exception as e:
        log(f"flask error: {e}")


def wait_for_flask(timeout=15):
    start = time.time()
    while time.time() - start < timeout:
        try:
            urllib.request.urlopen(f"http://{HOST}:{PORT}/")
            return True
        except Exception:
            time.sleep(0.3)
    return False


def set_main_window(win):
    global _MAIN_WIN
    _MAIN_WIN = win


if __name__ == "__main__":
    enable_desktop_chooser()
    import app as flask_app
    flask_app.register_bak_picker(pick_bak_blocking)
    t = threading.Thread(target=start_flask, daemon=True)
    t.start()
    if not wait_for_flask():
        log("flask failed to start within timeout")
        sys.exit(1)
    log("flask ready, opening window")
    try:
        win = Gtk.Window(title="Drift Tool — DB Schema Compare")
        win.set_default_size(1280, 800)
        view = WebKit2.WebView()
        view.set_hexpand(True)
        view.set_vexpand(True)
        win.add(view)
        view.load_uri(f"http://{HOST}:{PORT}/")
        win.connect("destroy", Gtk.main_quit)
        win.show_all()
        set_main_window(win)
        log("window registered, starting GUI loop")
        Gtk.main()
        log("window closed normally")
    except Exception as e:
        log(f"webview error: {e}")
        sys.exit(1)
