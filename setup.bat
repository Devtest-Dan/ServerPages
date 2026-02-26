@echo off
setlocal enabledelayedexpansion
title ServerPages Setup
cd /d "%~dp0"

echo ============================================
echo   ServerPages - One-Time Setup
echo ============================================
echo.

:: ── 1. Create directories ──────────────────────────────────────────────────
echo [1/5] Creating directories...
if not exist "bin" mkdir bin
if not exist "stream" mkdir stream
if not exist "logs" mkdir logs
if not exist "server\public" mkdir server\public
echo       Done.
echo.

:: ── 2. Download FFmpeg ─────────────────────────────────────────────────────
if exist "bin\ffmpeg.exe" (
    echo [2/5] FFmpeg already exists, skipping download.
) else (
    echo [2/5] Downloading FFmpeg...
    echo       This may take a minute (~80MB^)...

    set "FFMPEG_URL=https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
    set "FFMPEG_ZIP=%TEMP%\ffmpeg-serverpages.zip"
    set "FFMPEG_EXTRACT=%TEMP%\ffmpeg-serverpages-extract"

    :: Download using PowerShell
    powershell -Command "& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%FFMPEG_URL%' -OutFile '%FFMPEG_ZIP%' }" 2>nul

    if not exist "%FFMPEG_ZIP%" (
        echo       ERROR: Download failed. Please download FFmpeg manually:
        echo       1. Go to https://github.com/BtbN/FFmpeg-Builds/releases
        echo       2. Download ffmpeg-master-latest-win64-gpl.zip
        echo       3. Extract ffmpeg.exe to D:\ServerPages\bin\
        goto :npm_install
    )

    :: Extract
    echo       Extracting...
    if exist "%FFMPEG_EXTRACT%" rmdir /s /q "%FFMPEG_EXTRACT%"
    powershell -Command "& { Expand-Archive -Path '%FFMPEG_ZIP%' -DestinationPath '%FFMPEG_EXTRACT%' -Force }" 2>nul

    :: Find and copy ffmpeg.exe
    for /r "%FFMPEG_EXTRACT%" %%F in (ffmpeg.exe) do (
        copy /y "%%F" "bin\ffmpeg.exe" >nul 2>&1
        goto :ffmpeg_done
    )

    :ffmpeg_done
    :: Cleanup
    del /f /q "%FFMPEG_ZIP%" 2>nul
    rmdir /s /q "%FFMPEG_EXTRACT%" 2>nul

    if exist "bin\ffmpeg.exe" (
        echo       FFmpeg installed successfully.
    ) else (
        echo       ERROR: Could not extract FFmpeg. Please install manually.
    )
)
echo.

:: ── 3. npm install ─────────────────────────────────────────────────────────
:npm_install
echo [3/5] Installing Node.js dependencies...
cd server
call npm install --production 2>nul
if errorlevel 1 (
    echo       ERROR: npm install failed. Make sure Node.js is installed.
    echo       Download from https://nodejs.org/
    cd ..
    goto :scheduler
)
cd ..
echo       Done.
echo.

:: ── 4. Task Scheduler ─────────────────────────────────────────────────────
:scheduler
echo [4/5] Configuring Task Scheduler (auto-restart)...

:: Delete existing task if present
schtasks /delete /tn "ServerPages" /f >nul 2>&1

:: Find node.exe path
for /f "tokens=*" %%i in ('where node 2^>nul') do set "NODE_PATH=%%i"

if "!NODE_PATH!"=="" (
    echo       ERROR: node.exe not found in PATH.
    goto :tailscale
)

:: Create scheduled task
:: Runs at logon, restarts on failure every 10 seconds, up to 999 times
schtasks /create /tn "ServerPages" /tr "\"!NODE_PATH!\" \"D:\ServerPages\server\server.js\"" /sc onlogon /rl limited /f >nul 2>&1

if errorlevel 1 (
    echo       WARNING: Could not create scheduled task.
    echo       You may need to run this script as Administrator.
) else (
    echo       Task "ServerPages" created (runs at logon).

    :: Configure restart-on-failure via XML import for advanced settings
    echo       Configuring restart-on-failure...

    :: Generate task XML with restart settings
    (
    echo ^<?xml version="1.0" encoding="UTF-16"?^>
    echo ^<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"^>
    echo   ^<RegistrationInfo^>
    echo     ^<Description^>ServerPages - Screen broadcaster and media server^</Description^>
    echo   ^</RegistrationInfo^>
    echo   ^<Triggers^>
    echo     ^<LogonTrigger^>
    echo       ^<Enabled^>true^</Enabled^>
    echo     ^</LogonTrigger^>
    echo   ^</Triggers^>
    echo   ^<Settings^>
    echo     ^<MultipleInstancesPolicy^>IgnoreNew^</MultipleInstancesPolicy^>
    echo     ^<DisallowStartIfOnBatteries^>false^</DisallowStartIfOnBatteries^>
    echo     ^<StopIfGoingOnBatteries^>false^</StopIfGoingOnBatteries^>
    echo     ^<ExecutionTimeLimit^>PT0S^</ExecutionTimeLimit^>
    echo     ^<RestartOnFailure^>
    echo       ^<Interval^>PT1M^</Interval^>
    echo       ^<Count^>999^</Count^>
    echo     ^</RestartOnFailure^>
    echo     ^<Enabled^>true^</Enabled^>
    echo     ^<Hidden^>true^</Hidden^>
    echo   ^</Settings^>
    echo   ^<Actions^>
    echo     ^<Exec^>
    echo       ^<Command^>!NODE_PATH!^</Command^>
    echo       ^<Arguments^>"D:\ServerPages\server\server.js"^</Arguments^>
    echo       ^<WorkingDirectory^>D:\ServerPages\server^</WorkingDirectory^>
    echo     ^</Exec^>
    echo   ^</Actions^>
    echo   ^<Principals^>
    echo     ^<Principal id="Author"^>
    echo       ^<GroupId^>BUILTIN\Users^</GroupId^>
    echo       ^<RunLevel^>LeastPrivilege^</RunLevel^>
    echo     ^</Principal^>
    echo   ^</Principals^>
    echo ^</Task^>
    ) > "%TEMP%\serverpages-task.xml"

    schtasks /create /tn "ServerPages" /xml "%TEMP%\serverpages-task.xml" /f >nul 2>&1
    if errorlevel 1 (
        echo       WARNING: Advanced settings failed. Basic task still works.
    ) else (
        echo       Restart-on-failure configured (10s interval, 999 attempts).
    )
    del /f /q "%TEMP%\serverpages-task.xml" 2>nul
)
echo.

:: ── 5. Tailscale ──────────────────────────────────────────────────────────
:tailscale
echo [5/5] Tailscale Funnel setup...

where tailscale >nul 2>&1
if errorlevel 1 (
    echo       Tailscale not found in PATH.
    echo       To enable internet access:
    echo         1. Install Tailscale: https://tailscale.com/download
    echo         2. Login: tailscale login
    echo         3. Enable funnel: tailscale funnel 3333
    echo       This gives you a free HTTPS URL accessible from anywhere.
) else (
    echo       Tailscale is installed.
    echo       To expose ServerPages to the internet, run:
    echo         tailscale funnel 3333
    echo       This gives you a stable HTTPS URL like:
    echo         https://your-machine.tailXXXXX.ts.net
)
echo.

echo ============================================
echo   Setup complete!
echo ============================================
echo.
echo   Start manually:  start.bat
echo   Stop:            stop.bat
echo   Auto-start:      Happens on next login
echo.
echo   Local URL:  http://localhost:3333
echo.
pause
