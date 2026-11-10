CRICTL_VERSION="v1.35.0"

ARCH=$(dpkg --print-architecture)

curl -fL --retry 3 \
  "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz" \
  -o /tmp/crictl.tar.gz

sudo tar -xzf /tmp/crictl.tar.gz -C /usr/local/bin

crictl --version

sudo tee /etc/crictl.yaml > /dev/null <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

sudo crictl info
sudo crictl images
sudo crictl ps -a