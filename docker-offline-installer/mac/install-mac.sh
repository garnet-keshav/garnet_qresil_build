#!/usr/bin/env bash
# ==============================================================================
# Garnet Q-Resil — Offline Docker Installer for macOS (Apple Silicon & Intel)
# 100% Offline — Air-gapped enterprise ready
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=========================================================="
echo "    macOS Offline Docker Setup                            "
echo "=========================================================="

ARCH="$(uname -m)"
echo "==> macOS Hardware Architecture: ${ARCH}"

# 1. Check if Docker and Compose are already installed
if command -v docker &>/dev/null && (docker compose version &>/dev/null || docker-compose version &>/dev/null); then
  echo "==> Docker is already installed on this Mac:"
  docker --version
  docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
else
  # 2. Select matching offline DMG
  DMG_FILE=""
  if [ "${ARCH}" = "arm64" ] && [ -f "${SCRIPT_DIR}/arm64/Docker.dmg" ]; then
    DMG_FILE="${SCRIPT_DIR}/arm64/Docker.dmg"
  elif [ "${ARCH}" = "x86_64" ] && [ -f "${SCRIPT_DIR}/intel/Docker.dmg" ]; then
    DMG_FILE="${SCRIPT_DIR}/intel/Docker.dmg"
  else
    DMG_FILE="$(find "${SCRIPT_DIR}" -name "*.dmg" 2>/dev/null | head -n 1)"
  fi

  if [ -n "${DMG_FILE}" ] && [ -f "${DMG_FILE}" ]; then
    echo "==> Found offline installer: ${DMG_FILE}"
    echo "==> Mounting DMG and installing Docker.app to /Applications..."

    # Terminate any stale Docker processes before replacing
    killall Docker "Docker Desktop" 2>/dev/null || true

    MOUNT_POINT="/Volumes/GarnetDockerInstall_$$"
    hdiutil attach "${DMG_FILE}" -nobrowse -mountpoint "${MOUNT_POINT}" -quiet

    echo "==> Copying Docker.app to /Applications (requires admin privileges)..."
    sudo rm -rf /Applications/Docker.app
    sudo cp -R "${MOUNT_POINT}/Docker.app" /Applications/

    hdiutil detach "${MOUNT_POINT}" -quiet || true

    echo "==> Initializing privileged Docker helper components..."
    sudo /Applications/Docker.app/Contents/MacOS/install --privileged-components || true
    echo "==> Docker installation complete."
  else
    echo ""
    echo "[!] Docker is not installed on this Mac, and the offline macOS installer DMG was omitted."
    echo "    Please install Docker Desktop for macOS (https://www.docker.com/products/docker-desktop) and re-run ./start.sh."
    exit 1
  fi
fi

# 3. Ensure Docker Desktop application is running
if ! docker info &>/dev/null; then
  echo "==> Starting Docker Desktop..."
  open -a Docker || open -a "/Applications/Docker.app" || true

  echo "==> Waiting for Docker daemon to become ready (this may take 15-30 seconds)..."
  ATTEMPTS=0
  MAX_ATTEMPTS=45
  until docker info &>/dev/null || [ ${ATTEMPTS} -ge ${MAX_ATTEMPTS} ]; do
    printf "."
    sleep 2
    ATTEMPTS=$((ATTEMPTS + 1))
  done
  echo ""

  if ! docker info &>/dev/null; then
    echo "[ERROR] Docker Desktop did not start in time. Please open Docker manually and retry."
    exit 1
  fi
fi

echo ""
echo "=========================================================="
echo " [SUCCESS] Docker & Compose ready on macOS!               "
echo "=========================================================="
docker --version
docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
echo "=========================================================="

