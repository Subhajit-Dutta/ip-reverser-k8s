#!/bin/bash
# -----------------------------------------------------------------------------
# Minikube Setup Script — TERRAFORM-COMPATIBLE (Ubuntu 22.04)
# Safe for remote-exec: no SSH/network restarts. Robust logging & retries.
# Usage:
#   sudo /tmp/setup-minikube-terraform.sh <cluster_name> <environment> <minikube_version> <k8s_version> <driver> <memoryMB> <cpus>
# Example:
#   sudo /tmp/setup-minikube-terraform.sh demo dev v1.34.0 v1.30.0 docker 3000 2
# -----------------------------------------------------------------------------

echo "MINIKUBE_SETUP_VERSION=2025-08-15T14:25Z (auto-cap resources)"

set -euxo pipefail

# --- Environment -----------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME=/root
export MINIKUBE_IN_STYLE=false
LOG_FILE=/var/log/minikube-setup.log

# Mirror all output to logfile
exec > >(tee -a "$LOG_FILE") 2>&1

log(){ echo "[$(date '+%F %T')] $*"; }

# On error: show helpful logs
trap 'RC=$?; echo; echo "---- docker/minikube logs (on error) ----";
      (journalctl -u docker --no-pager -n 200 || true);
      (tail -n 200 ~/.minikube/logs/lastStart.txt 2>/dev/null || true);
      echo "-------------------------------------------";
      exit $RC' ERR

# --- Args & defaults -------------------------------------------------------------------------
CLUSTER_NAME="${1:-minikube}"
ENVIRONMENT="${2:-dev}"
MINIKUBE_VERSION="${3:-v1.34.0}"
KUBERNETES_VERSION="${4:-v1.30.0}"
DRIVER="${5:-docker}"
REQ_MEMORY_RAW="${6:-3000}"   # may be "3000" or "3000mb"
REQ_CPUS="${7:-2}"

# Normalize memory to integer MB
REQ_MEMORY_MB="${REQ_MEMORY_RAW%MB}"
REQ_MEMORY_MB="${REQ_MEMORY_MB%mb}"

# --- Helpers ---------------------------------------------------------------------------------
retry() { for i in {1..8}; do "$@" && return 0; sleep $((i*5)); done; return 1; }

# Query Docker for actual resource limits (preferred when using docker driver)
get_docker_json() {
  docker system info --format '{{json .}}' 2>/dev/null || echo '{}'
}

calc_caps() {
  # Total mem via Docker, fallback to /proc/meminfo
  local docker_json total_bytes total_mb ncpu
  docker_json="$(get_docker_json)"
  total_bytes="$(printf '%s' "$docker_json" | awk -F'[:,{}"]' '/MemTotal/ {print $6; exit}' || true)"
  if [[ -n "${total_bytes}" && "${total_bytes}" -gt 0 ]] 2>/dev/null; then
    TOTAL_MB=$(( total_bytes / 1024 / 1024 ))
  else
    TOTAL_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
  fi

  # Leave headroom for OS & Docker (safe margin)
  SAFE_MAX_MB=$(( TOTAL_MB - 768 ))
  if (( SAFE_MAX_MB < 2200 )); then
    # if system is very small, try smaller margin
    SAFE_MAX_MB=$(( TOTAL_MB - 512 ))
  fi
  if (( SAFE_MAX_MB < 1500 )); then
    SAFE_MAX_MB=1500
  fi

  # CPUs via Docker, fallback to nproc
  ncpu="$(printf '%s' "$docker_json" | awk -F'[:,{}"]' '/NCPU/ {print $6; exit}' || true)"
  if [[ -z "$ncpu" || "$ncpu" -le 0 ]] 2>/dev/null; then
    ncpu="$(nproc || echo 2)"
  fi
  AVAIL_CPUS="$ncpu"

  # Apply caps
  if [[ -z "$REQ_MEMORY_MB" || "$REQ_MEMORY_MB" -le 0 ]] 2>/dev/null; then
    REQ_MEMORY_MB=3000
  fi
  if (( REQ_MEMORY_MB > SAFE_MAX_MB )); then
    log "Requested memory ${REQ_MEMORY_MB}MB exceeds safe max ${SAFE_MAX_MB}MB on this host; capping."
    REQ_MEMORY_MB="$SAFE_MAX_MB"
  fi

  if [[ -z "$REQ_CPUS" || "$REQ_CPUS" -le 0 ]] 2>/dev/null; then
    REQ_CPUS=2
  fi
  if (( REQ_CPUS > AVAIL_CPUS )); then
    log "Requested CPUs ${REQ_CPUS} exceeds available ${AVAIL_CPUS}; capping."
    REQ_CPUS="$AVAIL_CPUS"
  fi

  # Export the final values
  MINIKUBE_MEMORY_MB="$REQ_MEMORY_MB"
  MINIKUBE_CPUS="$REQ_CPUS"
}

