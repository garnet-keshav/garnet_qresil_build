#!/usr/bin/env bash
# ==============================================================================
# Garnet Q-Resil — 1-Click Database Backup Script
# Creates a compressed, timestamped SQL backup of all scans, CBOMs, and reports.
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUP_DIR="${BUNDLE_DIR}/backups"
mkdir -p "${BACKUP_DIR}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/qresil_backup_${TIMESTAMP}.sql.gz"

echo "=========================================================="
echo "    Garnet Q-Resil — Database Backup                     "
echo "=========================================================="

# Determine docker command
DOCKER_CMD="docker"
if ! docker info &>/dev/null && command -v sg &>/dev/null && sg docker -c "docker info" &>/dev/null 2>&1; then
  DOCKER_CMD="sg docker -c docker"
elif ! docker info &>/dev/null && command -v sudo &>/dev/null; then
  DOCKER_CMD="sudo docker"
fi

if ! ${DOCKER_CMD} ps --format '{{.Names}}' | grep -q "garnet-offline-build-db"; then
  echo "[ERROR] Database container is not running."
  echo "        Please start the application with './start.sh' first."
  exit 1
fi

DB_CONTAINER="$(${DOCKER_CMD} ps -q -f "name=garnet-offline-build-db" | head -n 1)"
[ -z "${DB_CONTAINER}" ] && DB_CONTAINER="garnet-offline-build-db-1"

echo "==> Creating full database backup from container '${DB_CONTAINER}'..."
${DOCKER_CMD} exec "${DB_CONTAINER}" pg_dump -U cbomkit -d postgres --clean --if-exists | gzip > "${BACKUP_FILE}"

FILESIZE="$(ls -lh "${BACKUP_FILE}" | awk '{print $5}')"
echo "==> [SUCCESS] Backup created successfully!"
echo "    File: ${BACKUP_FILE} (${FILESIZE})"
echo "=========================================================="

