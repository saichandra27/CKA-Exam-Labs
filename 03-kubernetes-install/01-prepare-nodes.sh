
#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "Preparing $(hostname) for Kubernetes"
echo "=========================================="

# ------------------------------------------
# STEP 1: Disable swap if active
# ------------------------------------------
echo "[1/5] Checking swap..."

if swapon --noheadings --show=NAME 2>/dev/null | grep -q .; then
    echo "Active swap detected. Disabling..."
    sudo swapoff -a
else
    echo "No active swap detected."
fi

# ------------------------------------------
# STEP 2: Check and load kernel modules
# ------------------------------------------
echo "[2/5] Checking kernel modules..."

for module in overlay br_netfilter; do

    if [ -d "/sys/module/$module" ]; then
        echo "$module is already loaded."

    elif command -v modprobe >/dev/null 2>&1; then
        echo "Loading $module..."
        sudo modprobe "$module"

    else
        echo "ERROR: $module is unavailable and modprobe is missing." >&2
        exit 1
    fi

    # Verify module is available
    if [ ! -d "/sys/module/$module" ]; then
        echo "ERROR: $module could not be verified." >&2
        exit 1
    fi
done

# ------------------------------------------
# STEP 3: Persist kernel module configuration
# ------------------------------------------
echo "[3/5] Persisting kernel module configuration..."

printf '%s\n' overlay br_netfilter |
    sudo tee /etc/modules-load.d/k8s.conf > /dev/null

# ------------------------------------------
# STEP 4: Configure Kubernetes networking
# ------------------------------------------
echo "[4/5] Configuring networking..."

cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes.conf > /dev/null
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

# Apply settings directly.
# Avoid sysctl --system in restricted containerized labs.
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1

# ------------------------------------------
# STEP 5: Verify Kubernetes prerequisites
# ------------------------------------------
echo "[5/5] Verifying configuration..."

echo ""
echo "=== Hostname ==="
hostname

echo ""
echo "=== Swap ==="
if swapon --noheadings --show=NAME 2>/dev/null | grep -q .; then
    echo "ERROR: Swap is still active." >&2
    exit 1
else
    echo "PASS: No active swap."
fi

echo ""
echo "=== Kernel Modules ==="
for module in overlay br_netfilter; do
    test -d "/sys/module/$module"
    echo "PASS: $module"
done

echo ""
echo "=== IP Forwarding ==="
sudo sysctl net.ipv4.ip_forward
test "$(sysctl -n net.ipv4.ip_forward)" = "1"

echo ""
echo "=== Bridge Networking ==="
sudo sysctl net.bridge.bridge-nf-call-iptables
test "$(sysctl -n net.bridge.bridge-nf-call-iptables)" = "1"

echo ""
echo "=== Containerd Service ==="
sudo systemctl is-active --quiet containerd
echo "PASS: containerd is active."

echo ""
echo "=== Containerd Cgroup Driver ==="
sudo grep -Eq '^[[:space:]]*SystemdCgroup[[:space:]]*=[[:space:]]*true' \
    /etc/containerd/config.toml
echo "PASS: SystemdCgroup = true"

echo ""
echo "=========================================="
echo "SUCCESS: $(hostname) preparation completed"
echo "=========================================="
