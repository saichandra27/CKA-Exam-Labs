#!/usr/bin/env bash
set -euo pipefail
sudo swapoff -a
# Comment active swap entries in fstab, preserving a backup.
sudo cp -n /etc/fstab /etc/fstab.cka-backup
sudo sed -i -E '/^[[:space:]]*[^#[:space:]].*[[:space:]]swap[[:space:]]/ s/^/# CKA disabled: /' /etc/fstab
printf '%s\n' overlay br_netfilter | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
for module in overlay br_netfilter; do
  if ! test -d "/sys/module/$module"; then sudo modprobe "$module"; fi
  test -d "/sys/module/$module" || { echo "ERROR: $module unavailable" >&2; exit 1; }
done
cat <<'SYSCTL' | sudo tee /etc/sysctl.d/99-kubernetes.conf >/dev/null
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
SYSCTL
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
[[ -z "$(swapon --noheadings --show=NAME)" ]]
[[ "$(sysctl -n net.ipv4.ip_forward)" == 1 ]]
[[ "$(sysctl -n net.bridge.bridge-nf-call-iptables)" == 1 ]]
sudo systemctl is-active --quiet containerd
printf 'PASS: %s prepared\n' "$(hostname)"
