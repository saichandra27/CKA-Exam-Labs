
#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# CKA LAB 03 - Initialize Kubernetes Node
#
# Usage:
#   bash 03-Initialize-Kubernetes.sh control-plane [options]
#
#   bash 03-Initialize-Kubernetes.sh worker \
#     --join-command 'kubeadm join ...'
#
# Options:
#   --control-plane-host HOST
#   --control-plane-ip IP
#   --pod-cidr CIDR
#   --service-cidr CIDR
#   --cri-socket SOCKET
#   --kubernetes-version VERSION
#   --join-command COMMAND
# ============================================================

ROLE="${1:-}"
[[ $# -gt 0 ]] && shift

CONTROL_PLANE_HOST="node01"
CONTROL_PLANE_IP=""
POD_CIDR="10.200.0.0/16"
SERVICE_CIDR="10.96.0.0/12"
CRI_SOCKET="unix:///run/containerd/containerd.sock"
KUBERNETES_VERSION="v1.35.10"
JOIN_COMMAND=""

usage() {
    cat <<EOF
Usage:
  $0 control-plane [options]
  $0 worker --join-command 'kubeadm join ...'

Options:
  --control-plane-host HOST
  --control-plane-ip IP
  --pod-cidr CIDR
  --service-cidr CIDR
  --cri-socket SOCKET
  --kubernetes-version VERSION
  --join-command COMMAND
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# ------------------------------------------------------------
# STEP 1 - Parse command-line parameters
# ------------------------------------------------------------

[[ "$ROLE" == "control-plane" || "$ROLE" == "worker" ]] || {
    usage
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --control-plane-host)
            [[ $# -ge 2 ]] || die "Missing host value"
            CONTROL_PLANE_HOST="$2"
            shift 2
            ;;
        --control-plane-ip)
            [[ $# -ge 2 ]] || die "Missing IP value"
            CONTROL_PLANE_IP="$2"
            shift 2
            ;;
        --pod-cidr)
            [[ $# -ge 2 ]] || die "Missing Pod CIDR"
            POD_CIDR="$2"
            shift 2
            ;;
        --service-cidr)
            [[ $# -ge 2 ]] || die "Missing Service CIDR"
            SERVICE_CIDR="$2"
            shift 2
            ;;
        --cri-socket)
            [[ $# -ge 2 ]] || die "Missing CRI socket"
            CRI_SOCKET="$2"
            shift 2
            ;;
        --kubernetes-version)
            [[ $# -ge 2 ]] || die "Missing Kubernetes version"
            KUBERNETES_VERSION="$2"
            shift 2
            ;;
        --join-command)
            [[ $# -ge 2 ]] || die "Missing join command"
            JOIN_COMMAND="$2"
            shift 2
            ;;
        *)
            die "Unknown parameter: $1"
            ;;
    esac
done

NODE_HOSTNAME="$(hostname)"

# ------------------------------------------------------------
# STEP 2 - Detect control-plane IP
# ------------------------------------------------------------

if [[ "$ROLE" == "control-plane" && -z "$CONTROL_PLANE_IP" ]]; then
    CONTROL_PLANE_IP="$(
        ip -4 -o addr show dev eth0 |
        awk '{split($4, a, "/"); print a[1]; exit}'
    )"
fi

if [[ "$ROLE" == "control-plane" ]]; then
    [[ -n "$CONTROL_PLANE_IP" ]] ||
        die "Unable to detect control-plane IP. Use --control-plane-ip."
fi

# ------------------------------------------------------------
# STEP 3 - Validate prerequisites
# ------------------------------------------------------------

echo "============================================"
echo "Kubernetes Node Initialization"
echo "============================================"
echo "Hostname:           $NODE_HOSTNAME"
echo "Role:               $ROLE"
echo "Control-plane host: $CONTROL_PLANE_HOST"
echo "Control-plane IP:   ${CONTROL_PLANE_IP:-N/A}"
echo "Pod CIDR:           $POD_CIDR"
echo "Service CIDR:       $SERVICE_CIDR"
echo "CRI socket:         $CRI_SOCKET"
echo "Kubernetes version: $KUBERNETES_VERSION"
echo "============================================"

echo "[1/5] Validating prerequisites..."

for cmd in kubeadm kubelet kubectl; do
    command -v "$cmd" >/dev/null 2>&1 ||
        die "$cmd is not installed"
done

command -v sudo >/dev/null 2>&1 ||
    die "sudo is not installed"

sudo -v

sudo systemctl is-active --quiet containerd ||
    die "containerd is not running"

SOCKET_PATH="${CRI_SOCKET#unix://}"

[[ "$CRI_SOCKET" == unix://* ]] ||
    die "Expected a unix:// CRI socket"

sudo test -S "$SOCKET_PATH" ||
    die "CRI socket does not exist: $SOCKET_PATH"

echo "PASS: Prerequisites validated."

# ------------------------------------------------------------
# STEP 4 - Initialize control plane
# ------------------------------------------------------------

if [[ "$ROLE" == "control-plane" ]]; then

    [[ "$NODE_HOSTNAME" == "$CONTROL_PLANE_HOST" ]] ||
        die "Control-plane role must run on $CONTROL_PLANE_HOST"

    echo "[2/5] Checking control-plane state..."

    API_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
    ADMIN_CONF="/etc/kubernetes/admin.conf"

    if sudo test -f "$API_MANIFEST"; then
        echo "Existing control-plane manifest detected."
        echo "Skipping kubeadm init."
    else
        # Detect incomplete initialization before retrying.
        if sudo test -e "$ADMIN_CONF" ||
           sudo test -e /etc/kubernetes/pki/ca.crt ||
           sudo test -e /var/lib/etcd/member; then
            die "Partial kubeadm state detected. Diagnose before retrying."
        fi

        echo "Initializing Kubernetes control plane..."

        sudo kubeadm init \
            --apiserver-advertise-address="$CONTROL_PLANE_IP" \
            --pod-network-cidr="$POD_CIDR" \
            --service-cidr="$SERVICE_CIDR" \
            --cri-socket="$CRI_SOCKET" \
            --kubernetes-version="$KUBERNETES_VERSION"

        echo "PASS: kubeadm init completed."
    fi

    # --------------------------------------------------------
    # STEP 5 - Configure kubectl
    # --------------------------------------------------------

    echo "[3/5] Configuring kubectl..."

    sudo test -f "$ADMIN_CONF" ||
        die "$ADMIN_CONF is missing. Initialization is incomplete."

    mkdir -p "$HOME/.kube"

    sudo cp "$ADMIN_CONF" "$HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
    chmod 600 "$HOME/.kube/config"

    echo "PASS: kubectl configured."

    # --------------------------------------------------------
    # STEP 6 - Verify control plane
    # --------------------------------------------------------

    echo "[4/5] Verifying Kubernetes API..."

    kubectl --request-timeout=10s get --raw=/readyz ||
        die "Kubernetes API is not ready. Check kubelet and static Pod logs."

    kubectl cluster-info
    kubectl get nodes -o wide
    kubectl get pods -n kube-system -o wide

    # --------------------------------------------------------
    # STEP 7 - Generate worker join command
    # --------------------------------------------------------

    echo "[5/5] Generating worker join command..."

    echo
    echo "Generate a worker join command on node01:"
    echo
    echo "  sudo kubeadm token create --print-join-command"
    echo
    echo "Then run the worker script with --join-command."
    echo
    echo "Control-plane initialization completed."
fi

# ------------------------------------------------------------
# STEP 8 - Join worker node
# ------------------------------------------------------------

if [[ "$ROLE" == "worker" ]]; then

    [[ "$NODE_HOSTNAME" != "$CONTROL_PLANE_HOST" ]] ||
        die "Cannot join control plane as a worker"

    echo "[2/5] Checking worker status..."

    if sudo test -f /etc/kubernetes/kubelet.conf; then
        echo "Existing kubelet configuration detected."
        echo "Skipping kubeadm join."
        exit 0
    fi

    [[ -n "$JOIN_COMMAND" ]] ||
        die "Missing --join-command"

    # Split a simple kubeadm join command into arguments.
    # No eval or shell execution.
    read -r -a JOIN_ARGS <<< "$JOIN_COMMAND"

    [[ ${#JOIN_ARGS[@]} -ge 3 ]] ||
        die "Invalid join command"

    [[ "${JOIN_ARGS[0]}" == "kubeadm" &&
       "${JOIN_ARGS[1]}" == "join" ]] ||
        die "Expected a kubeadm join command"

    for arg in "${JOIN_ARGS[@]}"; do
        if [[ "$arg" == --cri-socket* ]]; then
            die "Join command already contains --cri-socket. Remove it."
        fi
    done

    echo "[3/5] Joining worker node..."

    sudo "${JOIN_ARGS[@]}" \
        --cri-socket="$CRI_SOCKET"

    echo "[4/5] Worker joined successfully."

    echo "[5/5] Checking kubelet..."

    sudo systemctl is-active --quiet kubelet ||
        die "kubelet is not running"

    echo "PASS: kubelet active."
fi

echo "============================================"
echo "SUCCESS: Initialization script completed"
echo "============================================"