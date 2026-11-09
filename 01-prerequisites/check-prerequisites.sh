
#!/usr/bin/env bash
set -euo pipefail

for node in node01 node02 node03; do
  echo "========== $node =========="

  ssh "$node" '
    echo "--- Hostname ---"
    hostname

    echo "--- OS ---"
    grep PRETTY_NAME /etc/os-release

    echo "--- CPU ---"
    nproc

    echo "--- Memory ---"
    free -h

    echo "--- Disk ---"
    df -h /

    echo "--- IP Addresses ---"
    ip -br -4 addr

    echo "--- Swap ---"
    swapon --show

    echo "--- Container Runtime ---"
    command -v containerd || true

    echo "--- Kubernetes Binaries ---"
    command -v kubeadm || true
    command -v kubelet || true
    command -v kubectl || true
  '
done
