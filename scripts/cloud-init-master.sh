#!/bin/bash
set -euo pipefail

KUBERNETES_VERSION="${kubernetes_version}"
POD_CIDR="${pod_cidr}"

# ──────────────────────────────────────────
# 1. System update
# ──────────────────────────────────────────
dnf update -y

# ──────────────────────────────────────────
# 2. Disable swap
# ──────────────────────────────────────────
swapoff -a
sed -i '/swap/d' /etc/fstab

# ──────────────────────────────────────────
# 3. Load kernel modules
# ──────────────────────────────────────────
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# ──────────────────────────────────────────
# 4. sysctl configuration
# ──────────────────────────────────────────
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# ──────────────────────────────────────────
# 5. SELinux permissive
# ──────────────────────────────────────────
setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# ──────────────────────────────────────────
# 6. Disable firewalld
# ──────────────────────────────────────────
systemctl disable --now firewalld || true

# ──────────────────────────────────────────
# 7. Install containerd
# ──────────────────────────────────────────
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y containerd.io

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable --now containerd

# ──────────────────────────────────────────
# 8. Install kubeadm / kubelet / kubectl
# ──────────────────────────────────────────
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/rpm/repodata/repomd.xml.key
EOF

dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

# ──────────────────────────────────────────
# 9. kubeadm init
# Single master — --upload-certs not needed
# ──────────────────────────────────────────
kubeadm init \
  --pod-network-cidr="$POD_CIDR" \
  --ignore-preflight-errors=NumCPU,Hostname \
  2>&1 | tee /var/log/kubeadm-init.log

# ──────────────────────────────────────────
# 10. kubeconfig setup (root)
# ──────────────────────────────────────────
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

# ──────────────────────────────────────────
# 11. Install CNI - Calico
# ──────────────────────────────────────────
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml \
  --kubeconfig /root/.kube/config

# ──────────────────────────────────────────
# 12. Install nmap
# ──────────────────────────────────────────
dnf install -y nmap

# ──────────────────────────────────────────
# 13. SSH key + environment setup
# ──────────────────────────────────────────
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat <<'SSHKEY' > /root/.ssh/id_ed25519
${ssh_private_key}
SSHKEY
chmod 600 /root/.ssh/id_ed25519

cat <<EOF > /etc/k8s-join.env
WORKER_SUBNET="${worker_subnet_cidr}"
EOF
chmod 600 /etc/k8s-join.env

# ──────────────────────────────────────────
# 14. Worker join script
# Scan worker subnet via nmap → SSH kubeadm join
# ──────────────────────────────────────────
cat <<'JOINSCRIPT' > /usr/local/bin/ssh-join-workers.sh
#!/bin/bash
set -uo pipefail

source /etc/k8s-join.env
LOG="/var/log/ssh-join-workers.log"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i /root/.ssh/id_ed25519"

# Scan worker subnet
WORKERS=$(nmap -n -sn "$WORKER_SUBNET" -oG - | awk '/Up$/{print $2}')
if [ -z "$WORKERS" ]; then
  echo "$(date): no hosts found on $WORKER_SUBNET" >> "$LOG"
  exit 0
fi

# Check for unjoined workers
NEED_JOIN=""
for ip in $WORKERS; do
  RESULT=$(ssh $SSH_OPTS root@"$ip" "[ -f /var/run/worker-joined ] && echo JOINED || echo PENDING" 2>/dev/null || echo "UNREACHABLE")
  if [ "$RESULT" = "PENDING" ]; then
    NEED_JOIN="$NEED_JOIN $ip"
  fi
done

NEED_JOIN=$(echo "$NEED_JOIN" | xargs)
if [ -z "$NEED_JOIN" ]; then
  echo "$(date): all workers already joined" >> "$LOG"
  exit 0
fi

# Create join token (only when unjoined workers exist)
JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null)
if [ -z "$JOIN_CMD" ]; then
  echo "$(date): failed to create join token" >> "$LOG"
  exit 1
fi

for ip in $NEED_JOIN; do
  echo "$(date): joining $ip..." >> "$LOG"
  ssh $SSH_OPTS root@"$ip" \
    "$JOIN_CMD --ignore-preflight-errors=Hostname 2>&1 && touch /var/run/worker-joined" >> "$LOG" 2>&1
  if [ $? -eq 0 ]; then
    echo "$(date): $ip joined successfully" >> "$LOG"
  else
    echo "$(date): $ip join failed, will retry" >> "$LOG"
  fi
done
JOINSCRIPT

chmod +x /usr/local/bin/ssh-join-workers.sh

# ──────────────────────────────────────────
# 15. systemd service + timer
# Retry worker join every 1 min (handles autoscaling)
# ──────────────────────────────────────────
cat <<EOF > /etc/systemd/system/ssh-join-workers.service
[Unit]
Description=Join workers to Kubernetes cluster via SSH

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ssh-join-workers.sh
EOF

cat <<EOF > /etc/systemd/system/ssh-join-workers.timer
[Unit]
Description=Retry joining workers via SSH

[Timer]
OnBootSec=30s
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now ssh-join-workers.timer

# Initial attempt (failure won't block cloud-init)
/usr/local/bin/ssh-join-workers.sh || true
