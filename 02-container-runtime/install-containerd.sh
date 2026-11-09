#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
# Generate a complete config for the installed containerd version.
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i -E 's/^([[:space:]]*SystemdCgroup[[:space:]]*=[[:space:]]*)false/\1true/' /etc/containerd/config.toml
# Avoid accidentally disabling the CRI plugin.
if grep -Eq '^[[:space:]]*disabled_plugins[[:space:]]*=.*"cri"' /etc/containerd/config.toml; then
  echo 'ERROR: CRI plugin disabled in containerd config' >&2; exit 1
fi
sudo systemctl enable --now containerd
sudo systemctl restart containerd
sudo systemctl is-active --quiet containerd
sudo test -S /run/containerd/containerd.sock
sudo grep -Eq '^[[:space:]]*SystemdCgroup[[:space:]]*=[[:space:]]*true' /etc/containerd/config.toml
containerd --version
echo 'PASS: containerd running with systemd cgroups and socket available'
# Socket existence is not a complete CRI health check. kubeadm preflight will test CRI.
