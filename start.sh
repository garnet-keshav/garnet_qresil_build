#!/usr/bin/env bash
# ==============================================================================
# Garnet Q-Resil — 1-Click Air-Gapped Startup Script
# Automatically detects OS (Ubuntu, RHEL, CentOS, Rocky, AlmaLinux, Debian, etc.)
# Handles Docker auto-installation, non-root permissions, and docker group setup.
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# 0. Subcommand routing (stop, backup, restore)
case "$1" in
  stop)
    exec "${SCRIPT_DIR}/stop.sh"
    ;;
  backup)
    exec "${SCRIPT_DIR}/scripts/backup.sh"
    ;;
  restore)
    shift
    exec "${SCRIPT_DIR}/scripts/restore.sh" "$@"
    ;;
esac

echo "=========================================================="
echo "    Garnet Q-Resil — Air-Gapped Deployment               "
echo "=========================================================="

# 1. Detect OS
OS_INFO="Linux"
IS_MAC="false"
if [ "$(uname -s)" = "Darwin" ]; then
  IS_MAC="true"
  OS_INFO="macOS $(sw_vers -productVersion 2>/dev/null || uname -r) ($(uname -m))"
elif [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_INFO="${NAME:-Linux} ${VERSION_ID:-}"
fi
echo "==> Target System OS: ${OS_INFO}"

# 2. Check if Docker or Podman is installed
RUNTIME=""
COMPOSE_CMD=""

check_installed_tools() {
  if command -v docker &>/dev/null; then
    RUNTIME="docker"
    if docker compose version &>/dev/null || sg docker -c "docker compose version" &>/dev/null 2>&1 || sudo docker compose version &>/dev/null 2>&1; then
      COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
      COMPOSE_CMD="docker-compose"
    fi
  elif command -v podman &>/dev/null; then
    RUNTIME="podman"
    if command -v podman-compose &>/dev/null; then
      COMPOSE_CMD="podman-compose"
    elif podman compose version &>/dev/null; then
      COMPOSE_CMD="podman compose"
    fi
  fi
}

check_installed_tools

# 3. If neither Docker nor Podman (or Compose) is found, install Docker
if [ -z "${RUNTIME}" ] || [ -z "${COMPOSE_CMD}" ]; then
  echo ""
  echo "[!] Neither Docker nor Podman (with Compose) was found on this system."

  # If running on macOS and the installer DMG was omitted, fail gracefully with instructions
  if [ "${IS_MAC}" = "true" ]; then
    if [ ! -f "./docker-offline-installer/mac/arm64/Docker.dmg" ] && [ ! -f "./docker-offline-installer/mac/intel/Docker.dmg" ]; then
      echo "[ERROR] Docker is not installed on this Mac, and the offline macOS installer DMG was omitted."
      echo "        Please install Docker Desktop for macOS (https://www.docker.com/products/docker-desktop) and re-run ./start.sh."
      exit 1
    fi
  fi

  echo "==> Initiating installation of Docker & Docker Compose..."
  
  if [ -f "./docker-offline-installer/install-docker-offline.sh" ]; then
    bash "./docker-offline-installer/install-docker-offline.sh"
    check_installed_tools
  else
    echo "[ERROR] Offline installer script not found!"
    exit 1
  fi
fi

if [ -z "${RUNTIME}" ] || [ -z "${COMPOSE_CMD}" ]; then
  echo "[ERROR] Failed to find or initialize a working container runtime."
  exit 1
fi

# 4. Resolve Runtime Execution Mode & Docker Group Permissions
EXEC_MODE="direct"  # direct, sg, sudo
CURRENT_USER="$(id -un 2>/dev/null || whoami)"

if [ "${RUNTIME}" = "docker" ]; then
  # Ensure docker daemon service is started
  if ! docker info &>/dev/null && ! sudo docker info &>/dev/null 2>&1; then
    echo "==> Docker daemon is stopped. Starting docker service..."
    if [ "${IS_MAC}" = "true" ]; then
      open -a Docker || open -a "/Applications/Docker.app" || true
      sleep 5
    elif command -v systemctl &>/dev/null; then
      sudo systemctl reset-failed docker 2>/dev/null || true
      sudo systemctl start docker 2>/dev/null || systemctl start docker 2>/dev/null || true
    else
      sudo service docker start 2>/dev/null || service docker start 2>/dev/null || true
    fi
    sleep 2
  fi

  # Check if non-sudo docker works directly
  if docker info &>/dev/null; then
    EXEC_MODE="direct"
  else
    echo "==> Non-root user '${CURRENT_USER}' encountered Docker socket permission restriction."

    # Check if user is in docker group in /etc/group
    if ! getent group docker 2>/dev/null | grep -q "\b${CURRENT_USER}\b"; then
      echo "==> Adding '${CURRENT_USER}' to the 'docker' group..."
      if command -v sudo &>/dev/null; then
        sudo groupadd -f docker 2>/dev/null || true
        sudo usermod -aG docker "${CURRENT_USER}" 2>/dev/null || true
      fi
    fi

    # Fix socket group ownership and permissions if needed
    if [ -S /var/run/docker.sock ] && command -v sudo &>/dev/null; then
      sudo chown root:docker /var/run/docker.sock 2>/dev/null || true
      sudo chmod 660 /var/run/docker.sock 2>/dev/null || true
    fi

    # Test if 'sg docker' allows running immediately without re-logging in
    if command -v sg &>/dev/null && sg docker -c "docker info" &>/dev/null 2>&1; then
      echo "==> Seamlessly activating 'docker' group for this session via 'sg docker'."
      EXEC_MODE="sg"
    elif command -v sudo &>/dev/null && sudo docker info &>/dev/null 2>&1; then
      echo "==> Using 'sudo docker' fallback (group membership will activate without sudo on next SSH login)."
      EXEC_MODE="sudo"
    else
      echo "[ERROR] Cannot communicate with Docker daemon socket /var/run/docker.sock."
      exit 1
    fi
  fi
fi

# Wrapper execution functions
run_runtime() {
  case "${EXEC_MODE}" in
    direct)
      ${RUNTIME} "$@"
      ;;
    sg)
      sg docker -c "${RUNTIME} $*"
      ;;
    sudo)
      sudo ${RUNTIME} "$@"
      ;;
  esac
}

