
#!/usr/bin/env bash
set -euo pipefail

echo "Preparing $(hostname) for Kubernetes"

# Disable swap
sudo swapoff -a

# Load kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

# Persist module configuration
printf '%s\n' overlay br_netfilter |
  sudo tee /etc/modules-load.d/k8s.conf > /dev/null

# Configure Kubernetes networking
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes.conf > /dev/null
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

# Apply kernel settings
sudo sysctl --system

# Verify
echo "=== Verification ==="
sudo sysctl net.ipv4.ip_forward
sudo sysctl net.bridge.bridge-nf-call-iptables
sudo systemctl is-active containerd
sudo grep 'SystemdCgroup = true' /etc/containerd/config.toml
