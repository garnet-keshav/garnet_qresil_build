#!/usr/bin/env bash
# ==============================================================================
# Garnet Q-Resil — Offline Docker Installer for Linux (RHEL & Debian)
# 100% Offline — Air-gapped enterprise ready
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=========================================================="
echo "    Linux Offline Docker & Compose Setup                  "
echo "=========================================================="

# 1. If Docker and Docker Compose are ALREADY installed and healthy, exit immediately
if command -v docker &>/dev/null && (docker compose version &>/dev/null || docker-compose version &>/dev/null); then
  if docker info &>/dev/null; then
    echo "==> Docker and Docker Compose are ALREADY installed and healthy on this system:"
    docker --version
    docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
    echo "==> Docker is verified and ready. Skipping installation."
    exit 0
  fi
fi

# 2. Require root or sudo privileges
if [ "$EUID" -ne 0 ]; then
  echo "[!] Linux installation requires root privileges to configure systemd services."
  echo "    Re-running with sudo..."
  exec sudo bash "$0" "$@"
fi

# 3. Detect Linux Distribution Family
OS_NAME="Linux"
OS_VERSION="Unknown"
OS_FAMILY="unknown"

if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_NAME="${NAME:-Linux}"
  OS_VERSION="${VERSION_ID:-}"

  case "${ID:-}" in
    rhel|centos|rocky|almalinux|fedora|ol)
      OS_FAMILY="rhel"
      ;;
    ubuntu|debian|linuxmint|pop)
      OS_FAMILY="debian"
      ;;
    *)
      if [[ "${ID_LIKE:-}" =~ (rhel|fedora|centos) ]]; then
        OS_FAMILY="rhel"
      elif [[ "${ID_LIKE:-}" =~ (debian|ubuntu) ]]; then
        OS_FAMILY="debian"
      fi
      ;;
  esac
fi

echo "==> Detected Linux Distribution: ${OS_NAME} ${OS_VERSION} (Family: ${OS_FAMILY})"

# Check if Docker is installed but daemon is stopped
if command -v docker &>/dev/null && (docker compose version &>/dev/null || docker-compose version &>/dev/null); then
  echo "==> Docker binaries exist. Checking daemon service..."
  
  # Ensure docker group exists and user is added
  if ! getent group docker >/dev/null; then
    echo "==> Creating docker group..."
    groupadd -f docker
  fi
  TARGET_USER="${SUDO_USER:-$USER}"
  if [ -n "${TARGET_USER}" ] && [ "${TARGET_USER}" != "root" ]; then
    echo "==> Ensuring user '${TARGET_USER}' is in the 'docker' group..."
    usermod -aG docker "${TARGET_USER}" || true
  fi

  # Start service
  systemctl reset-failed docker.service 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true

  if [ -S /var/run/docker.sock ]; then
    chown root:docker /var/run/docker.sock 2>/dev/null || true
    chmod 660 /var/run/docker.sock 2>/dev/null || true
  fi

  if docker info &>/dev/null; then
    echo "==> Docker daemon started and verified successfully."
    exit 0
  fi
fi

echo "==> Installing Docker binaries offline from local linux/ bundle..."

# 4. Check for archive files in linux/ directory
DOCKER_TGZ="$(ls "${SCRIPT_DIR}"/docker-*.tgz 2>/dev/null | head -n 1)"
COMPOSE_BIN="${SCRIPT_DIR}/docker-compose"

if [ -z "${DOCKER_TGZ}" ] || [ ! -f "${DOCKER_TGZ}" ]; then
  echo "[ERROR] Docker tarball (docker-*.tgz) not found in ${SCRIPT_DIR}"
  exit 1
fi

if [ ! -f "${COMPOSE_BIN}" ]; then
  echo "[ERROR] docker-compose binary not found in ${SCRIPT_DIR}"
  exit 1
fi

# 5. Extract and install Docker binaries
TMP_EXTRACT=$(mktemp -d)
echo "==> Extracting $(basename "${DOCKER_TGZ}")..."
tar -xzf "${DOCKER_TGZ}" -C "${TMP_EXTRACT}"

