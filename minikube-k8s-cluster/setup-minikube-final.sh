#!/bin/bash

# Minikube Setup Script - FINAL WORKING VERSION
# This script works 100% with Terraform based on successful manual testing
# Usage: sudo ./setup-minikube-final.sh <cluster_name> <environment> <minikube_version> <k8s_version> <driver> <memory> <cpus>

set -e

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
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "=========================================="
echo "Minikube Setup Script - FINAL VERSION"
echo "=========================================="
echo "Date: $(date)"
echo "Cluster Name: $CLUSTER_NAME"
echo "Environment: $ENVIRONMENT"
echo "Minikube Version: $MINIKUBE_VERSION"
echo "Kubernetes Version: $KUBERNETES_VERSION"
echo "Driver: $MINIKUBE_DRIVER"
echo "Memory: $MINIKUBE_MEMORY MB"
echo "CPUs: $MINIKUBE_CPUS"
echo "=========================================="

# Get instance metadata
echo "Getting instance metadata..."
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 || echo "unknown")
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "unknown")
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type || echo "unknown")

echo "Instance Info:"
echo "  Private IP: $PRIVATE_IP"
echo "  Public IP: $PUBLIC_IP"
echo "  Instance Type: $INSTANCE_TYPE"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

# Update system
echo "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# Install essential packages
echo "Installing essential packages..."
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
    python3-pip

# Install Docker
echo "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

# Configure Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Wait for Docker to be ready
echo "Waiting for Docker to be ready..."
sleep 10

# Fix Docker permissions
chmod 666 /var/run/docker.sock
chown root:docker /var/run/docker.sock

# Verify Docker is running
if ! systemctl is-active --quiet docker; then
    echo "ERROR: Docker failed to start"
    systemctl status docker
    exit 1
fi

echo "Docker installed and configured successfully"

# Configure Docker daemon for Minikube
echo "Configuring Docker daemon..."
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
echo "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$KUBERNETES_VERSION/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install Minikube
echo "Installing Minikube $MINIKUBE_VERSION..."
curl -LO "https://storage.googleapis.com/minikube/releases/$MINIKUBE_VERSION/minikube-linux-amd64"
chmod +x minikube-linux-amd64
mv minikube-linux-amd64 /usr/local/bin/minikube

# Install crictl
echo "Installing crictl..."
CRICTL_VERSION="v1.28.0"
curl -L "https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-$CRICTL_VERSION-linux-amd64.tar.gz" | tar -C /usr/local/bin -xz

# Configure system for Minikube
echo "Configuring system for Minikube..."

# Disable swap
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab

# Load kernel modules
modprobe br_netfilter
echo 'br_netfilter' > /etc/modules-load.d/minikube.conf

# Set sysctl parameters
cat > /etc/sysctl.d/minikube.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# Setup ubuntu user environment
echo "Setting up ubuntu user environment..."
UBUNTU_HOME="/home/ubuntu"
MINIKUBE_HOME="$UBUNTU_HOME/.minikube"
KUBE_DIR="$UBUNTU_HOME/.kube"

# Remove any existing directories and recreate with proper permissions
rm -rf "$MINIKUBE_HOME" "$KUBE_DIR"

# Create directories as ubuntu user
sudo -u ubuntu mkdir -p "$MINIKUBE_HOME"
sudo -u ubuntu mkdir -p "$KUBE_DIR"

# Ensure proper ownership
chown -R ubuntu:ubuntu "$UBUNTU_HOME/.minikube"
chown -R ubuntu:ubuntu "$UBUNTU_HOME/.kube"

# Test Docker access for ubuntu user
echo "Testing Docker access for ubuntu user..."
if ! sudo -u ubuntu docker ps >/dev/null 2>&1; then
    echo "Fixing Docker access for ubuntu user..."
    chmod 666 /var/run/docker.sock
    
    # Test again
    if ! sudo -u ubuntu docker ps >/dev/null 2>&1; then
        echo "ERROR: Ubuntu user cannot access Docker"
        exit 1
    fi
fi

echo "Docker access confirmed for ubuntu user"

# Get system resources and calculate appropriate settings
echo "Calculating system resources..."
TOTAL_MEM=$(free -m | grep '^Mem:' | awk '{print $2}')
CPU_CORES=$(nproc)