# 5. Determine Networking Strategy & Compose File
# - macOS / Windows / WSL2 / Docker Desktop: VM requires pod mode (service:db namespace + published ports on db)
# - Linux with iptables: Pod mode provides full namespace isolation and published ports
# - Linux without iptables (hardened RHEL / daemon.json with iptables:false): Host mode bypasses kernel NAT
COMPOSE_FILE="docker-compose.yml"
NETWORK_STRATEGY="pod (service:db namespace)"

IS_WSL="false"
if [ -n "${WSL_DISTRO_NAME:-}" ] || { [ -r /proc/version ] && grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; }; then
  IS_WSL="true"
fi

IS_DOCKER_DESKTOP="false"
if [ "${RUNTIME}" = "docker" ] && run_runtime info 2>/dev/null | grep -qi "Operating System:.*Docker Desktop"; then
  IS_DOCKER_DESKTOP="true"
fi

if [ "${IS_MAC}" = "true" ]; then
  COMPOSE_FILE="docker-compose.yml"
  NETWORK_STRATEGY="pod (macOS Docker Desktop: published ports required for VM bridge)"
elif [ -n "${GARNET_NETWORK_MODE}" ]; then
  if [ "${GARNET_NETWORK_MODE}" = "host" ]; then
    COMPOSE_FILE="docker-compose.host.yml"
    NETWORK_STRATEGY="host (manual override via GARNET_NETWORK_MODE=host)"
  else
    COMPOSE_FILE="docker-compose.yml"
    NETWORK_STRATEGY="pod (manual override via GARNET_NETWORK_MODE=${GARNET_NETWORK_MODE})"
  fi
elif [ "${IS_DOCKER_DESKTOP}" = "true" ] || [ "${IS_WSL}" = "true" ]; then
  COMPOSE_FILE="docker-compose.yml"
  NETWORK_STRATEGY="pod (WSL2 / Docker Desktop: published ports required for host localhost)"
else
  HAS_IPTABLES="true"
  if ! command -v iptables &>/dev/null && ! command -v iptables-legacy &>/dev/null && ! command -v nft &>/dev/null; then
    HAS_IPTABLES="false"
  fi

  if [ -f /etc/docker/daemon.json ] && grep -qi '"iptables"[[:space:]]*:[[:space:]]*false' /etc/docker/daemon.json 2>/dev/null; then
    HAS_IPTABLES="false"
  fi

  if [ "${HAS_IPTABLES}" = "false" ]; then
    if [ -f "docker-compose.host.yml" ]; then
      COMPOSE_FILE="docker-compose.host.yml"
      NETWORK_STRATEGY="host (RHEL/Linux: iptables not available/disabled in dockerd; bypassing kernel NAT)"
    else
      echo "[!] Warning: iptables not available, but docker-compose.host.yml was not found. Using default compose."
    fi
  else
    COMPOSE_FILE="docker-compose.yml"
    NETWORK_STRATEGY="pod (Linux: iptables active; service:db namespace)"
  fi
