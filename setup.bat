@echo off
setlocal enabledelayedexpansion
title ServerPages Setup
cd /d "%~dp0"

echo ============================================
echo   ServerPages - One-Time Setup
echo ============================================
echo.

:: ── 1. Create directories ──────────────────────────────────────────────────
echo [1/7] Creating directories...
if not exist "bin" mkdir bin
if not exist "stream" mkdir stream
if not exist "logs" mkdir logs
if not exist "server\public" mkdir server\public
echo       Done.
echo.

:: ── 2. Install Node.js (if missing) ──────────────────────────────────────
echo [2/7] Checking Node.js...
where node >nul 2>&1
if errorlevel 1 (
    echo       Node.js not found. Installing...
    set "NODE_MSI=%TEMP%\node-setup.msi"
    powershell -Command "& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi' -OutFile '!NODE_MSI!' }" 2>nul
    if not exist "!NODE_MSI!" (
        echo       ERROR: Download failed. Install Node.js manually from https://nodejs.org/
        pause
        exit /b 1
    )
    echo       Running installer (this may take a minute^)...
    msiexec /i "!NODE_MSI!" /qn /norestart
    del /f /q "!NODE_MSI!" 2>nul
    :: Refresh PATH
    set "PATH=%PATH%;C:\Program Files\nodejs"
    where node >nul 2>&1
    if errorlevel 1 (
        echo       ERROR: Node.js install failed. Install manually from https://nodejs.org/
        pause
        exit /b 1
    )
    echo       Node.js installed.
) else (
    for /f "tokens=*" %%i in ('node -v 2^>nul') do echo       Found Node.js %%i
)
echo.

:: ── 3. Download FFmpeg ─────────────────────────────────────────────────────
if exist "bin\ffmpeg.exe" (
    echo [3/7] FFmpeg already exists, skipping download.
) else (
    echo [3/7] Downloading FFmpeg...
    echo       This may take a minute (~80MB^)...

    set "FFMPEG_URL=https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
    set "FFMPEG_ZIP=%TEMP%\ffmpeg-serverpages.zip"
    set "FFMPEG_EXTRACT=%TEMP%\ffmpeg-serverpages-extract"

    powershell -Command "& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%FFMPEG_URL%' -OutFile '%FFMPEG_ZIP%' }" 2>nul

    if not exist "!FFMPEG_ZIP!" (
        echo       ERROR: Download failed. Please download FFmpeg manually:
        echo       1. Go to https://github.com/BtbN/FFmpeg-Builds/releases
        echo       2. Download ffmpeg-master-latest-win64-gpl.zip
        echo       3. Extract ffmpeg.exe to %~dp0bin\
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
        echo       FFmpeg installed successfully.
    ) else (
        echo       ERROR: Could not extract FFmpeg. Please install manually.
    )
)
echo.

:: ── 4. npm install ─────────────────────────────────────────────────────────
:npm_install
echo [4/7] Installing Node.js dependencies...
cd server
call npm install --production 2>nul
if errorlevel 1 (
    echo       ERROR: npm install failed.
    cd ..
    goto :scheduler
)
cd ..
echo       Done.
echo.

:: ── 5. Task Scheduler ──────────────────────────────────────────────────────
:scheduler
echo [5/7] Configuring Task Scheduler (auto-start + auto-restart)...

schtasks /delete /tn "ServerPages" /f >nul 2>&1

:: Generate task XML — runs on any user logon, hidden, restarts on failure
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
echo       ^<Command^>wscript.exe^</Command^>
echo       ^<Arguments^>"%~dp0bin\launch-hidden.vbs"^</Arguments^>
echo       ^<WorkingDirectory^>%~dp0server^</WorkingDirectory^>
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
    echo       WARNING: Could not create scheduled task. Try running as Administrator.
) else (
    echo       Task "ServerPages" created (any user logon, restart on failure).
)
del /f /q "%TEMP%\serverpages-task.xml" 2>nul
echo.

