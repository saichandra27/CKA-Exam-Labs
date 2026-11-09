#Test kernel and container permissions
echo "=== IP FORWARDING ==="
sudo sysctl -w net.ipv4.ip_forward=1

echo "=== OVERLAY FILESYSTEM ==="
grep -w overlay /proc/filesystems

echo "=== KERNEL MODULE ==="
sudo modprobe br_netfilter 2>&1 || true

echo "=== CGROUP WRITE ACCESS ==="
sudo mkdir /sys/fs/cgroup/cka-test 2>&1 \
  && sudo rmdir /sys/fs/cgroup/cka-test

echo "=== NETWORK ADMINISTRATION ==="
sudo ip link add cka-test type dummy 2>&1 \
  && sudo ip link delete cka-test

echo "=== SYSTEMD STATUS ==="
systemctl is-system-running