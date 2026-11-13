# Garnet Q-Resil — Multi-Platform Offline Docker Installer

This directory contains standalone, 100% offline Docker packages and automation scripts for deploying on isolated environments with **zero inbound or outbound internet connectivity**.

---

## Clean Parent-Child Architecture

Only **ONE parent script** sits in this root directory (`install-docker-offline.sh`).
When executed, it detects the operating system and automatically launches the dedicated script inside the respective OS folder:

```text
docker-offline-installer/
├── install-docker-offline.sh       # MASTER PARENT SCRIPT (Auto-detects OS & runs child script)
├── install-docker-offline.bat      # Windows 1-click batch launcher
├── README.md                       # Architecture & usage guide
├── linux/                          # ── Linux Offline Folder ──
│   ├── install-linux.sh            # Dedicated Linux installer (systemd, selinux, iptables)
│   ├── docker-27.5.1.tgz           # Static binaries (dockerd, containerd, runc, ctr)
│   ├── docker-compose              # Standalone Compose v2 binary
│   └── README.txt
├── mac/                            # ── macOS Offline Folder ──
│   ├── install-mac.sh              # Dedicated macOS installer (architecture detection & mount)
│   ├── arm64/
│   │   └── Docker.dmg              # Official Apple Silicon (M1/M2/M3/M4) DMG (572 MB)
│   ├── intel/
│   │   └── Docker.dmg              # Official Intel (x86_64) DMG (628 MB)
│   └── README.txt
└── windows/                        # ── Windows Offline Folder ──
    ├── install-windows.ps1         # Dedicated Windows unattended PowerShell installer
    ├── Docker Desktop Installer.exe# Official Windows 10/11 & Server installer (623 MB)
    └── README.txt
```

---

## Operating System Detection Matrix

| OS | Detected Kernel | Child Script Triggered | Offline Files Used |
| :--- | :--- | :--- | :--- |
| **Linux (RHEL / Ubuntu)** | `Linux` | `linux/install-linux.sh` | `linux/docker-27.5.1.tgz`, `linux/docker-compose` |
| **macOS (Apple Silicon)** | `Darwin` (`arm64`) | `mac/install-mac.sh` | `mac/arm64/Docker.dmg` |
| **macOS (Intel)** | `Darwin` (`x86_64`) | `mac/install-mac.sh` | `mac/intel/Docker.dmg` |
| **Windows** | `MINGW*` / `MSYS*` / CMD | `windows/install-windows.ps1` | `windows/Docker Desktop Installer.exe` |