# --- Idempotency: if already running, exit success -------------------------------------------
if command -v minikube >/dev/null 2>&1; then
  if minikube status >/dev/null 2>&1; then
    log "Minikube already running; writing ready marker."
    echo "SUCCESS: Minikube already running at $(date -Iseconds)" > /tmp/minikube-ready
    chown ubuntu:ubuntu /tmp/minikube-ready || true
    exit 0
  fi
fi

# --- Base packages ----------------------------------------------------------------------------
log "Installing base packages (curl, gnupg, lsb-release, conntrack, socat)"
retry apt-get update -y
retry apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https conntrack socat

# --- Kernel prerequisites ---------------------------------------------------------------------
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

# --- Docker (official repository) --------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker (official repository)"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  UBU_CODENAME="$(. /etc/os-release && echo "$UBUNTU_CODENAME")"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBU_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
  retry apt-get update -y
  retry apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

log "Configuring Docker to use systemd cgroup driver"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{
  "exec-opts": ["native.cgroupdriver=systemd"]
}
JSON
systemctl restart docker
until systemctl is-active --quiet docker; do
  log "Waiting for Docker to be active..."
  sleep 2
done
log "Docker is active"

# --- kubectl ----------------------------------------------------------------------------------
if ! command -v kubectl >/dev/null 2>&1; then
  log "Installing kubectl ${KUBERNETES_VERSION}"
  curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi
kubectl version --client=true --output=yaml || true

# --- Minikube ---------------------------------------------------------------------------------
if ! command -v minikube >/dev/null 2>&1; then
  log "Installing Minikube ${MINIKUBE_VERSION}"
  curl -fsSL -o /usr/local/bin/minikube "https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-amd64"
  chmod +x /usr/local/bin/minikube
fi
minikube version || true

# --- Calculate safe resource caps --------------------------------------------------------------
calc_caps
log "Host totals: $(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)MB RAM, $(nproc) CPUs"
log "Using Minikube resources: ${MINIKUBE_MEMORY_MB}MB RAM, ${MINIKUBE_CPUS} CPUs (driver=${DRIVER})"

# --- Start Minikube ----------------------------------------------------------------------------
log "Starting Minikube..."
minikube start \
  --driver="${DRIVER}" \
  --kubernetes-version="${KUBERNETES_VERSION}" \
  --memory="${MINIKUBE_MEMORY_MB}mb" \
  --cpus="${MINIKUBE_CPUS}" \
  --container-runtime=docker \
  --wait=all

# --- Verify ------------------------------------------------------------------------------------
log "Cluster info"
kubectl cluster-info
kubectl get nodes -o wide || true

# --- Success marker ---------------------------------------------------------------------------
echo "SUCCESS: Minikube cluster is ready at $(date -Iseconds)" > /tmp/minikube-ready
chown ubuntu:ubuntu /tmp/minikube-ready || true
log "Completed successfully for cluster=${CLUSTER_NAME}, env=${ENVIRONMENT}"
exit 0
