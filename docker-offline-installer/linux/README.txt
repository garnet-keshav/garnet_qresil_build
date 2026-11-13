==============================================================================
Garnet Q-Resil — Offline Docker Binaries for Linux (RHEL & Debian)
==============================================================================

This folder contains pre-packaged, standalone static binaries for air-gapped
Linux systems with ZERO internet access:

1. Files:
   - docker-27.5.1.tgz : Official static binaries (dockerd, docker CLI, containerd, runc, ctr)
   - docker-compose    : Official standalone Docker Compose v2 executable

2. Supported Distributions:
   - RHEL 7, 8, 9, CentOS, Rocky Linux, AlmaLinux, Oracle Linux, Fedora
   - Ubuntu 18.04, 20.04, 22.04, 24.04 LTS, Debian 10, 11, 12

3. Installation:
   Run '../install-docker-offline.sh' or '../../start.sh'.
   The installer automatically extracts the binaries to /usr/bin/, creates
   and starts systemd services for containerd and docker, restores SELinux
   contexts, configures iptables/firewalld, and adds the current user to the
   docker group.
==============================================================================