:: ── 6. Tailscale ───────────────────────────────────────────────────────────
:tailscale
echo [6/7] Configuring Tailscale...

where tailscale >nul 2>&1
if errorlevel 1 (
    :: Check default install location
    if exist "C:\Program Files\Tailscale\tailscale.exe" (
        set "PATH=%PATH%;C:\Program Files\Tailscale"
    ) else (
        echo       Tailscale not found. Installing...
        set "TS_MSI=%TEMP%\tailscale-setup.msi"
        powershell -Command "& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $r = Invoke-WebRequest -Uri 'https://pkgs.tailscale.com/stable/?mode=json' -UseBasicParsing | ConvertFrom-Json; $msi = ($r.exes | Where-Object { $_ -like '*amd64*.msi' } | Select-Object -First 1); Invoke-WebRequest -Uri \"https://pkgs.tailscale.com/stable/$msi\" -OutFile '!TS_MSI!' }" 2>nul
        if not exist "!TS_MSI!" (
            echo       ERROR: Download failed. Install Tailscale manually from https://tailscale.com/download
            pause
            exit /b 1
        )
        echo       Running installer...
        msiexec /i "!TS_MSI!" /qn /norestart TS_UNATTENDEDMODE=always
        del /f /q "!TS_MSI!" 2>nul
        set "PATH=%PATH%;C:\Program Files\Tailscale"
        :: Wait for service to start
        timeout /t 5 /nobreak >nul
        where tailscale >nul 2>&1
        if errorlevel 1 (
            echo       ERROR: Tailscale install failed. Install manually from https://tailscale.com/download
            pause
            exit /b 1
        )
        echo       Tailscale installed.
    )
)

:: Check if logged in
tailscale status >nul 2>&1
if errorlevel 1 (
    echo       Logging in to Tailscale...
    echo       A browser window will open — sign in and come back.
    tailscale login
    echo.
)

:: Set unattended mode
echo       Enabling unattended mode...
tailscale set --unattended 2>nul
echo       Done.

:: Enable Funnel on port 3333
echo       Enabling Funnel on port 3333...
tailscale funnel --bg 3333 2>nul
echo       Done.

:: Show the URL
echo.
echo       Your URL:
tailscale funnel status 2>nul || tailscale status 2>nul | findstr /i "Funnel"
echo.

:: ── 7. Hide Tailscale tray icon ────────────────────────────────────────────
echo [7/7] Hiding Tailscale tray icon...

:: Remove GUI startup shortcut
if exist "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Tailscale.lnk" (
    del /f /q "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Tailscale.lnk" 2>nul
    echo       Removed Tailscale startup shortcut.
) else (
    echo       Tailscale startup shortcut already removed.
)

:: Kill the GUI process
taskkill /IM tailscale-ipn.exe /F >nul 2>&1
echo       Killed Tailscale GUI (tray icon removed).
echo       Tailscale service continues running in the background.
echo.

:: ── Start ServerPages now ──────────────────────────────────────────────────
echo Starting ServerPages...
wscript.exe "%~dp0bin\launch-hidden.vbs"
timeout /t 3 /nobreak >nul

:: Verify
powershell -Command "try { $s = Invoke-RestMethod 'http://localhost:3333/api/status'; Write-Host '       Server: OK (FFmpeg:' $s.ffmpeg ', Quality:' $s.quality ')' } catch { Write-Host '       WARNING: Server not responding yet. It may need a few more seconds.' }" 2>nul
echo.

echo ============================================
echo   Setup complete!
echo ============================================
echo.
echo   Everything is running — fully hidden, no windows, no tray icons.
echo   Auto-starts on any user login, auto-restarts on failure.
echo.
echo   Local:     http://localhost:3333
echo   Internet:  Check Tailscale status for your URL
echo.
echo   To stop:   stop.bat
echo.
pause
