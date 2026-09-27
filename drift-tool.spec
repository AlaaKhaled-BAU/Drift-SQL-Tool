# PyInstaller spec for the Drift Tool exe (Windows and Linux alike).
# Build: build-windows.bat  (or ./build.sh on Linux)
# Output: dist/DriftTool/DriftTool(.exe). Runs from app.py: Flask + browser + native .bak dialog.
# work/ and an optional .env live beside the executable, not inside the bundle.

a = Analysis(
    ["app.py"],
    pathex=["."],
    datas=[
        ("templates", "templates"),
        ("static", "static"),
        ("exclude-from-drift.txt", "."),
        ("TUTORIAL.md", "."),
    ],
    hiddenimports=["pymssql._mssql", "pymssql._pymssql"],
    excludes=["gi", "pytest"],
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="DriftTool",
    console=True,
)
coll = COLLECT(exe, a.binaries, a.datas, name="DriftTool")
