# ==============================================================================
# Garnet Q-Resil — Air-Gapped Shutdown Script for Windows
# ==============================================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BundleDir = Split-Path -Parent $ScriptDir
Set-Location $BundleDir

Write-Host "==> Stopping Garnet Q-Resil services..." -ForegroundColor Cyan
& docker compose down

Write-Host "==> [SUCCESS] All services stopped." -ForegroundColor Green

