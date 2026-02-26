@echo off
title ServerPages - Stopping...
cd /d "%~dp0"

echo Stopping ServerPages...
echo.

:: Create stop flag (graceful shutdown)
echo stop > "stop.flag"
echo Sent stop signal...

:: Wait a moment for graceful shutdown
timeout /t 3 /nobreak >nul

:: Force kill if still running
tasklist /FI "IMAGENAME eq node.exe" /FO CSV /NH 2>nul | findstr /i "node.exe" >nul 2>&1
if not errorlevel 1 (
    :: Only kill node processes running our server
    for /f "tokens=2 delims=," %%i in ('wmic process where "name='node.exe' and commandline like '%%ServerPages%%'" get processid /format:csv 2^>nul ^| findstr /r "[0-9]"') do (
        taskkill /PID %%i /F >nul 2>&1
    )
)

:: Kill any remaining ffmpeg
taskkill /IM ffmpeg.exe /F >nul 2>&1

:: Clean up
del /f /q "stop.flag" 2>nul
del /f /q "stream\*.ts" 2>nul
del /f /q "stream\*.m3u8" 2>nul

echo.
echo ServerPages stopped.
echo.
timeout /t 2 >nul
