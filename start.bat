@echo off
title ScreenCast - Starting...
cd /d "%~dp0"

echo Starting ScreenCast...
echo.

:: Check for node
where node >nul 2>&1
if errorlevel 1 (
    echo ERROR: Node.js not found. Install from https://nodejs.org/
    pause
    exit /b 1
)

:: Check for ffmpeg
if not exist "bin\ffmpeg.exe" (
    echo ERROR: ffmpeg.exe not found. Run setup.bat first.
    pause
    exit /b 1
)

:: Check for node_modules
if not exist "server\node_modules" (
    echo ERROR: Dependencies not installed. Run setup.bat first.
    pause
    exit /b 1
)

:: Start the server (hidden via start /min)
start /min "ScreenCast" node "D:\ScreenCast\server\server.js"

echo ScreenCast started!
echo.
echo   Local:  http://localhost:3333
echo.
echo The server is running in the background.
echo Use stop.bat to stop it.
echo.
timeout /t 3 >nul
