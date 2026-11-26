# Garnet Q-Resil — Air-Gapped Deployment Guide

This standalone package contains everything required to deploy **Garnet Q-Resil (`garnet-offline-build`)** on an isolated, air-gapped machine or server with **zero inbound or outbound internet access**.

---

## 1. Supported Operating Systems

- **Linux (RHEL-Family):** Red Hat Enterprise Linux (RHEL 7, 8, 9), CentOS, Rocky Linux, AlmaLinux, Fedora, Oracle Linux.
- **Linux (Debian-Family):** Ubuntu (18.04, 20.04, 22.04, 24.04 LTS), Debian (10, 11, 12).
- **macOS:** Apple Silicon (M1/M2/M3/M4 arm64) & Intel Macs (x86_64).
- **Windows:** Windows 10/11 Pro/Enterprise & Windows Server (WSL2 / Hyper-V).

---

## 2. What If Docker Is NOT Installed?

**You do NOT need to install Docker beforehand!**

The package includes **`docker-offline-installer/`**, featuring the unified multi-platform installer:
- **`install-docker-offline.sh`**: Auto-detects Linux distribution or macOS or Windows Git Bash and installs Docker offline with zero external network access.
- **`install-docker-offline.ps1` / `install-docker-offline.bat`**: Unattended silent installation for native Windows environments.

When you run `./start.sh` (or `start.bat` on Windows):
1. It automatically detects your operating system.
2. It checks if Docker or Podman is installed and running.
3. If **missing**, it installs and configures Docker engine, containerd, and Compose **100% locally with zero internet calls**.
4. If **already installed**, it seamlessly reuses the existing runtime.

---

## 3. Persistent Data & Upgrades

All bank on-premises data (scanned CBOMs, certificates, compliance findings, risk metrics) is stored in persistent named Docker volumes:
- `garnet-offline-build_pg-data` (PostgreSQL database storage)
- `garnet-offline-build_cbomkit-data` (CBOM repository cache)

**Upgrading or restarting the stack NEVER deletes your data.**
Non-destructive database schema migration (`quarkus.hibernate-orm.schema-management.strategy=update`) applies upgrades additively without dropping tables or altering existing data.

To backup or restore your database at any time:
- **Linux / macOS:** `./start.sh backup` (or `./scripts/backup.sh`) and `./start.sh restore <file>` (or `./scripts/restore.sh <file>`)
- **Windows:** `scripts\backup.bat` and `scripts\restore.bat <file>`

---

## 4. Package Contents

- **`start.sh` & `stop.sh`**: 1-click startup & shutdown scripts for Linux & macOS.
- **`start.bat` & `stop.bat`**: 1-click startup & shutdown launchers for Windows.
- **`docker-compose.yml`**: Compose manifest defining the project `garnet-offline-build`.
- **`docker-images/`**: Container images compressed with gzip and stored in <50MB multi-part chunks for Git/GitHub compatibility (auto-assembled into `q-resil-images.tar.gz` on startup).
- **`q-resil-images.tar.gz`**: 100% offline container images (UI, Backend, Remediation Engine, Postgres) — reassembled automatically by `start.sh` / `start.bat`.
- **`docker-offline-installer/`**:
  - `install-docker-offline.sh`: Single master parent installer (auto-detects OS and runs child script).
  - `install-docker-offline.bat`: Windows 1-click batch launcher.
  - `linux/`: Dedicated Linux folder (`install-linux.sh`, `docker-27.5.1.tgz`, `docker-compose`).
  - `mac/`: Dedicated macOS folder (`install-mac.sh`, `arm64/Docker.dmg`, `intel/Docker.dmg`).
  - `windows/`: Dedicated Windows folder (`install-windows.ps1`, `Docker Desktop Installer.exe`).
- **`scripts/`**: Internal utilities (`start.ps1`, `stop.ps1`, `backup.sh/bat/ps1`, `restore.sh/bat/ps1`).
- **`backups/`**: Directory storing compressed SQL database backups.
- **`example/`**: CycloneDX 1.6 CBOM test files (`keycloak-cbom.json`, `kafka-cbom.json`, `flick-cbom.json`).

---

## 5. Quickstart Deployment

### Linux & macOS:
```bash
tar -xvf garnet-qresil-rhel-poc.tar.gz
cd offline-bundle
./start.sh
```

### Windows:
Extract `garnet-qresil-rhel-poc.tar.gz` and double-click `start.bat` (or run `./start.ps1` in PowerShell as Administrator).

---

## 6. Accessing the Application

- **Garnet Q-Resil Web UI:** `http://localhost:8000/` (or `http://<SERVER_IP>:8000/`)
- **Backend API & Swagger:** `http://localhost:8081/api`
- **PostgreSQL Database:** `127.0.0.1:5432`

> [!TIP]
> **Automatic Port Conflict Resolution (Sequential Auto-Increment):**
> If any default port (8000, 8081, or 5432) is already occupied by existing services on your host machine, `start.sh` (and `start.bat` on Windows) automatically detects the collision and claims the next available sequential port (e.g., 8000 &rarr; 8001, 8081 &rarr; 8082, 5432 &rarr; 5433). Nginx reverse routing and Quarkus endpoints adapt dynamically with zero configuration changes required.

---

## 7. Common Operations

| Task | Linux / macOS | Windows |
| :--- | :--- | :--- |
| **Check service status** | `docker compose ps` | `docker compose ps` |
| **View live logs** | `docker compose logs -f` | `docker compose logs -f` |
| **Stop application** | `./stop.sh` | `stop.bat` |
| **Restart application** | `./start.sh` | `start.bat` |
| **Backup database** | `./start.sh backup` | `scripts\backup.bat` |
| **Restore database** | `./start.sh restore <file>` | `scripts\restore.bat <file>` |

---

## 8. Repackaging with Latest Code Changes

If you modify application code (Java backend or React frontend), you can rebuild and update the offline archive from the main repository root:

```bash
# Full Rebuild (Compiles Java + Builds Docker images + Repackages tar.gz)
./build-offline-bundle.sh

# Or using Make:
make repack-offline
```

### Understanding `--skip-build`

| Command | Compiles Java & Builds Images? | Exports Images & Creates Archive? | Typical Time | When to Use |
| :--- | :---: | :---: | :---: | :--- |
| **`./build-offline-bundle.sh`** | **YES** | **YES** | ~2–3 min | **Code changed** (backend `src/`, frontend `frontend/src/`) |
| **`./build-offline-bundle.sh --skip-build`** | ❌ *(Skipped)* | **YES** | ~15 sec | **No code changed** (only updated scripts, docs, or config) |

- **Without `--skip-build` (Default):** Runs `mvn clean package` and `docker build` so that all new code changes are baked into `q-resil-cbom:offline` and `q-resil-cbom-frontend:offline`.
- **With `--skip-build`:** Reuses existing local Docker images and skips compilation, instantly exporting `q-resil-images.tar` and repackaging `garnet-qresil-rhel-poc.tar.gz`.
