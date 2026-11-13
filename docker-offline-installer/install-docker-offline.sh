#!/usr/bin/env bash
# ==============================================================================
# Garnet Q-Resil — Master Parent Offline Docker Installer
# Auto-detects operating system and delegates to dedicated installer:
#   - Linux   -> linux/install-linux.sh
#   - macOS   -> mac/install-mac.sh
#   - Windows -> windows/install-windows.ps1
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=========================================================="
echo "    Garnet Q-Resil — Offline Docker Setup                 "
echo "=========================================================="

KERNEL="$(uname -s 2>/dev/null || echo "Unknown")"

case "${KERNEL}" in
  Darwin*)
    echo "==> Detected OS: macOS (Darwin)"
    echo "==> Launching macOS installer: mac/install-mac.sh"
    exec bash "${SCRIPT_DIR}/mac/install-mac.sh" "$@"
    ;;
  Linux*)
    # Check if running in WSL
    if grep -qi microsoft /proc/version 2>/dev/null; then
      echo "==> Detected OS: Windows Subsystem for Linux (WSL)"
      if command -v powershell.exe &>/dev/null && [ -f "${SCRIPT_DIR}/windows/install-windows.ps1" ]; then
        echo "==> Delegating to Windows PowerShell installer..."
        exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "${SCRIPT_DIR}/windows/install-windows.ps1" 2>/dev/null || echo "${SCRIPT_DIR}/windows/install-windows.ps1")"
      fi
    fi
    echo "==> Detected OS: Linux"
    echo "==> Launching Linux installer: linux/install-linux.sh"
    exec bash "${SCRIPT_DIR}/linux/install-linux.sh" "$@"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "==> Detected OS: Windows (Git Bash / MSYS)"
    echo "==> Launching Windows installer: windows/install-windows.ps1"
    if command -v powershell.exe &>/dev/null; then
      exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "${SCRIPT_DIR}/windows/install-windows.ps1" 2>/dev/null || echo "${SCRIPT_DIR}/windows/install-windows.ps1")"
    else
      echo "[ERROR] powershell.exe not found. Please run 'install-docker-offline.bat' or 'windows/install-windows.ps1' directly."
      exit 1
    fi
    ;;
  *)
    echo "==> Platform: ${KERNEL}. Attempting Linux installer fallback..."
    exec bash "${SCRIPT_DIR}/linux/install-linux.sh" "$@"
    ;;
esac
