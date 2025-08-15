#!/bin/bash
# -----------------------------------------------------------------------------
# Minikube Setup Script — TERRAFORM-COMPATIBLE (Ubuntu 22.04)
# Safe for remote-exec: no SSH/network restarts, idempotent-ish, with retries.
# Usage:
#   sudo /tmp/setup-minikube-terraform.sh <cluster_name> <environment> <minikube_version> <k8s_version> <driver> <memory> <cpus>
# Example:
#   sudo /tmp/setup-minikube-terraform.sh demo dev v1.34.0 v1.30.0 docker 4096 2
# -----------------------------------------------------------------------------

echo "MINIKUBE_SETUP_VERSION=2025-08-15T14:05Z  (hardened, no ssh/netplan restarts)"

set -euxo pipefail

# --- Environment for non-interactive runs ---------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME=/root

LOG_FILE=/var/log/minikube-setup.log
# Mirror all output to the logfile
exec > >(tee -a "$LOG_FILE") 2>&1

log(){ echo "[$(date '+%F %T')] $*"; }

# On any error: show helpful logs, then exit with the original code
trap 'RC=$?; echo; echo "---- docker/minikube logs (on error) ----";
      (journalctl -u docker --no-pager -n 200 || true);
      (tail -n 200 ~/.minikube/logs/lastStart.txt 2>/dev/null || true);
      echo "-------------------------------------------";
      exit $RC' ERR

# --- Args & defaults -----------------------------------------------------------------------------
CLUSTER_NAME="${1:-minikube}"
ENVIRONMENT="${2:-dev}"
MINIKUBE_VERSION="${3:-v1.34.0}"
KUBERNETES_VERSION="${4:-v1.30.0}"
DRIVER="${5:-docker}"
MINIKUBE_MEMORY="${6:-4096}"
MINIKUBE_CPUS="${7:-2}"

# --- Helpers -------------------------------------------------------------------------------------
retry() { for i in {1..8}; do "$@" && return 0; sleep $((i*5)); done; return 1; }

# --- Base packages --------------------------------------------------------------------------------
log "Installing base packages (curl, gnupg, conntrack, socat, etc.)"
retry apt-get update -y
retry apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https conntrack socat

# --- Kernel prerequisites for Kubernetes ----------------------------------------------------------
log "Ensuring kernel modules br_netfilter and overlay"
modprobe br_netfilter || true
modprobe overlay || true
install -d -m 0755 /etc/modules-load.d
cat >/etc/modules-load.d/k8s.conf <<'EOF'
br_netfilter
overlay
EOF

log "Applying sysctl settings for Kubernetes"
install -d -m 0755 /etc/sysctl.d
cat >/etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system || true

# --- Docker (official repo) -----------------------------------------------------------------------
log "Installing Docker from official repository"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

UBU_CODENAME="$(. /etc/os-release && echo "$UBUNTU_CODENAME")"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBU_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

retry apt-get update -y
retry apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log "Configuring Docker to use systemd cgroup driver"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{
  "exec-opts": ["native.cgroupdriver=systemd"]
}
JSON

systemctl enable --now docker
# Restart once to pick up daemon.json without disrupting SSH
systemctl restart docker
# Quick readiness check
until systemctl is-active --quiet docker; do
  log "Waiting for Docker to be active..."
  sleep 2
done
log "Docker is active"

# --- kubectl --------------------------------------------------------------------------------------
log "Installing kubectl ${KUBERNETES_VERSION}"
curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl
kubectl version --client=true --output=yaml || true

# --- Minikube -------------------------------------------------------------------------------------
log "Installing Minikube ${MINIKUBE_VERSION}"
curl -fsSL -o /usr/local/bin/minikube "https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-amd64"
chmod +x /usr/local/bin/minikube
minikube version || true

# --- Start Minikube -------------------------------------------------------------------------------
log "Starting Minikube (driver=${DRIVER}, mem=${MINIKUBE_MEMORY}, cpus=${MINIKUBE_CPUS}, k8s=${KUBERNETES_VERSION})"
minikube start \
  --driver="${DRIVER}" \
  --kubernetes-version="${KUBERNETES_VERSION}" \
  --memory="${MINIKUBE_MEMORY}" \
  --cpus="${MINIKUBE_CPUS}" \
  --container-runtime=docker \
  --wait=all

# --- Basic verification ---------------------------------------------------------------------------
log "Cluster info"
kubectl cluster-info
kubectl get nodes -o wide

# --- Success marker for Terraform -----------------------------------------------------------------
echo "SUCCESS: Minikube cluster is ready at $(date -Iseconds)" > /tmp/minikube-ready
chown ubuntu:ubuntu /tmp/minikube-ready || true

log "✅ Completed successfully for cluster=${CLUSTER_NAME}, env=${ENVIRONMENT}"
exit 0
