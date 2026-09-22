#!/usr/bin/env python3
"""Drift Tool — Desktop wrapper (Flask + pywebview)."""
import os
import sys
import threading
import time
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
LOG = os.path.join(os.path.expanduser("~"), ".drift-tool-desktop.log")

def log(m):
    with open(LOG, "a") as f:
        f.write(f"{time.strftime('%H:%M:%S')} {m}\n")

log("started")
log(f"DISPLAY={os.environ.get('DISPLAY','(unset)')}")
log(f"WAYLAND_DISPLAY={os.environ.get('WAYLAND_DISPLAY','(unset)')}")
log(f"cwd={os.getcwd()}")

import webview
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

if __name__ == "__main__":
    t = threading.Thread(target=start_flask, daemon=True)
    t.start()
    if not wait_for_flask():
        log("flask failed to start within timeout")
        sys.exit(1)
    log("flask ready, opening window")
    try:
        webview.create_window(
            "Drift Tool — DB Schema Compare",
            f"http://{HOST}:{PORT}",
            width=1280, height=800,
            resizable=True,
        )
        log("window registered, starting GUI loop")
        webview.start(gui="gtk")
        log("window closed normally")
    except Exception as e:
        log(f"webview error: {e}")
        sys.exit(1)
