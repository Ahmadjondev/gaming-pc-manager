@echo off
setlocal EnableDelayedExpansion
title Gaming Laptop Agent - Automated Setup

:: Check for Administrative Privileges and auto-elevate
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [*] Requesting Administrator Privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo ================================================================
echo        AUTOMATED GAMING LAPTOP AGENT INSTALLER
echo ================================================================
echo.

set TARGET_DIR=C:\GameRoomAgent
set DEFAULT_URL=wss://gaming-pc-manager.onrender.com/ws/client

echo [*] Target Directory: %TARGET_DIR%
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

echo [*] Copying Agent Executable...
copy /Y "%~dp0GameRoomAgent.exe" "%TARGET_DIR%\" >nul

:: Automatically configure config.json
if not exist "%TARGET_DIR%\config.json" (
    echo.
    echo [*] Configuring Server Connection...
    set SERVER_URL=%1
    if "!SERVER_URL!"=="" (
        set SERVER_URL=%DEFAULT_URL%
    )

    echo Generating configuration for laptop: %COMPUTERNAME%...
    (
        echo {
        echo   "serverUrl": "!SERVER_URL!",
        echo   "stationId": "%COMPUTERNAME%",
        echo   "stationName": "%COMPUTERNAME%",
        echo   "authToken": "gameroom_secret_key_2026",
        echo   "autoStartWithWindows": true,
        echo   "telemetryIntervalSeconds": 3,
        echo   "autoLockOnDisconnect": false
        echo }
    ) > "%TARGET_DIR%\config.json"
    echo [+] Config created with Station: %COMPUTERNAME% and Server: !SERVER_URL!
) else (
    echo [*] Existing config.json detected in %TARGET_DIR%. Keeping current settings.
)

echo.
echo [*] Setting up Auto-Run on Laptop Power-On / Boot...

:: 1. Windows Task Scheduler (Runs with Highest Admin privileges, starts even on battery)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$action = New-ScheduledTaskAction -Execute '%TARGET_DIR%\GameRoomAgent.exe'; " ^
    "$trigger = New-ScheduledTaskTrigger -AtLogOn; " ^
    "$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0; " ^
    "Register-ScheduledTask -TaskName 'GameRoomAgent' -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force" >nul 2>&1

:: 2. Registry Run Keys (Machine-wide and Current User fallback)
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" /v "GameRoomAgent" /t REG_SZ /d "\"%TARGET_DIR%\GameRoomAgent.exe\"" /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "GameRoomAgent" /t REG_SZ /d "\"%TARGET_DIR%\GameRoomAgent.exe\"" /f >nul 2>&1

:: 3. Windows Firewall Rule (Allow Outbound WebSocket Traffic)
netsh advfirewall firewall add rule name="GameRoomAgent" dir=out action=allow program="%TARGET_DIR%\GameRoomAgent.exe" enable=yes >nul 2>&1

echo.
echo ================================================================
echo   [+] INSTALLATION SUCCESSFUL!
echo   [+] Station Name: %COMPUTERNAME%
echo   [+] Auto-Run on Boot: ENABLED (Task Scheduler + Highest Admin)
echo ================================================================
echo.
echo Starting GameRoomAgent now...
start "" "%TARGET_DIR%\GameRoomAgent.exe"

timeout /t 3 >nul
exit /b
