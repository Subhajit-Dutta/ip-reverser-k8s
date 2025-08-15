#!/bin/bash

# Minikube Setup Script - TERRAFORM COMPATIBLE VERSION
# This version is specifically designed to work with Terraform remote-exec
# Usage: sudo ./setup-minikube-terraform.sh <cluster_name> <environment> <minikube_version> <k8s_version> <driver> <memory> <cpus>

# TERRAFORM COMPATIBILITY FIXES
set -e
set -o pipefail

# Ensure we have a proper environment even in non-interactive mode
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME=/root
export TERM=xterm

# Configuration (can be overridden by command line arguments)
CLUSTER_NAME=${1:-"minikube-demo"}
ENVIRONMENT=${2:-"demo"}
MINIKUBE_VERSION=${3:-"v1.32.0"}
KUBERNETES_VERSION=${4:-"v1.28.3"}
MINIKUBE_DRIVER=${5:-"docker"}
MINIKUBE_MEMORY=${6:-"3900"}
MINIKUBE_CPUS=${7:-"2"}

# Logging setup
LOG_FILE="/var/log/minikube-setup.log"

# Create log function that works in non-interactive mode
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Redirect all output to log file while still showing on screen
exec > >(tee -a "$LOG_FILE")
exec 2>&1

log "=========================================="
log "Minikube Setup Script - TERRAFORM COMPATIBLE"
log "=========================================="
log "Cluster Name: $CLUSTER_NAME"
log "Environment: $ENVIRONMENT"
log "Minikube Version: $MINIKUBE_VERSION"
log "Kubernetes Version: $KUBERNETES_VERSION"
log "Driver: $MINIKUBE_DRIVER"
log "Memory: $MINIKUBE_MEMORY MB"
log "CPUs: $MINIKUBE_CPUS"
log "=========================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log "ERROR: This script must be run as root (use sudo)"
   exit 1
fi

# Get instance metadata with retries
log "Getting instance metadata..."
get_metadata() {
    local url=$1
    local retries=5
    local count=0
    
    while [ $count -lt $retries ]; do
        if result=$(curl -s --connect-timeout 5 --max-time 10 "$url" 2>/dev/null); then
            echo "$result"
            return 0
        fi
        count=$((count + 1))
        sleep 2
    done
    echo "unknown"
}

PRIVATE_IP=$(get_metadata "http://169.254.169.254/latest/meta-data/local-ipv4")
PUBLIC_IP=$(get_metadata "http://169.254.169.254/latest/meta-data/public-ipv4")
INSTANCE_TYPE=$(get_metadata "http://169.254.169.254/latest/meta-data/instance-type")

log "Instance Info:"
log "  Private IP: $PRIVATE_IP"
log "  Public IP: $PUBLIC_IP"
log "  Instance Type: $INSTANCE_TYPE"

# Update system with better error handling
log "Updating system packages..."
apt-get update -y || {
    log "First update failed, trying again..."
    sleep 10
    apt-get update -y
}

apt-get upgrade -y

# Install essential packages
log "Installing essential packages..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    unzip \
    jq \
    conntrack \
    socat \
    python3 \
    python3-pip \
    software-properties-common

# Install Docker with retry logic
log "Installing Docker..."
install_docker() {
    # Remove any existing Docker installations
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker repository
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io
}

# Try Docker installation with retry
DOCKER_RETRIES=3
for i in $(seq 1 $DOCKER_RETRIES); do
    if install_docker; then
        log "Docker installed successfully on attempt $i"
        break
    else
        log "Docker installation failed on attempt $i"
        if [ $i -eq $DOCKER_RETRIES ]; then
            log "ERROR: Failed to install Docker after $DOCKER_RETRIES attempts"
            exit 1
        fi
        sleep 10
    fi
done

# Configure Docker
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
log "Waiting for Docker to be ready..."
DOCKER_WAIT=0
while ! systemctl is-active --quiet docker && [ $DOCKER_WAIT -lt 30 ]; do
    sleep 2
    DOCKER_WAIT=$((DOCKER_WAIT + 1))
done

if ! systemctl is-active --quiet docker; then
    log "ERROR: Docker failed to start after 60 seconds"
    systemctl status docker
    exit 1
fi

# Add ubuntu user to docker group and fix permissions
usermod -aG docker ubuntu
chmod 666 /var/run/docker.sock
chown root:docker /var/run/docker.sock

log "Docker installed and configured successfully"

# Configure Docker daemon for Minikube
log "Configuring Docker daemon..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "insecure-registries": ["10.96.0.0/12", "192.168.0.0/16"]
}
EOF

systemctl daemon-reload
systemctl restart docker
sleep 10

# Install kubectl
log "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$KUBERNETES_VERSION/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install Minikube
log "Installing Minikube $MINIKUBE_VERSION..."
curl -LO "https://storage.googleapis.com/minikube/releases/$MINIKUBE_VERSION/minikube-linux-amd64"
chmod +x minikube-linux-amd64
mv minikube-linux-amd64 /usr/local/bin/minikube

