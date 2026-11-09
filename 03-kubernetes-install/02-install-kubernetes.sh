
#!/usr/bin/env bash
set -euo pipefail

K8S_VERSION="v1.35"

echo "Installing Kubernetes $K8S_VERSION on $(hostname)"

# Install prerequisites
sudo apt-get update
sudo apt-get install -y ca-certificates curl gpg

# Configure repository signing key
sudo mkdir -p -m 755 /etc/apt/keyrings

curl -fsSL \
  "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" \
  -o /tmp/kubernetes-release.key

sudo gpg --dearmor --yes \
  -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
  /tmp/kubernetes-release.key

# Configure Kubernetes package repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" |
  sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

# Install Kubernetes packages
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# Prevent unintended package upgrades
sudo apt-mark hold kubelet kubeadm kubectl

# Enable kubelet
sudo systemctl enable kubelet

# Verify installed components
echo "=== Kubernetes versions ==="
kubeadm version -o short
kubelet --version
kubectl version --client

echo "=== Container runtime ==="
sudo systemctl is-active containerd

echo "SUCCESS: Kubernetes binaries installed on $(hostname)"