echo "System resources:"
echo "  Total Memory: ${TOTAL_MEM}MB"
echo "  CPU Cores: $CPU_CORES"

# Calculate safer memory allocation
ADJUSTED_MEMORY=$MINIKUBE_MEMORY
ADJUSTED_CPUS=$MINIKUBE_CPUS

# For t3.medium (4GB total), use max 2800MB for Minikube
if [ "$TOTAL_MEM" -lt 4096 ]; then
    ADJUSTED_MEMORY=2800
    echo "INFO: t3.medium detected, using safe memory allocation: ${ADJUSTED_MEMORY}MB"
elif [ "$TOTAL_MEM" -lt "$MINIKUBE_MEMORY" ]; then
    # Leave 1GB for system
    ADJUSTED_MEMORY=$((TOTAL_MEM - 1024))
    echo "WARNING: Adjusting memory to ${ADJUSTED_MEMORY}MB (system has ${TOTAL_MEM}MB total)"
fi

if [ "$CPU_CORES" -lt "$MINIKUBE_CPUS" ]; then
    ADJUSTED_CPUS=$CPU_CORES
    echo "WARNING: Adjusting CPUs to $ADJUSTED_CPUS (system has $CPU_CORES cores)"
fi

echo "Minikube will use:"
echo "  Memory: ${ADJUSTED_MEMORY}MB"
echo "  CPUs: $ADJUSTED_CPUS"

# Create the Minikube startup script that we KNOW works
echo "Creating Minikube startup script..."
cat > /tmp/minikube-startup.sh << 'EOF'
#!/bin/bash
set -e

# Set environment variables
export HOME=/home/ubuntu
export MINIKUBE_HOME=/home/ubuntu/.minikube
export KUBECONFIG=/home/ubuntu/.kube/config
export CHANGE_MINIKUBE_NONE_USER=true

cd /home/ubuntu

echo "Starting Minikube as user: $(whoami)"
echo "Home directory: $HOME"
echo "Minikube home: $MINIKUBE_HOME"
echo "Kubeconfig: $KUBECONFIG"

# Verify directories exist and have correct permissions
ls -la /home/ubuntu/.minikube /home/ubuntu/.kube || echo "Directories not found, will be created"

# Clean any existing cluster
minikube delete --all --purge 2>/dev/null || true

# Remove any leftover kubeconfig
rm -f /home/ubuntu/.kube/config

# Start Minikube with conservative settings
echo "Starting Minikube with driver=DRIVER_PLACEHOLDER, memory=MEMORY_PLACEHOLDER MB, cpus=CPU_PLACEHOLDER"

minikube start \
    --driver=DRIVER_PLACEHOLDER \
    --memory=MEMORY_PLACEHOLDER \
    --cpus=CPU_PLACEHOLDER \
    --kubernetes-version=K8S_PLACEHOLDER \
    --delete-on-failure \
    --force \
    --wait=true \
    --wait-timeout=600s \
    --v=3

echo "Minikube started successfully!"

# Verify cluster
echo "Verifying cluster status..."
minikube status
kubectl get nodes

# Wait for nodes to be ready
echo "Waiting for nodes to be ready..."
timeout 300 bash -c 'until kubectl get nodes | grep -q "Ready"; do echo "Waiting for nodes..."; sleep 10; done'

# Enable essential addons
echo "Enabling Minikube addons..."
minikube addons enable storage-provisioner || true
minikube addons enable default-storageclass || true

# Enable optional addons (with error handling)
echo "Enabling optional addons..."
minikube addons enable dashboard || echo "Dashboard addon failed, continuing..."
minikube addons enable metrics-server || echo "Metrics-server addon failed, continuing..."

echo "Minikube setup completed successfully!"
EOF

# Replace placeholders in the startup script
sed -i "s/DRIVER_PLACEHOLDER/$MINIKUBE_DRIVER/g" /tmp/minikube-startup.sh
sed -i "s/MEMORY_PLACEHOLDER/$ADJUSTED_MEMORY/g" /tmp/minikube-startup.sh
sed -i "s/CPU_PLACEHOLDER/$ADJUSTED_CPUS/g" /tmp/minikube-startup.sh
sed -i "s/K8S_PLACEHOLDER/$KUBERNETES_VERSION/g" /tmp/minikube-startup.sh

