@echo off
cd /d "%~dp0"
if "%~1"=="" (
    echo Usage: restore.bat path\to\backup.sql
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0restore.ps1" -BackupPath "%~1"
if %ERRORLEVEL% neq 0 pause

