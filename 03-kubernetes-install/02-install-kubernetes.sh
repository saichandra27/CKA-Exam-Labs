#!/usr/bin/env bash
set -euo pipefail
K8S_MINOR="${1:-v1.35}"
[[ "$K8S_MINOR" =~ ^v[0-9]+\.[0-9]+$ ]] || { echo 'Usage: script [v1.35]' >&2; exit 1; }
sudo apt-get update
sudo apt-get install -y ca-certificates curl gpg
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" -o /tmp/kubernetes-release.key
sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg /tmp/kubernetes-release.key
printf 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/%s/deb/ /\n' "$K8S_MINOR" | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
kubeadm version -o short
kubelet --version
kubectl version --client
sudo systemctl is-active --quiet containerd
printf 'PASS: Kubernetes packages installed on %s\n' "$(hostname)"