fi

run_compose() {
  case "${EXEC_MODE}" in
    direct)
      ${COMPOSE_CMD} -f "${COMPOSE_FILE}" "$@"
      ;;
    sg)
      sg docker -c "${COMPOSE_CMD} -f \"${COMPOSE_FILE}\" $*"
      ;;
    sudo)
      sudo ${COMPOSE_CMD} -f "${COMPOSE_FILE}" "$@"
      ;;
  esac
}

echo "==> Container runtime: ${RUNTIME} (execution mode: ${EXEC_MODE})"
echo "==> Compose command:   ${COMPOSE_CMD} -f ${COMPOSE_FILE}"
echo "==> Network strategy:  ${NETWORK_STRATEGY}"

# 6. Reassemble multi-part container images if needed, then load
if [ ! -f "q-resil-images.tar" ] && [ ! -f "q-resil-images.tar.gz" ]; then
  if compgen -G "docker-images/q-resil-images.tar.gz.part_*" > /dev/null || compgen -G "q-resil-images.tar.gz.part_*" > /dev/null; then
    echo "==> Multi-part compressed container images detected. Reassembling into q-resil-images.tar.gz..."
    if compgen -G "docker-images/q-resil-images.tar.gz.part_*" > /dev/null; then
      cat docker-images/q-resil-images.tar.gz.part_* > q-resil-images.tar.gz
    else
      cat q-resil-images.tar.gz.part_* > q-resil-images.tar.gz
    fi
    echo "==> Container image archive successfully reassembled."
  elif compgen -G "docker-images/q-resil-images.tar.part_*" > /dev/null || compgen -G "q-resil-images.tar.part_*" > /dev/null; then
    echo "==> Multi-part container images detected. Reassembling into q-resil-images.tar..."
    if compgen -G "docker-images/q-resil-images.tar.part_*" > /dev/null; then
      cat docker-images/q-resil-images.tar.part_* > q-resil-images.tar
    else
      cat q-resil-images.tar.part_* > q-resil-images.tar
    fi
    echo "==> Container image archive successfully reassembled."
  fi
fi

if [ -f "q-resil-images.tar.gz" ]; then
  echo "==> Loading container images from q-resil-images.tar.gz (offline)..."
  run_runtime load -i q-resil-images.tar.gz
  echo "==> Container images loaded into local storage."
elif [ -f "q-resil-images.tar" ]; then
  echo "==> Loading container images from q-resil-images.tar (offline)..."
  run_runtime load -i q-resil-images.tar
  echo "==> Container images loaded into local storage."
fi

# 6. Check and resolve available ports automatically
is_port_in_use() {
  local port="$1"
  # 1. Try python3 / python socket bind test (most accurate: tests if 0.0.0.0:port can be bound)
  if command -v python3 &>/dev/null; then
    if ! python3 -c "import socket; s = socket.socket(); s.bind(('0.0.0.0', ${port})); s.close()" 2>/dev/null; then
      return 0
    else
      return 1
    fi
  elif command -v python &>/dev/null; then
    if ! python -c "import socket; s = socket.socket(); s.bind(('0.0.0.0', ${port})); s.close()" 2>/dev/null; then
      return 0
    else
      return 1
    fi
  fi

  # 2. Try lsof (standard on macOS and Linux)
  if command -v lsof &>/dev/null; then
    lsof -iTCP:"${port}" -sTCP:LISTEN -n -P &>/dev/null && return 0
  fi

  # 3. Try /dev/tcp (Bash built-in)
  if (echo > /dev/tcp/127.0.0.1/"${port}") 2>/dev/null; then
    return 0
  fi

  # 4. Try nc
  if command -v nc &>/dev/null; then
    nc -z 127.0.0.1 "${port}" &>/dev/null && return 0
  fi

  return 1
}

find_next_free_port() {
  local port="$1"
  local name="$2"
  local initial_port="$1"
  while is_port_in_use "${port}"; do
    echo "    [!] Port ${port} (${name}) is already in use. Trying next port $((port + 1))..." >&2
    port=$((port + 1))
  done
  if [ "${port}" -ne "${initial_port}" ]; then
    echo "    ==> Auto-assigned port ${port} for ${name} (default ${initial_port} was busy)." >&2
  fi
  echo "${port}"
}

# Stop any previously running garnet-offline-build stack to recycle ports cleanly
OTHER_COMPOSE="docker-compose.host.yml"
[ "${COMPOSE_FILE}" = "docker-compose.host.yml" ] && OTHER_COMPOSE="docker-compose.yml"