# Install crictl
log "Installing crictl..."
CRICTL_VERSION="v1.28.0"
curl -L "https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-$CRICTL_VERSION-linux-amd64.tar.gz" | tar -C /usr/local/bin -xz

# Configure system for Minikube
log "Configuring system for Minikube..."

# Disable swap
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab

# Load kernel modules
modprobe br_netfilter
echo 'br_netfilter' > /etc/modules-load.d/minikube.conf

# Set ONLY the sysctl parameters that work
log "Setting sysctl parameters..."
cat > /etc/sysctl.d/minikube.conf << 'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

# Apply sysctl settings with individual error handling
sysctl -w net.bridge.bridge-nf-call-iptables=1 2>/dev/null || log "Warning: Could not set bridge-nf-call-iptables"
sysctl -w net.bridge.bridge-nf-call-ip6tables=1 2>/dev/null || log "Warning: Could not set bridge-nf-call-ip6tables"
sysctl -w net.ipv4.ip_forward=1 2>/dev/null || log "Warning: Could not set ip_forward"

# TERRAFORM-COMPATIBLE directory setup
log "Setting up ubuntu user environment for Terraform execution..."
UBUNTU_HOME="/home/ubuntu"
MINIKUBE_HOME="$UBUNTU_HOME/.minikube"
KUBE_DIR="$UBUNTU_HOME/.kube"

# Completely clean and recreate directories
log "Cleaning up any existing directories..."
pkill -f minikube 2>/dev/null || true
sleep 5

# Force removal as root
rm -rf "$MINIKUBE_HOME" "$KUBE_DIR" 2>/dev/null || true
sleep 2

# Create directories as root first, then change ownership
log "Creating directories with proper permissions..."
mkdir -p "$MINIKUBE_HOME"
mkdir -p "$KUBE_DIR"

# Set ownership and permissions
chown -R ubuntu:ubuntu "$UBUNTU_HOME"
chmod 755 "$MINIKUBE_HOME"
chmod 755 "$KUBE_DIR"

# Verify Docker access for ubuntu user
log "Verifying Docker access for ubuntu user..."
if ! sudo -u ubuntu docker ps >/dev/null 2>&1; then
    log "Fixing Docker access..."
    usermod -aG docker ubuntu
    chmod 666 /var/run/docker.sock
    
    # Force group membership update
    newgrp docker 2>/dev/null || true
    
    # Test again
    if ! sudo -u ubuntu docker ps >/dev/null 2>&1; then
        log "ERROR: Ubuntu user still cannot access Docker"
        ls -la /var/run/docker.sock
        groups ubuntu
        exit 1
    fi
fi

log "Docker access confirmed for ubuntu user"

# Calculate system resources
log "Calculating system resources..."
TOTAL_MEM=$(free -m | grep '^Mem:' | awk '{print $2}')
CPU_CORES=$(nproc)

log "System resources:"
log "  Total Memory: ${TOTAL_MEM}MB"
log "  CPU Cores: $CPU_CORES"

# Adjust resource allocation
ADJUSTED_MEMORY=$MINIKUBE_MEMORY
ADJUSTED_CPUS=$MINIKUBE_CPUS

if [ "$TOTAL_MEM" -lt 4096 ]; then
    ADJUSTED_MEMORY=2800
    log "INFO: Small instance detected, using safe memory allocation: ${ADJUSTED_MEMORY}MB"
elif [ "$TOTAL_MEM" -lt "$MINIKUBE_MEMORY" ]; then
    ADJUSTED_MEMORY=$((TOTAL_MEM - 1024))
    log "WARNING: Adjusting memory to ${ADJUSTED_MEMORY}MB (system has ${TOTAL_MEM}MB total)"
fi

if [ "$CPU_CORES" -lt "$MINIKUBE_CPUS" ]; then
    ADJUSTED_CPUS=$CPU_CORES
    log "WARNING: Adjusting CPUs to $ADJUSTED_CPUS (system has $CPU_CORES cores)"
fi

log "Minikube will use: Memory=${ADJUSTED_MEMORY}MB, CPUs=$ADJUSTED_CPUS"

# TERRAFORM-COMPATIBLE Minikube startup
log "Starting Minikube cluster with Terraform-compatible method..."

# Create startup script with FULL environment setup
cat > /tmp/minikube-start.sh << EOF
#!/bin/bash
set -e

# CRITICAL: Set full environment for non-interactive execution
export HOME=/home/ubuntu
export USER=ubuntu
export MINIKUBE_HOME=/home/ubuntu/.minikube
export KUBECONFIG=/home/ubuntu/.kube/config
export CHANGE_MINIKUBE_NONE_USER=true
export MINIKUBE_SUPPRESS_SUPPORT_URL=true
export PATH="/usr/local/bin:/usr/bin:/bin"

# Change to ubuntu home directory
cd /home/ubuntu

echo "Environment check:"
echo "HOME=\$HOME"
echo "USER=\$USER"
echo "MINIKUBE_HOME=\$MINIKUBE_HOME"
echo "KUBECONFIG=\$KUBECONFIG"
echo "PWD=\$(pwd)"
echo "User=\$(whoami)"

