# ==============================================================================
# Garnet Q-Resil — Offline Docker Installer for Windows
# Supports Windows 10/11 Pro, Enterprise, and Windows Server (WSL2 / Hyper-V)
# ==============================================================================
[CmdletBinding()]
param()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "    Windows Offline Docker Setup                          " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check if Docker CLI is in PATH or default install directory
$DockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
$DefaultDockerExe = "C:\Program Files\Docker\Docker\resources\bin\docker.exe"

if (-not $DockerCmd -and (Test-Path $DefaultDockerExe)) {
    $env:Path += ";C:\Program Files\Docker\Docker\resources\bin"
    $DockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
}

$IsInstalled = $false
if ($DockerCmd) {
    try {
        & docker --version | Out-Null
        $IsInstalled = $true
    } catch {
        $IsInstalled = $false
    }
}

if ($IsInstalled) {
    Write-Host "==> Docker is already installed on this machine:" -ForegroundColor Green
    & docker --version
} else {
    Write-Host "==> Docker not found. Checking for offline installer..." -ForegroundColor Yellow

    # Look for Docker Desktop Installer.exe in windows/ directory
    $InstallerExe = Get-ChildItem -Path $ScriptDir -Filter "*.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($InstallerExe) {
        Write-Host "==> Found offline installer: $($InstallerExe.Name)" -ForegroundColor Green
        Write-Host "==> Running unattended Docker Desktop installation (this may take 2-4 minutes)..." -ForegroundColor Cyan

        $InstallProcess = Start-Process -FilePath $InstallerExe.FullName -ArgumentList "install --quiet --accept-license" -Wait -PassThru

        if ($InstallProcess.ExitCode -eq 0 -or $InstallProcess.ExitCode -eq 3010) {
            Write-Host "==> [SUCCESS] Docker Desktop installed successfully." -ForegroundColor Green
            $env:Path += ";C:\Program Files\Docker\Docker\resources\bin"
        } else {
            Write-Host "[WARNING] Installer exited with code: $($InstallProcess.ExitCode)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[!] Docker is not installed on this machine, and the offline Windows installer was omitted." -ForegroundColor Yellow
        Write-Host "    Please install Docker Desktop for Windows and run start.bat again." -ForegroundColor Yellow
        exit 1
    }
}

# 2. Ensure Docker Desktop application is running
$DockerProcess = Get-Process "Docker Desktop" -ErrorAction SilentlyContinue
$DockerDesktopApp = "C:\Program Files\Docker\Docker\Docker Desktop.exe"

if (-not $DockerProcess -and (Test-Path $DockerDesktopApp)) {
    Write-Host "==> Launching Docker Desktop background engine..." -ForegroundColor Cyan
    Start-Process -FilePath $DockerDesktopApp
}

# 3. Wait for Docker engine to become healthy and accept commands
Write-Host "==> Waiting for Docker engine to initialize..." -NoNewline -ForegroundColor Cyan
$Attempts = 0
$MaxAttempts = 45
$Ready = $false

while (-not $Ready -and ($Attempts -lt $MaxAttempts)) {
    try {
        $null = & docker info 2>&1
        if ($LASTEXITCODE -eq 0) {
            $Ready = $true
            break
        }
    } catch {}

    Write-Host "." -NoNewline
    Start-Sleep -Seconds 3
    $Attempts++
}
Write-Host ""

if (-not $Ready) {
    Write-Host "[ERROR] Docker engine did not become ready in time." -ForegroundColor Red
    Write-Host "        Please open Docker Desktop from the Start menu and wait for the status indicator to turn green." -ForegroundColor Yellow
    exit 1
}

Write-Host "==> [SUCCESS] Docker daemon is running and ready on Windows." -ForegroundColor Green

