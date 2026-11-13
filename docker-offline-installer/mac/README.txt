==============================================================================
Garnet Q-Resil — Offline Docker Installers for macOS (Darwin)
==============================================================================

This directory contains official, standalone offline DMG disk images for
deploying Docker Desktop on air-gapped macOS machines with ZERO internet access:

1. Directory Structure:
   - arm64/Docker.dmg : Official installer for Apple Silicon Macs (M1/M2/M3/M4)
   - intel/Docker.dmg : Official installer for Intel Macs (x86_64)

2. Installation:
   Run '../install-docker-offline.sh' or '../../start.sh'.
   The script detects your Mac's CPU architecture (arm64 vs x86_64), mounts
   the matching DMG, copies Docker.app into /Applications, registers privileged
   system helper components, and starts Docker Desktop automatically.
==============================================================================
