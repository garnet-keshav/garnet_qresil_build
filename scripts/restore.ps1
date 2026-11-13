# ==============================================================================
# Garnet Q-Resil — Database Restore Script for Windows
# Usage: .\restore.ps1 <path\to\qresil_backup_*.sql>
# ==============================================================================
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$BackupPath
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BundleDir = Split-Path -Parent $ScriptDir

# Auto-resolve path inside backups/ directory
if (-not (Test-Path $BackupPath) -and (Test-Path (Join-Path $BundleDir "backups\$BackupPath"))) {
    $BackupPath = Join-Path $BundleDir "backups\$BackupPath"
}

if (-not (Test-Path $BackupPath)) {
    Write-Host "[ERROR] Backup file not found: $BackupPath" -ForegroundColor Red
    exit 1
}

$DbContainer = & docker ps -q -f "name=garnet-offline-build-db" | Select-Object -First 1
if (-not $DbContainer) {
    Write-Host "[ERROR] Database container is not running. Please start the stack with 'start.bat' first." -ForegroundColor Red
    exit 1
}

$BackendContainer = & docker ps -q -f "name=garnet-offline-build-backend" | Select-Object -First 1
if (-not $BackendContainer) { $BackendContainer = "garnet-offline-build-backend-1" }

Write-Host "==> Restoring database to '$DbContainer'..." -ForegroundColor Cyan
Get-Content $BackupPath | & docker exec -i $DbContainer psql -U cbomkit -d postgres

Write-Host "==> Restarting backend container '$BackendContainer' to reload state..." -ForegroundColor Cyan
& docker restart $BackendContainer | Out-Null

Write-Host "==> [SUCCESS] Database restored successfully!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan

