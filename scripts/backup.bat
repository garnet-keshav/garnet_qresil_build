@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0backup.ps1"
if %ERRORLEVEL% neq 0 pause

