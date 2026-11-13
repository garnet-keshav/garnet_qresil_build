#!/usr/bin/env bash
# ==============================================================================
# Garnet Q-Resil — Air-Gapped Shutdown Script
# Handles direct, sg docker, and sudo execution modes cleanly.
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "==> Stopping Garnet Q-Resil services..."

stop_stack() {
  if command -v podman &> /dev/null && ! command -v docker &> /dev/null; then
    if command -v podman-compose &> /dev/null; then
      podman-compose down
    else
      podman compose down
    fi
    return 0
  fi

  # Docker runtime
  COMPOSE_BIN="docker compose"
  if ! docker compose version &>/dev/null && ! sudo docker compose version &>/dev/null 2>&1; then
    if command -v docker-compose &>/dev/null; then
      COMPOSE_BIN="docker-compose"
    fi
  fi

  run_down() {
    local file="$1"
    if [ -f "${file}" ]; then
      if docker info &>/dev/null; then
        ${COMPOSE_BIN} -f "${file}" down 2>/dev/null || true
      elif command -v sg &>/dev/null && sg docker -c "docker info" &>/dev/null 2>&1; then
        sg docker -c "${COMPOSE_BIN} -f \"${file}\" down" 2>/dev/null || true
      elif command -v sudo &>/dev/null; then
        sudo ${COMPOSE_BIN} -f "${file}" down 2>/dev/null || true
      else
        ${COMPOSE_BIN} -f "${file}" down 2>/dev/null || true
      fi
    fi
  }

  run_down "docker-compose.host.yml"
  run_down "docker-compose.yml"
}

stop_stack

echo "==> All services stopped."
