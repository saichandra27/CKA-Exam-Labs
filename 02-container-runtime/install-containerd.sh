
#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y containerd

sudo mkdir -p /etc/containerd

containerd config default |  sudo tee /etc/containerd/config.toml > /dev/null

sudo sed -i \
  's/SystemdCgroup = false/SystemdCgroup = true/' \
  /etc/containerd/config.toml

sudo systemctl enable --now containerd
sudo systemctl restart containerd

echo "=== $(hostname) ==="
containerd --version
sudo systemctl is-active containerd
sudo grep 'SystemdCgroup = true' /etc/containerd/config.toml
sudo ctr plugins ls | grep cri