# Make it executable and set ownership
chmod +x /tmp/minikube-startup.sh
chown ubuntu:ubuntu /tmp/minikube-startup.sh

# Execute the Minikube startup script as ubuntu user
echo "Starting Minikube cluster as ubuntu user..."
sudo -i -u ubuntu /tmp/minikube-startup.sh

# Verify the cluster is running
echo "Final verification..."
if sudo -i -u ubuntu minikube status | grep -q "Running"; then
    echo "✅ Minikube is running successfully"
else
    echo "❌ Minikube verification failed"
    echo "Getting logs for debugging..."
    sudo -i -u ubuntu minikube logs || echo "No logs available"
    exit 1
fi

# Create Jenkins service account and RBAC
echo "Creating Jenkins service account..."
sudo -i -u ubuntu kubectl apply -f - << 'EOF'
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
echo "Creating cluster information file..."
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
- Kubernetes API: https://$PRIVATE_IP:8443

Useful Commands:
- minikube status
- minikube dashboard --url
- kubectl get nodes
- kubectl get pods --all-namespaces

Setup completed at: $(date)
EOF

chown ubuntu:ubuntu "$UBUNTU_HOME/cluster-info.txt"

# Create utility scripts
echo "Creating utility scripts..."

# Dashboard script
cat > "$UBUNTU_HOME/start-dashboard.sh" << 'EOF'
#!/bin/bash
echo "Starting Kubernetes Dashboard..."
echo "Dashboard will be available at the URL shown below:"
minikube dashboard --url
EOF

# Health check script
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
echo "All Namespaces:"
kubectl get all --all-namespaces
echo ""
echo "Enabled Addons:"
minikube addons list | grep enabled
echo ""
echo "=== Health Check Complete ==="
EOF

chmod +x "$UBUNTU_HOME/start-dashboard.sh"
chmod +x "$UBUNTU_HOME/cluster-health-check.sh"
chown ubuntu:ubuntu "$UBUNTU_HOME/start-dashboard.sh"
chown ubuntu:ubuntu "$UBUNTU_HOME/cluster-health-check.sh"

# Create systemd service for auto-start
echo "Creating systemd service for Minikube auto-start..."
cat > /etc/systemd/system/minikube.service << EOF
[Unit]
Description=Minikube Kubernetes Cluster
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=ubuntu
Group=ubuntu
ExecStart=/usr/local/bin/minikube start --driver=$MINIKUBE_DRIVER
RemainAfterExit=yes
Environment=HOME=/home/ubuntu
Environment=MINIKUBE_HOME=/home/ubuntu/.minikube

[Install]
WantedBy=multi-user.target
EOF

systemctl enable minikube.service

# Final verification and summary
echo "Performing final cluster verification..."
sudo -i -u ubuntu minikube status
sudo -i -u ubuntu kubectl get nodes
sudo -i -u ubuntu kubectl get pods -n kube-system

# Create success marker for Terraform
echo "SUCCESS: Minikube cluster is ready" > /tmp/minikube-ready
chown ubuntu:ubuntu /tmp/minikube-ready

# Cleanup temporary files
rm -f /tmp/minikube-startup.sh

echo ""
echo "=========================================="
echo "✅ Minikube Setup Completed Successfully!"
echo "=========================================="
echo "🎉 Your Minikube cluster is ready for deployments!"
echo ""
echo "📋 Quick Start:"
echo "1. SSH to instance: ssh -i $CLUSTER_NAME-key.pem ubuntu@$PUBLIC_IP"
echo "2. Check status: ./cluster-health-check.sh"
echo "3. Start dashboard: ./start-dashboard.sh"
echo "4. Deploy apps: kubectl create deployment test --image=nginx"
echo ""
echo "🌐 Access your applications:"
echo "- NodePort services: http://$PUBLIC_IP:30000-32767"
echo "- Dashboard: Run ./start-dashboard.sh and forward ports"
echo ""
echo "📁 Files created:"
echo "- /home/ubuntu/cluster-info.txt"
echo "- /home/ubuntu/start-dashboard.sh"
echo "- /home/ubuntu/cluster-health-check.sh"
echo ""
echo "Setup completed at: $(date)"
echo "=========================================="