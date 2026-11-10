#!/usr/bin/env bash
set -euo pipefail
# Usage:
#   bash 03-Initialize-Kubernetes.sh control-plane [--control-plane-ip IP] [--pod-cidr CIDR] [--service-cidr CIDR]
#   bash 03-Initialize-Kubernetes.sh worker --join-command 'kubeadm join IP:6443 --token ... --discovery-token-ca-cert-hash ...'
die(){ echo "ERROR: $*" >&2; exit 1; }
ROLE="${1:-}"; [[ $# -gt 0 ]] && shift || true
[[ "$ROLE" == control-plane || "$ROLE" == worker ]] || die 'Role must be control-plane or worker'
CONTROL_PLANE_HOST="${CONTROL_PLANE_HOST:-node01}"
CONTROL_PLANE_IP="${CONTROL_PLANE_IP:-}"
POD_CIDR="${POD_CIDR:-10.200.0.0/16}"
SERVICE_CIDR="${SERVICE_CIDR:-10.144.0.0/12}"
CRI_SOCKET="${CRI_SOCKET:-unix:///run/containerd/containerd.sock}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-$(kubeadm version -o short 2>/dev/null || true)}"
JOIN_COMMAND=''
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || die "Missing value for $1"
  case "$1" in
    --control-plane-host) CONTROL_PLANE_HOST="$2";;
    --control-plane-ip) CONTROL_PLANE_IP="$2";;
    --pod-cidr) POD_CIDR="$2";;
    --service-cidr) SERVICE_CIDR="$2";;
    --cri-socket) CRI_SOCKET="$2";;
    --kubernetes-version) KUBERNETES_VERSION="$2";;
    --join-command) JOIN_COMMAND="$2";;
    *) die "Unknown option: $1";;
  esac
  shift 2
done
for cmd in kubeadm kubelet kubectl sudo; do command -v "$cmd" >/dev/null || die "$cmd not installed"; done
sudo -v
sudo systemctl is-active --quiet containerd || die 'containerd inactive'
[[ "$CRI_SOCKET" == unix:///* ]] || die 'Expected unix:///... CRI socket'
sudo test -S "${CRI_SOCKET#unix://}" || die 'CRI socket missing'
[[ -n "$KUBERNETES_VERSION" ]] || die 'Cannot detect Kubernetes version'
if [[ "$ROLE" == control-plane ]]; then
  [[ "$(hostname)" == "$CONTROL_PLANE_HOST" ]] || die "Expected host $CONTROL_PLANE_HOST"
  if [[ -z "$CONTROL_PLANE_IP" ]]; then
    CONTROL_PLANE_IP="$(ip -4 -o addr show dev eth0 | awk '{split($4,a,"/"); print a[1]; exit}')"
  fi
  [[ -n "$CONTROL_PLANE_IP" ]] || die 'Cannot detect IP; pass --control-plane-ip'
  ip -4 addr show | grep -Fq "inet ${CONTROL_PLANE_IP}/" || die 'Advertise IP not assigned locally'
  echo "Control plane: $CONTROL_PLANE_IP; Pod CIDR: $POD_CIDR; Service CIDR: $SERVICE_CIDR"
  if sudo test -f /etc/kubernetes/manifests/kube-apiserver.yaml; then
    echo 'Existing API server manifest: checking API instead of rerunning kubeadm init'
    sudo test -f /etc/kubernetes/admin.conf || die 'Partial initialization: admin.conf missing'
  else
    if sudo test -e /etc/kubernetes/admin.conf || sudo test -e /etc/kubernetes/pki/ca.crt || sudo test -e /var/lib/etcd/member; then
      die 'Partial initialization detected. Diagnose before resetting or retrying.'
    fi
    sudo kubeadm init \
      --apiserver-advertise-address="$CONTROL_PLANE_IP" \
      --pod-network-cidr="$POD_CIDR" \
      --service-cidr="$SERVICE_CIDR" \
      --cri-socket="$CRI_SOCKET" \
      --kubernetes-version="$KUBERNETES_VERSION"
  fi
  mkdir -p "$HOME/.kube"
  sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
  sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  chmod 600 "$HOME/.kube/config"
  # /livez works even before CNI; /readyz can be temporarily unready while bootstrapping.
  kubectl --request-timeout=15s get --raw=/livez >/dev/null || die 'API server not healthy; inspect static Pod logs'
  kubectl get nodes -o wide
  echo 'Control plane initialized. NotReady is expected until a CNI is installed.'
  echo 'On node01 generate worker join command: sudo kubeadm token create --print-join-command'
else
  [[ "$(hostname)" != "$CONTROL_PLANE_HOST" ]] || die 'Cannot join control plane as worker'
  if sudo test -f /etc/kubernetes/kubelet.conf; then
    echo 'Existing kubelet.conf found. Verify join on control plane; not joining twice.'
    exit 0
  fi
  [[ -n "$JOIN_COMMAND" ]] || die 'Supply --join-command from kubeadm token create'
  read -r -a args <<< "$JOIN_COMMAND"
  [[ ${#args[@]} -ge 6 && "${args[0]}" == kubeadm && "${args[1]}" == join ]] || die 'Invalid kubeadm join command'
  for a in "${args[@]}"; do
    [[ "$a" != --cri-socket* ]] || die 'Remove --cri-socket from join command; script adds it'
  done
  sudo "${args[@]}" --cri-socket="$CRI_SOCKET"
  sudo systemctl is-active --quiet kubelet || die 'kubelet inactive after join'
  echo 'Worker joined. Check status on node01 with kubectl get nodes.'
fi