# Ensure directories exist and have correct permissions
mkdir -p /home/ubuntu/.minikube /home/ubuntu/.kube
chmod 755 /home/ubuntu/.minikube /home/ubuntu/.kube

# Clean any existing cluster
echo "Cleaning any existing Minikube cluster..."
minikube delete --all --purge 2>/dev/null || true
sleep 5

# Remove any leftover files
rm -rf /home/ubuntu/.minikube/cache 2>/dev/null || true
rm -rf /home/ubuntu/.minikube/logs 2>/dev/null || true
rm -f /home/ubuntu/.kube/config 2>/dev/null || true

# Start Minikube with full parameters
echo "Starting Minikube..."
minikube start \
    --driver=$MINIKUBE_DRIVER \
    --memory=$ADJUSTED_MEMORY \
    --cpus=$ADJUSTED_CPUS \
    --kubernetes-version=$KUBERNETES_VERSION \
    --delete-on-failure \
    --force \
    --wait=true \
    --wait-timeout=600s \
    --v=3

echo "Minikube started successfully!"

# Verify cluster
echo "Verifying cluster..."
minikube status
kubectl get nodes

# Wait for nodes to be ready
echo "Waiting for nodes to be ready..."
timeout 300 bash -c 'until kubectl get nodes | grep -q "Ready"; do echo "Waiting for nodes..."; sleep 10; done'

# Enable essential addons
echo "Enabling addons..."
minikube addons enable storage-provisioner || echo "Storage provisioner addon failed"
minikube addons enable default-storageclass || echo "Default storage class addon failed"
minikube addons enable dashboard || echo "Dashboard addon failed"
minikube addons enable metrics-server || echo "Metrics-server addon failed"

echo "Minikube setup completed successfully!"
EOF

chmod +x /tmp/minikube-start.sh
chown ubuntu:ubuntu /tmp/minikube-start.sh

# Execute as ubuntu user with proper environment
log "Executing Minikube startup as ubuntu user..."
if sudo -E -u ubuntu bash /tmp/minikube-start.sh; then
    log "✅ Minikube started successfully"
else
    log "❌ Minikube startup failed"
    log "Attempting to get logs..."
    sudo -u ubuntu minikube logs 2>/dev/null || log "Could not get minikube logs"
    exit 1
fi

# Final verification
log "Performing final verification..."
if sudo -u ubuntu minikube status | grep -q "Running"; then
    log "✅ Minikube is running successfully"
else
    log "❌ Final verification failed"
    sudo -u ubuntu minikube status || log "Could not get status"
    exit 1
fi

# Create Jenkins service account
log "Creating Jenkins service account..."
sudo -u ubuntu kubectl apply -f - << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-deployer
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-deployer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: jenkins-deployer
  namespace: default
EOF

# Create cluster information file
log "Creating cluster information file..."
cat > "$UBUNTU_HOME/cluster-info.txt" << EOF
Minikube Cluster Information
===========================

Cluster Name: $CLUSTER_NAME
Environment: $ENVIRONMENT
Setup Date: $(date)

Instance Information:
- Private IP: $PRIVATE_IP
- Public IP: $PUBLIC_IP
- Instance Type: $INSTANCE_TYPE

Minikube Configuration:
- Version: $MINIKUBE_VERSION
- Kubernetes Version: $KUBERNETES_VERSION
- Driver: $MINIKUBE_DRIVER
- Memory: ${ADJUSTED_MEMORY}MB
- CPUs: $ADJUSTED_CPUS

Access Information:
- SSH: ssh -i $CLUSTER_NAME-key.pem ubuntu@$PUBLIC_IP

Setup completed at: $(date)
EOF

chown ubuntu:ubuntu "$UBUNTU_HOME/cluster-info.txt"

# Create utility scripts
cat > "$UBUNTU_HOME/cluster-health-check.sh" << 'EOF'
#!/bin/bash
echo "=== Minikube Cluster Health Check ==="
echo "Date: $(date)"
echo ""
echo "Minikube Status:"
minikube status
echo ""
echo "Node Status:"
kubectl get nodes
echo ""
echo "System Pods:"
kubectl get pods -n kube-system
echo ""
echo "=== Health Check Complete ==="
EOF

chmod +x "$UBUNTU_HOME/cluster-health-check.sh"
chown ubuntu:ubuntu "$UBUNTU_HOME/cluster-health-check.sh"

# Cleanup temporary files
rm -f /tmp/minikube-start.sh

# Create success marker for Terraform
echo "SUCCESS: Minikube cluster is ready at $(date)" > /tmp/minikube-ready
echo "Cluster Name: $CLUSTER_NAME" >> /tmp/minikube-ready
echo "Environment: $ENVIRONMENT" >> /tmp/minikube-ready
echo "Public IP: $PUBLIC_IP" >> /tmp/minikube-ready

chown ubuntu:ubuntu /tmp/minikube-ready

log "=========================================="
log "✅ TERRAFORM-COMPATIBLE SETUP COMPLETED!"
log "=========================================="
log "Cluster is ready for deployments!"
log "Success marker created at: /tmp/minikube-ready"
log "Setup completed at: $(date)"
log "=========================================="