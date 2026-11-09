#!/usr/bin/env bash
set -euo pipefail
# Run on initialized control plane only, after kubectl works.
POD_CIDR="${1:-10.200.0.0/16}"
FLANNEL_VERSION="${FLANNEL_VERSION:-v0.27.4}"
[[ "$POD_CIDR" =~ ^[0-9.]+/[0-9]+$ ]] || { echo 'Invalid IPv4 CIDR' >&2; exit 1; }
command -v kubectl >/dev/null
kubectl get nodes >/dev/null
url="https://raw.githubusercontent.com/flannel-io/flannel/${FLANNEL_VERSION}/Documentation/kube-flannel.yml"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
curl -fsSL "$url" -o "$tmp"
# Replace the default Flannel network (not a Kubernetes API Service CIDR).
python3 - "$tmp" "$POD_CIDR" <<'PY'
import sys
p, cidr = sys.argv[1:]
s = open(p).read()
old='"Network": "10.244.0.0/16"'
if s.count(old) != 1:
    raise SystemExit('Expected default Flannel Network not found exactly once; review manifest manually')
s = s.replace(old, f'"Network": "{cidr}"')
open(p, 'w').write(s)
PY
kubectl apply -f "$tmp"
echo 'Flannel applied; verify: kubectl get pods -n kube-flannel -w; kubectl get nodes -w'
echo 'Note: /32 sandbox interfaces may require Flannel interface/backend customization.'
