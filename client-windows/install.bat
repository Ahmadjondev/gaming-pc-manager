@echo off
setlocal EnableDelayedExpansion
title Game Booster - Automated Setup

:: Check for Administrative Privileges and auto-elevate
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [*] Requesting Administrator Privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo ================================================================
echo               AUTOMATED GAME BOOSTER SETUP
echo ================================================================
echo.

set TARGET_DIR=C:\GameBooster
set LEGACY_DIR=C:\GameRoomAgent
set DEFAULT_URL=wss://gaming-pc-manager.onrender.com/ws/client

echo [*] Target Directory: %TARGET_DIR%
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

echo [*] Stopping running instances if active...
taskkill /F /IM GameBooster.exe >nul 2>&1
taskkill /F /IM GameRoomAgent.exe >nul 2>&1
timeout /t 1 /nobreak >nul

:: Clean legacy startup tasks & registry entries
schtasks /delete /tn "GameRoomAgent" /f >nul 2>&1
reg delete "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" /v "GameRoomAgent" /f >nul 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "GameRoomAgent" /f >nul 2>&1

:: Clean legacy firewall rules
netsh advfirewall firewall delete rule name="GameRoomAgent" >nul 2>&1
netsh advfirewall firewall delete rule name="GameRoomAgent-DirectControl" >nul 2>&1

echo [*] Copying Game Booster Executable...
copy /Y "%~dp0GameBooster.exe" "%TARGET_DIR%\" >nul

:: Migrate legacy config if exists
if not exist "%TARGET_DIR%\config.json" (
    if exist "%LEGACY_DIR%\config.json" (
        echo [*] Migrating existing configuration from %LEGACY_DIR%...
        copy /Y "%LEGACY_DIR%\config.json" "%TARGET_DIR%\config.json" >nul
    )
)

:: Automatically configure config.json if not present
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
        echo   "autoLockOnDisconnect": false,
        echo   "controlPort": 48999,
        echo   "enableDirectControl": true
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
    "$action = New-ScheduledTaskAction -Execute '%TARGET_DIR%\GameBooster.exe'; " ^
    "$trigger = New-ScheduledTaskTrigger -AtLogOn; " ^
    "$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0; " ^
    "Register-ScheduledTask -TaskName 'GameBooster' -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force" >nul 2>&1

:: 2. Registry Run Keys (Machine-wide and Current User fallback)
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" /v "GameBooster" /t REG_SZ /d "\"%TARGET_DIR%\GameBooster.exe\"" /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "GameBooster" /t REG_SZ /d "\"%TARGET_DIR%\GameBooster.exe\"" /f >nul 2>&1

:: 3. Windows Firewall Rules (Outbound + Direct High-FPS Inbound LAN/WAN Control Port 48999)
netsh advfirewall firewall add rule name="GameBooster" dir=out action=allow program="%TARGET_DIR%\GameBooster.exe" enable=yes >nul 2>&1
netsh advfirewall firewall add rule name="GameBooster-DirectControl" dir=in action=allow protocol=TCP localport=48999 enable=yes >nul 2>&1
netsh http add urlacl url=http://*:48999/ user=Everyone >nul 2>&1 || netsh http add urlacl url=http://*:48999/ user=Users >nul 2>&1

echo.
echo ================================================================
echo   [+] GAME BOOSTER INSTALLATION SUCCESSFUL!
echo   [+] Station Name: %COMPUTERNAME%
echo   [+] Auto-Run on Boot: ENABLED (Task Scheduler + Highest Admin)
echo ================================================================
echo.
echo Starting Game Booster now...
start "" "%TARGET_DIR%\GameBooster.exe"

timeout /t 3 >nul
exit /b
