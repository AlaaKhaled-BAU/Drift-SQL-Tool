"""Fail the Windows build unless DriftTool.exe is a windowed desktop app.

Checks the PE subsystem (2 = GUI, 3 = console), that pywebview was bundled,
and that the bundled sqlpackage runs without a separate .NET install.
"""
import struct
import subprocess
import sys
from pathlib import Path

GUI, CONSOLE = 2, 3


def subsystem(exe: Path) -> int:
    data = exe.read_bytes()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError(f"{exe} is not a PE file")
    return struct.unpack_from("<H", data, pe + 4 + 20 + 68)[0]


def main(dist: Path) -> int:
    exe = dist / "DriftTool.exe"
    if not exe.is_file():
        print(f"FAIL: {exe} missing")
        return 1
    sub = subsystem(exe)
    if sub != GUI:
        print(f"FAIL: {exe} subsystem is {sub} ({'console' if sub == CONSOLE else 'unknown'}); must be GUI (2).")
        return 1
    if not any(dist.rglob("webview*")):
        print("FAIL: pywebview is not in the bundle; the exe would have no window.")
        return 1
    sqlpackage = dist / "sqlpackage" / "sqlpackage.exe"
    if not sqlpackage.is_file():
        print(f"FAIL: {sqlpackage} missing; .bak compares would need a separate install.")
        return 1
    r = subprocess.run([str(sqlpackage), "/Version"], capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        print(f"FAIL: bundled sqlpackage does not run:\n{r.stdout}\n{r.stderr}")
        return 1
    print(f"OK: {exe} is a windowed desktop app; bundled sqlpackage {r.stdout.strip()}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1] if len(sys.argv) > 1 else "dist/DriftTool")))
