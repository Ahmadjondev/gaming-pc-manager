@echo off
title Gaming Laptop Agent Installer
echo ====================================================
echo   GAMING ROOM LAPTOP AGENT SETUP
echo ====================================================
echo.

set TARGET_DIR=C:\GameRoomAgent

echo [*] Creating directory %TARGET_DIR%...
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

echo [*] Installing files...
copy /Y "GameRoomAgent.exe" "%TARGET_DIR%\"
if not exist "%TARGET_DIR%\config.json" (
    copy /Y "config.json" "%TARGET_DIR%\"
)

echo [*] Enabling Windows Auto-Start on Boot...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "GameRoomAgent" /t REG_SZ /d "\"%TARGET_DIR%\GameRoomAgent.exe\"" /f

echo.
echo ====================================================
echo   INSTALLATION COMPLETED SUCCESSFULLY!
echo ====================================================
echo.
echo 1. Edit your server URL in: %TARGET_DIR%\config.json
echo 2. Launching GameRoomAgent now...
echo.
start "" "%TARGET_DIR%\GameRoomAgent.exe"
timeout /t 3 >nul
