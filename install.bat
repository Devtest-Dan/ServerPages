@echo off
setlocal enabledelayedexpansion
title ScreenCast - Full Installer

:: ── Self-elevate to Administrator ────────────────────────────────────────────
net session >nul 2>&1
if errorlevel 1 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "INSTALL_DIR=D:\ScreenCast"

echo.
echo ============================================
echo   ScreenCast - One-Click Installer
echo ============================================
echo.
echo   This will:
echo     1. Install Git        (if missing)
echo     2. Install Node.js    (if missing)
echo     3. Clone the repo     (if missing)
echo     4. Download FFmpeg
echo     5. Install npm dependencies
echo     6. Configure Task Scheduler (all users)
echo     7. Start the server
echo.
echo   Install path: %INSTALL_DIR%
echo.
pause

:: ── 1. Install Git ──────────────────────────────────────────────────────────
echo.
echo [1/7] Checking Git...
where git >nul 2>&1
if errorlevel 1 (
    echo       Git not found. Installing via winget...
    winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements >nul 2>&1
    if errorlevel 1 (
        echo       ERROR: winget failed. Please install Git manually:
        echo       https://git-scm.com/download/win
        pause
        exit /b 1
    )
    :: Refresh PATH so git is available in this session
    set "PATH=%PATH%;C:\Program Files\Git\cmd"
    echo       Git installed.
) else (
    echo       Git already installed.
)

:: ── 2. Install Node.js ──────────────────────────────────────────────────────
echo.
echo [2/7] Checking Node.js...
where node >nul 2>&1
if errorlevel 1 (
    echo       Node.js not found. Installing via winget...
    winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements >nul 2>&1
    if errorlevel 1 (
        echo       ERROR: winget failed. Please install Node.js manually:
        echo       https://nodejs.org/
        pause
        exit /b 1
    )
    :: Refresh PATH so node/npm are available in this session
    for /f "tokens=*" %%i in ('powershell -Command "[System.Environment]::GetEnvironmentVariable('Path','Machine')"') do set "PATH=%%i;%PATH%"
    echo       Node.js installed.
) else (
    echo       Node.js already installed.
)

:: Verify both are now available
where git >nul 2>&1
if errorlevel 1 (
    echo.
    echo       ERROR: Git still not in PATH. Please restart this script after
    echo       installing Git manually: https://git-scm.com/download/win
    pause
    exit /b 1
)
where node >nul 2>&1
if errorlevel 1 (
    echo.
    echo       ERROR: Node.js still not in PATH. Please restart this script after
    echo       installing Node.js manually: https://nodejs.org/
    pause
    exit /b 1
)

:: ── 3. Clone repo ───────────────────────────────────────────────────────────
echo.
echo [3/7] Cloning repository...
if exist "%INSTALL_DIR%\server\server.js" (
    echo       Repository already exists at %INSTALL_DIR%, pulling latest...
    cd /d "%INSTALL_DIR%"
    git pull >nul 2>&1
) else (
    git clone https://github.com/Devtest-Dan/ScreenCast.git "%INSTALL_DIR%" >nul 2>&1
    if errorlevel 1 (
        echo       ERROR: Clone failed. Check your internet connection.
        pause
        exit /b 1
    )
    echo       Cloned to %INSTALL_DIR%.
)
cd /d "%INSTALL_DIR%"

:: ── 4. Download FFmpeg ──────────────────────────────────────────────────────
echo.
if not exist "bin" mkdir bin
if not exist "stream" mkdir stream
if not exist "logs" mkdir logs
if not exist "server\public" mkdir server\public

