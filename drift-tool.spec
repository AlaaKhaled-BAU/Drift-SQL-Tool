# PyInstaller spec for the Drift Tool exe.
# Build: build-windows.bat  (or ./build.sh on Linux)
# Output: dist/DriftTool/DriftTool(.exe).
# Windows: windows_app.py, a native WebView2 window with no console (checked by tools/check_windows_exe.py).
# Linux: app.py, Flask + browser (the Linux desktop window is run-desktop.sh).
# work/ and an optional .env live beside the executable, not inside the bundle.
import sys

IS_WINDOWS = sys.platform == "win32"
ENTRY = "windows_app.py" if IS_WINDOWS else "app.py"

a = Analysis(
    [ENTRY],
    pathex=["."],
    datas=[
        ("templates", "templates"),
        ("static", "static"),
        ("exclude-from-drift.txt", "."),
        ("TUTORIAL.md", "."),
    ],
    hiddenimports=[
        "app",
        "pymssql._mssql",
        "pymssql._pymssql",
        "pyodbc",
        "tkinter",
        "tkinter.filedialog",
    ] + (["webview", "webview.platforms.edgechromium", "webview.platforms.winforms", "clr"] if IS_WINDOWS else []),
    excludes=["gi", "pytest"],
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="DriftTool",
    console=not IS_WINDOWS,
)
coll = COLLECT(exe, a.binaries, a.datas, name="DriftTool")
