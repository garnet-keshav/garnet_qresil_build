@echo off
rem ==============================================================================
rem Garnet Q-Resil — Windows 1-Click Startup Wrapper
rem Double-click or run from Command Prompt
rem ==============================================================================
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Startup failed. Press any key to exit.
    pause >nul
)