if exist "bin\ffmpeg.exe" (
    echo [4/7] FFmpeg already exists, skipping download.
) else (
    echo [4/7] Downloading FFmpeg (~80MB, may take a minute^)...

    set "FFMPEG_URL=https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
    set "FFMPEG_ZIP=%TEMP%\ffmpeg-screencast.zip"
    set "FFMPEG_EXTRACT=%TEMP%\ffmpeg-screencast-extract"

    powershell -Command "& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '!FFMPEG_URL!' -OutFile '!FFMPEG_ZIP!' }" 2>nul

    if not exist "!FFMPEG_ZIP!" (
        echo       ERROR: Download failed. Please download manually:
        echo       https://github.com/BtbN/FFmpeg-Builds/releases
        echo       Extract ffmpeg.exe to %INSTALL_DIR%\bin\
        goto :npm_install
    )

    echo       Extracting...
    if exist "!FFMPEG_EXTRACT!" rmdir /s /q "!FFMPEG_EXTRACT!"
    powershell -Command "& { Expand-Archive -Path '!FFMPEG_ZIP!' -DestinationPath '!FFMPEG_EXTRACT!' -Force }" 2>nul

    for /r "!FFMPEG_EXTRACT!" %%F in (ffmpeg.exe) do (
        copy /y "%%F" "bin\ffmpeg.exe" >nul 2>&1
        goto :ffmpeg_done
    )

    :ffmpeg_done
    del /f /q "!FFMPEG_ZIP!" 2>nul
    rmdir /s /q "!FFMPEG_EXTRACT!" 2>nul

    if exist "bin\ffmpeg.exe" (
        echo       FFmpeg installed.
    ) else (
        echo       ERROR: Could not extract FFmpeg.
    )
)

:: ── 5. npm install ──────────────────────────────────────────────────────────
:npm_install
echo.
echo [5/7] Installing Node.js dependencies...
cd /d "%INSTALL_DIR%\server"
call npm install --production 2>nul
if errorlevel 1 (
    echo       ERROR: npm install failed.
    cd /d "%INSTALL_DIR%"
    goto :scheduler
)
cd /d "%INSTALL_DIR%"
echo       Done.

:: ── 6. Task Scheduler ───────────────────────────────────────────────────────
:scheduler
echo.
echo [6/7] Configuring Task Scheduler (all-user auto-start)...

schtasks /delete /tn "ScreenCast" /f >nul 2>&1

for /f "tokens=*" %%i in ('where node 2^>nul') do set "NODE_PATH=%%i"

if "!NODE_PATH!"=="" (
    echo       ERROR: node.exe not found in PATH.
    goto :start_server
)

(
echo ^<?xml version="1.0" encoding="UTF-16"?^>
echo ^<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"^>
echo   ^<RegistrationInfo^>
echo     ^<Description^>ScreenCast - Screen broadcaster and media server^</Description^>
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
echo       ^<Arguments^>"%INSTALL_DIR%\server\server.js"^</Arguments^>
echo       ^<WorkingDirectory^>%INSTALL_DIR%\server^</WorkingDirectory^>
echo     ^</Exec^>
echo   ^</Actions^>
echo   ^<Principals^>
echo     ^<Principal id="Author"^>
echo       ^<GroupId^>BUILTIN\Users^</GroupId^>
echo       ^<RunLevel^>LeastPrivilege^</RunLevel^>
echo     ^</Principal^>
echo   ^</Principals^>
echo ^</Task^>
) > "%TEMP%\screencast-task.xml"

schtasks /create /tn "ScreenCast" /xml "%TEMP%\screencast-task.xml" /f >nul 2>&1
if errorlevel 1 (
    echo       WARNING: Task Scheduler setup failed. Server will not auto-start.
    echo       You may need to run this script as Administrator.
) else (
    echo       Task created (all users, restart-on-failure, hidden).
)
del /f /q "%TEMP%\screencast-task.xml" 2>nul

:: ── 7. Start the server ─────────────────────────────────────────────────────
:start_server
echo.
echo [7/7] Starting ScreenCast...

:: Kill any existing instance
taskkill /f /fi "WINDOWTITLE eq ScreenCast" >nul 2>&1

cd /d "%INSTALL_DIR%"
start /min "ScreenCast" node "%INSTALL_DIR%\server\server.js"
echo       Server started.

echo.
echo ============================================
echo   Installation complete!
echo ============================================
echo.
echo   Local URL:   http://localhost:3333
echo   Live stream: http://localhost:3333/live.html
echo   File browse: http://localhost:3333/media.html
echo.
echo   Auto-starts on any user login.
echo   Use stop.bat to stop the server.
echo.
echo   Optional - expose to internet:
echo     1. Install Tailscale: https://tailscale.com/download
echo     2. Run: tailscale login
echo     3. Run: tailscale funnel 3333
echo.
pause
