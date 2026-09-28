@echo off
rem Builds dist\DriftTool\DriftTool.exe from a clean venv. Run from the repo folder.
setlocal
cd /d "%~dp0"

if not exist .build-venv\Scripts\python.exe (
    py -3 -m venv .build-venv || python -m venv .build-venv || goto :fail
)
.build-venv\Scripts\python -m pip install -q --upgrade pip || goto :fail
.build-venv\Scripts\python -m pip install -q -r requirements.txt pyinstaller || goto :fail
.build-venv\Scripts\python -m PyInstaller --noconfirm --clean drift-tool.spec || goto :fail
rem sqlpackage (self-contained, .NET included) ships inside the app folder.
if not exist .build-cache\sqlpackage.zip (
    if not exist .build-cache mkdir .build-cache
    powershell -NoProfile -Command "Invoke-WebRequest https://aka.ms/sqlpackage-windows -OutFile .build-cache\sqlpackage.zip" || goto :fail
)
powershell -NoProfile -Command "Expand-Archive -Force .build-cache\sqlpackage.zip dist\DriftTool\sqlpackage" || goto :fail
.build-venv\Scripts\python tools\check_windows_exe.py dist\DriftTool || goto :fail

if exist .env copy /y .env dist\DriftTool\.env >nul
echo.
echo Built: dist\DriftTool\DriftTool.exe
echo Keep the whole dist\DriftTool folder together; work\ is created beside the exe.
exit /b 0

:fail
echo Build failed.
exit /b 1
