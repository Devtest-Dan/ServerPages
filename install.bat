@echo off
setlocal enabledelayedexpansion
title ServerPages Installer
cd /d "%~dp0"

set "INSTALL_DIR=D:\ServerPages"

echo ============================================
echo   ServerPages - One-Click Installer
echo ============================================
echo.

:: ── Check if already installed ───────────────────────────────────────────
if exist "%INSTALL_DIR%\server\server.js" (
    echo   Already installed at %INSTALL_DIR%
    echo   Running setup to update configuration...
    echo.
    cd /d "%INSTALL_DIR%"
    goto :run_setup
)

:: ── Download repo (no git needed) ────────────────────────────────────────
echo [0] Downloading ServerPages...
set "REPO_ZIP=%TEMP%\serverpages-repo.zip"
set "REPO_EXTRACT=%TEMP%\serverpages-extract"

powershell -Command "& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://github.com/Devtest-Dan/ServerPages/archive/refs/heads/master.zip' -OutFile '%REPO_ZIP%' }" 2>nul

if not exist "%REPO_ZIP%" (
    echo     ERROR: Download failed. Check your internet connection.
    pause
    exit /b 1
)

echo     Extracting to %INSTALL_DIR%...
if exist "%REPO_EXTRACT%" rmdir /s /q "%REPO_EXTRACT%"
powershell -Command "& { Expand-Archive -Path '%REPO_ZIP%' -DestinationPath '%REPO_EXTRACT%' -Force }" 2>nul

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
xcopy "%REPO_EXTRACT%\ServerPages-master\*" "%INSTALL_DIR%\" /E /Y /Q >nul 2>&1

del /f /q "%REPO_ZIP%" 2>nul
rmdir /s /q "%REPO_EXTRACT%" 2>nul

if not exist "%INSTALL_DIR%\server\server.js" (
    echo     ERROR: Extraction failed.
    pause
    exit /b 1
)

echo     Done.
echo.
cd /d "%INSTALL_DIR%"

:run_setup
call "%INSTALL_DIR%\setup.bat"
