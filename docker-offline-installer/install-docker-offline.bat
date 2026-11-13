@echo off
rem ==============================================================================
rem Garnet Q-Resil — Windows Docker Offline Installer Launcher
rem ==============================================================================
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\install-windows.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Docker installation encountered an issue. Press any key to exit.
    pause >nul
)