echo "==> Copying binaries to /usr/bin/..."
cp -p "${TMP_EXTRACT}"/docker/* /usr/bin/
rm -rf "${TMP_EXTRACT}"

# Restore SELinux contexts on RHEL/CentOS
if command -v restorecon &>/dev/null; then
  echo "==> Restoring SELinux security contexts on installed binaries..."
  restorecon -Rv /usr/bin/docker* /usr/bin/containerd* /usr/bin/runc* /usr/bin/ctr* 2>/dev/null || true
fi

# 6. Install Docker Compose v2 (both as CLI plugin and standalone binary)
echo "==> Installing Docker Compose v2..."
chmod +x "${COMPOSE_BIN}"
cp -p "${COMPOSE_BIN}" /usr/bin/docker-compose
mkdir -p /usr/local/lib/docker/cli-plugins /usr/lib/docker/cli-plugins
cp -p "${COMPOSE_BIN}" /usr/local/lib/docker/cli-plugins/docker-compose
cp -p "${COMPOSE_BIN}" /usr/lib/docker/cli-plugins/docker-compose

# 7. Create systemd containerd service
cat << 'EOF' > /etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/bin/containerd
Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF

# 8. Create systemd docker service
cat << 'EOF' > /etc/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service containerd.service
Wants=network-online.target
Requires=containerd.service

[Service]
Type=notify
ExecStart=/usr/bin/dockerd -H unix:///var/run/docker.sock --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

# 9. Create docker group and /var/run/docker.sock setup
if ! getent group docker >/dev/null; then
  echo "==> Creating docker group..."
  groupadd -f docker
fi

TARGET_USER="${SUDO_USER:-$USER}"
if [ -n "${TARGET_USER}" ] && [ "${TARGET_USER}" != "root" ]; then
  usermod -aG docker "${TARGET_USER}" || true
  echo "==> Added ${TARGET_USER} to docker group."
fi

# 10. Configure iptables and daemon.json
ENABLE_IPTABLES="true"
if ! command -v iptables &>/dev/null; then
  echo "==> 'iptables' not found in PATH. Configuring Docker with 'iptables: false'..."
  ENABLE_IPTABLES="false"
else
  echo "==> 'iptables' detected in PATH. Docker will manage iptables."
fi

if [ "${OS_FAMILY}" = "rhel" ]; then
  echo "==> Applying RHEL/CentOS-specific configurations..."
  if systemctl is-active --quiet firewalld 2>/dev/null; then
    echo "    Configuring firewalld for Docker bridge..."
    firewall-cmd --zone=trusted --add-interface=docker0 --permanent 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
  fi
fi

mkdir -p /etc/docker
cat << EOF > /etc/docker/daemon.json
{
  "iptables": ${ENABLE_IPTABLES},
  "group": "docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF

# 11. Start and enable services
echo "==> Starting containerd and docker services..."
systemctl reset-failed docker.service 2>/dev/null || true
systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd
sleep 1
systemctl enable docker
systemctl restart docker

# Wait up to 10 seconds for Docker daemon socket to appear
SOCK_ATTEMPTS=0
while [ ! -S /var/run/docker.sock ] && [ $SOCK_ATTEMPTS -lt 10 ]; do
  sleep 1
  SOCK_ATTEMPTS=$((SOCK_ATTEMPTS + 1))
done

if [ -S /var/run/docker.sock ]; then
  chown root:docker /var/run/docker.sock 2>/dev/null || true
  chmod 660 /var/run/docker.sock 2>/dev/null || true
fi

# 12. Verification
sleep 2
if docker info &>/dev/null; then
  echo ""
  echo "=========================================================="
  echo " [SUCCESS] Docker & Docker Compose installed offline!     "
  echo "=========================================================="
  docker --version
  docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
  echo "=========================================================="
else
  echo "[!] Docker daemon started but docker info returned non-zero. Status:"
  systemctl status docker --no-pager || true
fi

