
echo "=== TCP CONNECTIVITY ==="
for node in node01 node02; do
  echo "Testing $node port 22"
  timeout 3 bash -c "echo > /dev/tcp/$node/22" \
    && echo "TCP PASS" || echo "TCP FAIL"
done

echo "=== ROOT PING ==="
sudo ping -c 2 node01 || true

echo "=== IP FORWARDING ==="
sudo sysctl -w net.ipv4.ip_forward=1

echo "=== NETWORK ADMIN CAPABILITY ==="
sudo ip link add cka-test type dummy \
  && sudo ip link delete cka-test

echo "=== CGROUP PERMISSION ==="
sudo mkdir /sys/fs/cgroup/cka-test \
  && sudo rmdir /sys/fs/cgroup/cka-test
