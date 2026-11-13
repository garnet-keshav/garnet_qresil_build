==============================================================================
Garnet Q-Resil — Offline Docker Installer for Windows
==============================================================================

This folder contains the official standalone unattended installer for
deploying Docker Desktop on air-gapped Windows environments with ZERO internet access:

1. Files:
   - 'Docker Desktop Installer.exe' : Official unattended Windows installer

2. Supported Versions:
   - Windows 10 Pro / Enterprise / Education (64-bit, build 19044+)
   - Windows 11 Pro / Enterprise / Education (64-bit)
   - Windows Server 2022 / 2025 (with WSL2 or Hyper-V)

3. Installation:
   Run 'start.bat' or 'start.ps1' from the bundle root, or run
   'install-docker-offline.bat' / 'install-docker-offline.ps1' directly.
   The script runs a silent unattended installation with:
   'Docker Desktop Installer.exe' install --quiet --accept-license
   It configures PATH, initializes Docker Desktop, and starts the container stack.
==============================================================================
