"""Windows exe entry: Flask on a background thread, shown in a native WebView2 window.

No console and no browser. The Linux desktop app is desktop.py (GTK); pywebview
is only used here because its Windows backend (Edge WebView2) works, unlike GTK.
"""
import os
import socket
import sys
import threading
import time
import urllib.request
from pathlib import Path

HOST = "127.0.0.1"
PORT = 5057
URL = f"http://{HOST}:{PORT}/"
TITLE = "Drift Tool — DB Schema Compare"


def _redirect_output() -> None:
    """A windowed exe has no stdout/stderr; send prints and Flask logs to a file."""
    if sys.stdout is not None and sys.stderr is not None:
        return
    base = Path(sys.executable).resolve().parent if getattr(sys, "frozen", False) else Path(__file__).parent
    log_dir = base / "work"
    log_dir.mkdir(exist_ok=True)
    stream = open(log_dir / "desktop.log", "a", encoding="utf-8", buffering=1)
    sys.stdout = sys.stdout or stream
    sys.stderr = sys.stderr or stream


def _message_box(text: str) -> None:
    import ctypes
    ctypes.windll.user32.MessageBoxW(None, text, TITLE, 0x10)


def _already_running() -> bool:
    with socket.socket() as s:
        return s.connect_ex((HOST, PORT)) == 0


def _wait_for_flask(timeout: float = 30) -> bool:
    end = time.time() + timeout
    while time.time() < end:
        try:
            urllib.request.urlopen(URL, timeout=2)
            return True
        except Exception:
            time.sleep(0.3)
    return False


def main() -> None:
    _redirect_output()
    import webview

    if not _already_running():
        import app as flask_app

        def pick_bak() -> str | None:
            if not webview.windows:
                return None
            dialog = getattr(getattr(webview, "FileDialog", None), "OPEN", None) or webview.OPEN_DIALOG
            picked = webview.windows[0].create_file_dialog(
                dialog, file_types=("SQL Server backups (*.bak)", "All files (*.*)"))
            return str(Path(picked[0])) if picked else None

        flask_app.register_bak_picker(pick_bak)
        threading.Thread(
            target=lambda: flask_app.app.run(host=HOST, port=PORT, debug=False,
                                             threaded=True, use_reloader=False),
            daemon=True,
        ).start()
        if not _wait_for_flask():
            _message_box("The Drift Tool server did not start. See work\\desktop.log.")
            sys.exit(1)

    webview.create_window(TITLE, URL, width=1280, height=800, min_size=(900, 600))
    try:
        webview.start(gui="edgechromium")
    except Exception as e:
        print(f"[desktop] WebView2 failed: {e}")
        _message_box(
            "Could not open the app window. Install the Microsoft Edge WebView2 Runtime "
            "(https://go.microsoft.com/fwlink/p/?LinkId=2124703) and start Drift Tool again.")
        sys.exit(1)
    os._exit(0)


if __name__ == "__main__":
    main()
