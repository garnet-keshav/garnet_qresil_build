# ==============================================================================
# Garnet Q-Resil — Database Backup Script for Windows
# ==============================================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BundleDir = Split-Path -Parent $ScriptDir
$BackupDir = Join-Path $BundleDir "backups"
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupFile = Join-Path $BackupDir "qresil_backup_$Timestamp.sql"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "    Garnet Q-Resil — Windows Database Backup              " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$DbContainer = & docker ps -q -f "name=garnet-offline-build-db" | Select-Object -First 1
if (-not $DbContainer) {
    Write-Host "[ERROR] Database container is not running. Please start the stack with 'start.bat' first." -ForegroundColor Red
    exit 1
}

Write-Host "==> Creating full database backup from container '$DbContainer'..." -ForegroundColor Cyan
& docker exec $DbContainer pg_dump -U cbomkit -d postgres --clean --if-exists > $BackupFile

if (Test-Path $BackupFile) {
    $FileSize = (Get-Item $BackupFile).Length / 1KB
    Write-Host "==> [SUCCESS] Backup created successfully!" -ForegroundColor Green
    Write-Host "    File: $BackupFile ($([math]::Round($FileSize, 2)) KB)" -ForegroundColor Cyan
} else {
    Write-Host "[ERROR] Backup failed." -ForegroundColor Red
}
Write-Host "==========================================================" -ForegroundColor Cyan

