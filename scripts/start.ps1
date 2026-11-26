# ==============================================================================
# Garnet Q-Resil — 1-Click Air-Gapped Startup Script for Windows
# ==============================================================================
[CmdletBinding()]
param()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BundleDir = Split-Path -Parent $ScriptDir
Set-Location $BundleDir

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "    Garnet Q-Resil — Windows Offline Deployment           " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Ensure Docker is installed and running
$DockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
$DefaultDockerExe = "C:\Program Files\Docker\Docker\resources\bin\docker.exe"

if (-not $DockerCmd -and (Test-Path $DefaultDockerExe)) {
    $env:Path += ";C:\Program Files\Docker\Docker\resources\bin"
    $DockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
}

$Ready = $false

if ($DockerCmd) {
    try {
        $null = & docker info 2>&1
        if ($LASTEXITCODE -eq 0) { $Ready = $true }
    } catch {}
}

if (-not $Ready) {
    $WindowsInstallerDir = Join-Path $BundleDir "docker-offline-installer\windows"
    $InstallerExe = Get-ChildItem -Path $WindowsInstallerDir -Filter "*.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($InstallerExe) {
        $InstallerScript = Join-Path $WindowsInstallerDir "install-windows.ps1"
        if (Test-Path $InstallerScript) {
            & powershell.exe -ExecutionPolicy Bypass -File $InstallerScript
        }
    } else {
        Write-Host "[!] Docker is not installed on this Windows machine, and the offline installer was omitted." -ForegroundColor Yellow
        Write-Host "    Please install Docker Desktop for Windows and run start.bat again." -ForegroundColor Yellow
        exit 1
    }
}

# 2. Reassemble multi-part container images if needed, then load
if (-not (Test-Path "q-resil-images.tar") -and -not (Test-Path "q-resil-images.tar.gz")) {
    $GzParts = Get-ChildItem -Path "docker-images\q-resil-images.tar.gz.part_*" -ErrorAction SilentlyContinue
    if (-not $GzParts) { $GzParts = Get-ChildItem -Path "q-resil-images.tar.gz.part_*" -ErrorAction SilentlyContinue }
    
    if ($GzParts) {
        Write-Host "==> Multi-part compressed container images detected. Reassembling into q-resil-images.tar.gz..." -ForegroundColor Cyan
        cmd.exe /c "copy /b `"$($GzParts[0].DirectoryName)\q-resil-images.tar.gz.part_*`" q-resil-images.tar.gz" | Out-Null
        Write-Host "==> Container image archive successfully reassembled." -ForegroundColor Green
    } else {
        $TarParts = Get-ChildItem -Path "docker-images\q-resil-images.tar.part_*" -ErrorAction SilentlyContinue
        if (-not $TarParts) { $TarParts = Get-ChildItem -Path "q-resil-images.tar.part_*" -ErrorAction SilentlyContinue }
        if ($TarParts) {
            Write-Host "==> Multi-part container images detected. Reassembling into q-resil-images.tar..." -ForegroundColor Cyan
            cmd.exe /c "copy /b `"$($TarParts[0].DirectoryName)\q-resil-images.tar.part_*`" q-resil-images.tar" | Out-Null
            Write-Host "==> Container image archive successfully reassembled." -ForegroundColor Green
        }
    }
}

if (Test-Path "q-resil-images.tar.gz") {
    Write-Host "==> Loading container images from q-resil-images.tar.gz (offline)..." -ForegroundColor Cyan
    & docker load -i q-resil-images.tar.gz
    Write-Host "==> Container images loaded into local Docker storage." -ForegroundColor Green
} elseif (Test-Path "q-resil-images.tar") {
    Write-Host "==> Loading container images from q-resil-images.tar (offline)..." -ForegroundColor Cyan
    & docker load -i q-resil-images.tar
    Write-Host "==> Container images loaded into local Docker storage." -ForegroundColor Green
}

# 3. Check and resolve available ports automatically
function Test-PortInUse([int]$Port) {
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
        $listener.Start()
        $listener.Stop()
        return $false
    } catch {
        return $true
    }
}

function Find-NextFreePort([int]$Port, [string]$Name) {
    $CurrentPort = $Port
    while (Test-PortInUse $CurrentPort) {
        Write-Host "    [!] Port $CurrentPort ($Name) is already in use. Trying next port $($CurrentPort + 1)..." -ForegroundColor Yellow
        $CurrentPort++
    }
    if ($CurrentPort -ne $Port) {
        Write-Host "    ==> Auto-assigned port $CurrentPort for $Name (default $Port was busy)." -ForegroundColor Cyan
    }
    return $CurrentPort
}

# Stop any previously running garnet-offline-build stack to recycle ports cleanly
$ExistingContainers = & docker compose ps -q 2>$null
if ($ExistingContainers) {
    Write-Host "==> Existing Garnet Q-Resil containers detected. Stopping them to recycle ports..." -ForegroundColor Cyan
    & docker compose down 2>$null | Out-Null
    Start-Sleep -Seconds 1
}

Write-Host "==> Checking port availability..." -ForegroundColor Cyan
$env:GARNET_UI_PORT = Find-NextFreePort 8000 "Web UI"
$env:GARNET_API_PORT = Find-NextFreePort 8081 "Backend API"
$env:GARNET_DB_PORT = Find-NextFreePort 5432 "PostgreSQL Database"
$env:GARNET_REMEDIATION_PORT = Find-NextFreePort 9400 "Remediation Engine"

# 4. Start the stack
Write-Host "==> Bringing up Garnet Q-Resil containers..." -ForegroundColor Cyan
& docker compose up -d

# 5. Self-heal database credentials and initialize remediation DB
$DbContainer = & docker ps -q -f "name=garnet-offline-build-db" | Select-Object -First 1
if (-not $DbContainer) { $DbContainer = "garnet-offline-build-db-1" }

$DbReady = $false
$Attempts = 0
while (-not $DbReady -and ($Attempts -lt 15)) {
    $null = & docker exec $DbContainer pg_isready -h 127.0.0.1 -p $env:GARNET_DB_PORT -U cbomkit -d postgres 2>&1
    if ($LASTEXITCODE -eq 0) {
        $DbReady = $true
        & docker exec $DbContainer psql -h 127.0.0.1 -p $env:GARNET_DB_PORT -U cbomkit -d postgres -c "ALTER USER cbomkit WITH PASSWORD 'cbomkit_secure_poc_pass';" 2>$null | Out-Null
        & docker exec $DbContainer psql -h 127.0.0.1 -p $env:GARNET_DB_PORT -U cbomkit -d postgres -c "CREATE DATABASE remediation OWNER cbomkit;" 2>$null | Out-Null
        & docker compose restart remediation 2>$null | Out-Null
        break
    }
    Start-Sleep -Seconds 1
    $Attempts++
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  [SUCCESS] Garnet Q-Resil is LIVE on Windows!            " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Web UI:             http://localhost:$($env:GARNET_UI_PORT)" -ForegroundColor Cyan
Write-Host "  Backend API:        http://localhost:$($env:GARNET_API_PORT)/api" -ForegroundColor Cyan
Write-Host "  Remediation Engine: http://localhost:$($env:GARNET_REMEDIATION_PORT)/q/health" -ForegroundColor Cyan
Write-Host "  Database:           127.0.0.1:$($env:GARNET_DB_PORT)" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Logs:      docker compose logs -f"
Write-Host "  Stop:      .\stop.bat (or .\scripts\stop.ps1)"
Write-Host "==========================================================" -ForegroundColor Green
