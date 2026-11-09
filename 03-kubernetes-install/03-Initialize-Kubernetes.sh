
#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# CKA LAB 03 - Initialize Kubernetes Node
#
# node01 = Control Plane
# node02 = Worker
# node03 = Worker
#
# Kubernetes: v1.35
# Container runtime: containerd
# Pod CIDR: 10.200.0.0/16
# Service CIDR: 10.96.0.0/12
#
# Usage:
#   bash Initialize-Node.sh control-plane
#   bash Initialize-Node.sh worker '<join-command>'
# ============================================================

CONTROL_PLANE_HOST="node01"
CONTROL_PLANE_IP="10.244.149.212"
POD_CIDR="10.200.0.0/16"
SERVICE_CIDR="10.96.0.0/12"
CRI_SOCKET="unix:///run/containerd/containerd.sock"

ROLE="${1:-}"
HOSTNAME="$(hostname)"

echo "============================================"
echo "Kubernetes Node Initialization"
echo "Hostname: $HOSTNAME"
echo "Role: ${ROLE:-not specified}"
echo "============================================"

# ------------------------------------------------------------
# STEP 1 - Validate role
# ------------------------------------------------------------

if [[ "$ROLE" != "control-plane" && "$ROLE" != "worker" ]]; then
    echo "ERROR: Invalid role."
    echo "Usage:"
    echo "  bash Initialize-Node.sh control-plane"
    echo "  bash Initialize-Node.sh worker '<join-command>'"
    exit 1
fi

# ------------------------------------------------------------
# STEP 2 - Validate prerequisites
# ------------------------------------------------------------

echo "[1/5] Validating prerequisites..."

for cmd in kubeadm kubelet kubectl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: $cmd is not installed." >&2
        exit 1
    fi
done

sudo systemctl is-active --quiet containerd || {
    echo "ERROR: containerd is not running." >&2
    exit 1
}

echo "PASS: Kubernetes binaries and containerd available."

# ------------------------------------------------------------
# STEP 3 - Initialize control plane
# ------------------------------------------------------------

if [[ "$ROLE" == "control-plane" ]]; then

    if [[ "$HOSTNAME" != "$CONTROL_PLANE_HOST" ]]; then
        echo "ERROR: Control plane must run on $CONTROL_PLANE_HOST."
        exit 1
    fi

    echo "[2/5] Checking control-plane initialization..."

    if [[ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]]; then
        echo "Control plane already initialized. Skipping kubeadm init."
    else
        echo "Initializing Kubernetes control plane..."

        sudo kubeadm init \
            --apiserver-advertise-address="$CONTROL_PLANE_IP" \
            --pod-network-cidr="$POD_CIDR" \
            --service-cidr="$SERVICE_CIDR" \
            --cri-socket="$CRI_SOCKET"

        echo "PASS: Control plane initialized."
    fi

    # --------------------------------------------------------
    # STEP 4 - Configure kubectl
    # --------------------------------------------------------

    echo "[3/5] Configuring kubectl..."

    mkdir -p "$HOME/.kube"

    sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"

    sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

    chmod 600 "$HOME/.kube/config"

    echo "PASS: kubectl configured."

    # --------------------------------------------------------
    # STEP 5 - Verify cluster
    # --------------------------------------------------------

    echo "[4/5] Verifying control plane..."

    kubectl cluster-info
    kubectl get nodes -o wide
    kubectl get pods -n kube-system -o wide

    echo "[5/5] Generating worker join command..."

    echo ""
    echo "Run the following on node02 and node03:"
    echo ""

    sudo kubeadm token create \
        --print-join-command

    echo ""
    echo "IMPORTANT: Add this runtime flag to the join command:"
    echo "  --cri-socket=$CRI_SOCKET"

    echo ""
    echo "Control-plane setup completed."
fi

# ------------------------------------------------------------
# STEP 6 - Join worker nodes
# ------------------------------------------------------------

if [[ "$ROLE" == "worker" ]]; then

    if [[ "$HOSTNAME" == "$CONTROL_PLANE_HOST" ]]; then
        echo "ERROR: Do not join the control plane as a worker."
        exit 1
    fi

    echo "[2/5] Checking worker status..."

    if [[ -f /etc/kubernetes/kubelet.conf ]]; then
        echo "Worker appears already joined. Skipping kubeadm join."
        exit 0
    fi

    JOIN_COMMAND="${2:-}"

    if [[ -z "$JOIN_COMMAND" ]]; then
        echo "ERROR: Missing kubeadm join command."
        echo "Generate it on node01:"
        echo "  sudo kubeadm token create --print-join-command"
        exit 1
    fi

    # Validate expected kubeadm join command structure
    if [[ "$JOIN_COMMAND" != kubeadm\ join\ * ]]; then
        echo "ERROR: Expected a kubeadm join command."
        exit 1
    fi

    echo "[3/5] Joining worker node..."

    # Parse arguments without eval or shell execution.
    read -r -a JOIN_ARGS <<< "$JOIN_COMMAND"

    sudo "${JOIN_ARGS[@]}" \
        --cri-socket="$CRI_SOCKET"

    echo "[4/5] Worker joined."

    echo "[5/5] Checking kubelet..."

    sudo systemctl status kubelet --no-pager || true

    echo "Worker initialization completed."
fi

echo "============================================"
echo "SUCCESS: Initialization script completed"
echo "============================================"