if run_compose ps -q 2>/dev/null | grep -q .; then
  echo "==> Existing Garnet Q-Resil containers detected. Stopping them to recycle ports..."
  run_compose down 2>/dev/null || true
  sleep 1
fi
if [ -f "${OTHER_COMPOSE}" ]; then
  case "${EXEC_MODE}" in
    direct) ${COMPOSE_CMD} -f "${OTHER_COMPOSE}" down 2>/dev/null || true ;;
    sg)     sg docker -c "${COMPOSE_CMD} -f \"${OTHER_COMPOSE}\" down" 2>/dev/null || true ;;
    sudo)   sudo ${COMPOSE_CMD} -f "${OTHER_COMPOSE}" down 2>/dev/null || true ;;
  esac
fi

echo "==> Checking port availability..."
GARNET_UI_PORT=$(find_next_free_port 8000 "Web UI")
GARNET_API_PORT=$(find_next_free_port 8081 "Backend API")
GARNET_DB_PORT=$(find_next_free_port 5432 "PostgreSQL Database")
GARNET_REMEDIATION_PORT=$(find_next_free_port 9400 "Remediation Engine")

export GARNET_UI_PORT
export GARNET_API_PORT
export GARNET_DB_PORT
export GARNET_REMEDIATION_PORT

# 7. Start the stack
echo "==> Bringing up Garnet Q-Resil containers..."
run_compose up -d

# Self-heal database credentials and initialize remediation DB
DB_CONTAINER="$(run_compose ps -q db 2>/dev/null | head -n 1)"
[ -z "${DB_CONTAINER}" ] && DB_CONTAINER="garnet-offline-build-db-1"

# Wait up to 15 seconds for PostgreSQL to be ready to accept commands
DB_ATTEMPTS=0
while [ $DB_ATTEMPTS -lt 15 ]; do
  if run_runtime exec "${DB_CONTAINER}" pg_isready -h 127.0.0.1 -p "${GARNET_DB_PORT:-5432}" -U cbomkit -d postgres &>/dev/null; then
    run_runtime exec "${DB_CONTAINER}" psql -h 127.0.0.1 -p "${GARNET_DB_PORT:-5432}" -U cbomkit -d postgres -c "ALTER USER cbomkit WITH PASSWORD 'cbomkit_secure_poc_pass';" &>/dev/null || true
    run_runtime exec "${DB_CONTAINER}" psql -h 127.0.0.1 -p "${GARNET_DB_PORT:-5432}" -U cbomkit -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = 'remediation'" 2>/dev/null | grep -q 1 || \
    run_runtime exec "${DB_CONTAINER}" psql -h 127.0.0.1 -p "${GARNET_DB_PORT:-5432}" -U cbomkit -d postgres -c "CREATE DATABASE remediation OWNER cbomkit;" &>/dev/null || true
    run_compose restart remediation &>/dev/null || true
    break
  fi
  sleep 1
  DB_ATTEMPTS=$((DB_ATTEMPTS + 1))
done

echo ""
echo "=========================================================="
echo "  [SUCCESS] Garnet Q-Resil is LIVE (100% Offline)         "
echo "=========================================================="
echo ""
echo "  Web UI:             http://localhost:${GARNET_UI_PORT} (or http://<SERVER_IP>:${GARNET_UI_PORT})"
echo "  Backend API:        http://localhost:${GARNET_API_PORT}/api"
echo "  Remediation Engine: http://localhost:${GARNET_REMEDIATION_PORT}/q/health"
echo "  Database:           127.0.0.1:${GARNET_DB_PORT}"
echo ""
if [ "${EXEC_MODE}" = "direct" ]; then
  echo "  Logs:      ${COMPOSE_CMD} logs -f"
  echo "  Stop:      ./stop.sh"
elif [ "${EXEC_MODE}" = "sg" ]; then
  echo "  Logs:      sg docker -c \"${COMPOSE_CMD} logs -f\""
  echo "  Stop:      ./stop.sh"
  echo "  Note:      Docker group added to '${CURRENT_USER}'. After your next SSH login,"
  echo "             you can run standard 'docker' commands directly without 'sg' or 'sudo'."
else
  echo "  Logs:      sudo ${COMPOSE_CMD} logs -f"
  echo "  Stop:      ./stop.sh"
  echo "  Note:      Docker group added to '${CURRENT_USER}'. After your next SSH login,"
  echo "             you can run standard 'docker' commands directly without 'sudo'."
fi
echo "=========================================================="
