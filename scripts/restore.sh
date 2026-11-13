#!/usr/bin/env bash
# ==============================================================================
# Garnet Q-Resil — Database Restore Script
# Restores a compressed SQL backup created by backup.sh.
# Usage: ./restore.sh <path/to/qresil_backup_*.sql.gz>
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUP_FILE="$1"

# Auto-resolve relative filename inside backups/ directory
if [ -n "${BACKUP_FILE}" ] && [ ! -f "${BACKUP_FILE}" ] && [ -f "${BUNDLE_DIR}/backups/${BACKUP_FILE}" ]; then
  BACKUP_FILE="${BUNDLE_DIR}/backups/${BACKUP_FILE}"
fi

if [ -z "${BACKUP_FILE}" ] || [ ! -f "${BACKUP_FILE}" ]; then
  echo "[ERROR] Backup file not found: ${BACKUP_FILE}"
  echo "Usage: ./start.sh restore <backup_file.sql.gz>"
  echo ""
  echo "Available backups in backups/:"
  ls -1 "${BUNDLE_DIR}/backups" 2>/dev/null | grep -E "\.sql(\.gz)?$" || echo "  (none found)"
  echo ""
  exit 1
fi

echo "=========================================================="
echo "    Garnet Q-Resil — Database Restore                    "
echo "=========================================================="
echo "==> Restoring from: ${BACKUP_FILE}"

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

BACKEND_CONTAINER="$(${DOCKER_CMD} ps -q -f "name=garnet-offline-build-backend" | head -n 1)"
[ -z "${BACKEND_CONTAINER}" ] && BACKEND_CONTAINER="garnet-offline-build-backend-1"

echo "==> Restoring database to '${DB_CONTAINER}'..."
gunzip -c "${BACKUP_FILE}" | ${DOCKER_CMD} exec -i "${DB_CONTAINER}" psql -U cbomkit -d postgres

echo "==> Restarting backend container '${BACKEND_CONTAINER}' to reload restored state..."
${DOCKER_CMD} restart "${BACKEND_CONTAINER}" >/dev/null

echo "==> [SUCCESS] Database restored successfully!"
echo "=========================================================="

