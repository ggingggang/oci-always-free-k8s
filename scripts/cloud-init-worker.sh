#!/bin/bash
set -euo pipefail

KUBERNETES_VERSION="${kubernetes_version}"

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
# 9. Root SSH setup (for master access)
# ──────────────────────────────────────────
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat <<'PUBKEY' >> /root/.ssh/authorized_keys
${master_ssh_pubkey}
PUBKEY
chmod 600 /root/.ssh/authorized_keys

sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl restart sshd
