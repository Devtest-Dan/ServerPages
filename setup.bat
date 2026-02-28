@echo off
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
if not errorlevel 1 (
    for /f "tokens=*" %%i in ('node -v 2^>nul') do echo       Found Node.js %%i
    goto :ffmpeg
)

echo       Node.js not found. Installing...

if exist "%~dp0deps\node-setup.msi" (
    echo       Found local installer: deps\node-setup.msi
    copy /y "%~dp0deps\node-setup.msi" "%TEMP%\node-setup.msi" >nul
    goto :node_install
)

echo       Downloading from nodejs.org...
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi' -OutFile '%TEMP%\node-setup.msi' -UseBasicParsing"

:node_install
if not exist "%TEMP%\node-setup.msi" (
    echo       ERROR: No installer found. Install Node.js manually from https://nodejs.org/
    pause
    exit /b 1
)
echo       Running installer (this may take a minute)...
msiexec /i "%TEMP%\node-setup.msi" /qn /norestart
del /f /q "%TEMP%\node-setup.msi" 2>nul
set "PATH=%PATH%;C:\Program Files\nodejs"
where node >nul 2>&1
if errorlevel 1 (
    echo       ERROR: Node.js install failed. Install manually from https://nodejs.org/
    pause
    exit /b 1
)
echo       Node.js installed.
echo.

:: ── 3. Download FFmpeg ─────────────────────────────────────────────────────
:ffmpeg
if exist "bin\ffmpeg.exe" (
    echo [3/7] FFmpeg already exists, skipping.
    goto :npm_install
)

echo [3/7] Installing FFmpeg...
echo       This may take a minute (~80MB)...

if exist "%~dp0deps\ffmpeg.zip" (
    echo       Found local archive: deps\ffmpeg.zip
    copy /y "%~dp0deps\ffmpeg.zip" "%TEMP%\ffmpeg-serverpages.zip" >nul
    goto :ffmpeg_extract
)

echo       Downloading from github.com...
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip' -OutFile '%TEMP%\ffmpeg-serverpages.zip' -UseBasicParsing"

:ffmpeg_extract
if not exist "%TEMP%\ffmpeg-serverpages.zip" (
    echo       ERROR: No FFmpeg archive found. Please download manually:
    echo       1. Go to https://github.com/BtbN/FFmpeg-Builds/releases
    echo       2. Download ffmpeg-master-latest-win64-gpl.zip
    echo       3. Extract ffmpeg.exe to %~dp0bin\
    goto :npm_install
)

echo       Extracting...
if exist "%TEMP%\ffmpeg-serverpages-extract" rmdir /s /q "%TEMP%\ffmpeg-serverpages-extract"
powershell -Command "Expand-Archive -Path '%TEMP%\ffmpeg-serverpages.zip' -DestinationPath '%TEMP%\ffmpeg-serverpages-extract' -Force"

for /r "%TEMP%\ffmpeg-serverpages-extract" %%F in (ffmpeg.exe) do (
    copy /y "%%F" "bin\ffmpeg.exe" >nul 2>&1
    goto :ffmpeg_cleanup
)

:ffmpeg_cleanup
del /f /q "%TEMP%\ffmpeg-serverpages.zip" 2>nul
rmdir /s /q "%TEMP%\ffmpeg-serverpages-extract" 2>nul

if exist "bin\ffmpeg.exe" (
    echo       FFmpeg installed successfully.
) else (
    echo       ERROR: Could not extract FFmpeg. Please install manually.
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
if not errorlevel 1 goto :tailscale_configure

if exist "C:\Program Files\Tailscale\tailscale.exe" (
    set "PATH=%PATH%;C:\Program Files\Tailscale"
    goto :tailscale_configure
)

echo       Tailscale not found. Installing...

if exist "%~dp0deps\tailscale-setup.msi" (
    echo       Found local installer: deps\tailscale-setup.msi
    copy /y "%~dp0deps\tailscale-setup.msi" "%TEMP%\tailscale-setup.msi" >nul
    goto :tailscale_install
)

powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; $r = Invoke-WebRequest -Uri 'https://pkgs.tailscale.com/stable/?mode=json' -UseBasicParsing | ConvertFrom-Json; $msi = $r.MSIs.amd64; Invoke-WebRequest -Uri \"https://pkgs.tailscale.com/stable/$msi\" -OutFile '%TEMP%\tailscale-setup.msi' -UseBasicParsing"

:tailscale_install
if not exist "%TEMP%\tailscale-setup.msi" (
    echo       ERROR: No installer found. Install Tailscale manually from https://tailscale.com/download
    pause
    exit /b 1
)
echo       Running installer...
msiexec /i "%TEMP%\tailscale-setup.msi" /qn /norestart TS_UNATTENDEDMODE=always
del /f /q "%TEMP%\tailscale-setup.msi" 2>nul
set "PATH=%PATH%;C:\Program Files\Tailscale"
timeout /t 5 /nobreak >nul
where tailscale >nul 2>&1
if errorlevel 1 (
    echo       ERROR: Tailscale install failed. Install manually from https://tailscale.com/download
    pause
    exit /b 1
)
echo       Tailscale installed.

:tailscale_configure
tailscale status >nul 2>&1
if errorlevel 1 (
    echo       Logging in to Tailscale...
    echo       A browser window will open — sign in and come back.
    tailscale login
    echo.
)

echo       Enabling unattended mode...
tailscale set --unattended 2>nul
echo       Done.

echo       Enabling Funnel on port 3333...
tailscale funnel --bg 3333 2>nul
echo       Done.

echo.
echo       Your URL:
tailscale funnel status 2>nul || tailscale status 2>nul | findstr /i "Funnel"
echo.

:: ── 7. Hide Tailscale tray icon ────────────────────────────────────────────
echo [7/7] Hiding Tailscale tray icon...

if exist "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Tailscale.lnk" (
    del /f /q "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Tailscale.lnk" 2>nul
    echo       Removed Tailscale startup shortcut.
) else (
    echo       Tailscale startup shortcut already removed.
)

taskkill /IM tailscale-ipn.exe /F >nul 2>&1
echo       Killed Tailscale GUI (tray icon removed).
echo       Tailscale service continues running in the background.
echo.

:: ── Start ServerPages now ──────────────────────────────────────────────────
echo Starting ServerPages...
wscript.exe "%~dp0bin\launch-hidden.vbs"
timeout /t 3 /nobreak >nul

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
