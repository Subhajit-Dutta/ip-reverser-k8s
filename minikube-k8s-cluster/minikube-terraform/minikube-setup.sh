#!/bin/bash

# Minikube Setup Script for AWS EC2 - VERSION 9 (QUOTE FIXED)
# This script eliminates all template conflicts and quote issues

set -e

# Logging
exec > >(tee /var/log/minikube-setup.log)
exec 2>&1

echo "Starting Minikube setup at $(date)"

# Variables from Terraform
echo "Cluster Name: ${cluster_name}"
echo "Environment: ${environment}"
echo "Minikube Version: ${minikube_version}"
echo "Kubernetes Version: ${kubernetes_version}"
echo "Minikube Driver: ${minikube_driver}"
echo "Minikube Memory: ${minikube_memory}"
echo "Minikube CPUs: ${minikube_cpus}"

# Get instance metadata
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo "Instance Private IP: $PRIVATE_IP"
echo "Instance Public IP: $PUBLIC_IP"

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
    socat

# Install Docker
echo "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

# Configure Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Wait for Docker to be ready
echo "Waiting for Docker daemon to be fully ready..."
sleep 10

# Fix Docker socket permissions
chmod 666 /var/run/docker.sock
chown root:docker /var/run/docker.sock

# Verify Docker
if ! systemctl is-active docker >/dev/null; then
    echo "ERROR: Docker service is not running"
    exit 1
fi

echo "Docker configuration completed successfully"

# Configure Docker daemon for Minikube
mkdir -p /etc/docker
cat <<DOCKEREOF > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "insecure-registries": ["10.96.0.0/12", "192.168.0.0/16"]
}
DOCKEREOF

systemctl daemon-reload
systemctl restart docker
sleep 10

# Install kubectl
echo "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/${kubernetes_version}/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install Minikube
echo "Installing Minikube ${minikube_version}..."
curl -LO "https://storage.googleapis.com/minikube/releases/${minikube_version}/minikube-linux-amd64"
chmod +x minikube-linux-amd64
mv minikube-linux-amd64 /usr/local/bin/minikube

# Install crictl
echo "Installing crictl..."
CRICTL_VERSION="v1.28.0"
curl -L "https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-$CRICTL_VERSION-linux-amd64.tar.gz" | tar -C /usr/local/bin -xz

# Configure system for Minikube
echo "Configuring system for Minikube..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

modprobe br_netfilter
echo 'br_netfilter' >> /etc/modules-load.d/minikube.conf

cat <<SYSCTLEOF > /etc/sysctl.d/minikube.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYSCTLEOF

sysctl --system

# Create configuration files for the startup script
echo "${minikube_memory}" > /tmp/minikube-memory
echo "${minikube_cpus}" > /tmp/minikube-cpus
echo "${minikube_driver}" > /tmp/minikube-driver
echo "${kubernetes_version}" > /tmp/minikube-k8s-version

# Create startup script directly without base64 encoding
cat > /tmp/start-minikube.sh << 'SCRIPT_END'
#!/bin/bash
set -e

export MINIKUBE_HOME=/home/ubuntu/.minikube
export KUBECONFIG=/home/ubuntu/.kube/config
export CHANGE_MINIKUBE_NONE_USER=true

echo "Starting Minikube as ubuntu user..."
echo "Current user: $(whoami)"
echo "Home directory: $HOME"

# Set up directories
mkdir -p /home/ubuntu/.minikube
mkdir -p /home/ubuntu/.kube
chown -R ubuntu:ubuntu /home/ubuntu/.minikube
chown -R ubuntu:ubuntu /home/ubuntu/.kube

# Test Docker access
echo "Testing Docker access..."
if ! docker ps >/dev/null 2>&1; then
    echo "Docker access failed, attempting to fix..."
    sudo chmod 666 /var/run/docker.sock
    if ! docker ps >/dev/null 2>&1; then
        echo "Docker access still failing"
        exit 1
    fi
fi
echo "Docker access confirmed"

# Get system resources and read configuration from files
TOTAL_MEM=$(free -m | grep Mem | awk '{print $2}')
CPU_CORES=$(nproc)
REQUESTED_MEM=$(cat /tmp/minikube-memory)
REQUESTED_CPUS=$(cat /tmp/minikube-cpus)
DRIVER=$(cat /tmp/minikube-driver)
K8S_VERSION=$(cat /tmp/minikube-k8s-version)

echo "System resources:"
echo "  Total Memory: ${TOTAL_MEM}MB"
echo "  CPU Cores: ${CPU_CORES}"
echo "  Requested Memory: ${REQUESTED_MEM}MB"
echo "  Requested CPUs: ${REQUESTED_CPUS}"

# Calculate appropriate resources
MINIKUBE_MEM=$REQUESTED_MEM
MINIKUBE_CPUS=$REQUESTED_CPUS

if [ $TOTAL_MEM -lt $REQUESTED_MEM ]; then
    MINIKUBE_MEM=$((TOTAL_MEM - 512))
    echo "Adjusting memory to ${MINIKUBE_MEM}MB"
fi

if [ $CPU_CORES -lt $REQUESTED_CPUS ]; then
    MINIKUBE_CPUS=$CPU_CORES
    echo "Adjusting CPUs to ${MINIKUBE_CPUS}"
fi

echo "Starting Minikube with:"
echo "  Memory: ${MINIKUBE_MEM}MB"
echo "  CPUs: ${MINIKUBE_CPUS}"
echo "  Driver: ${DRIVER}"
echo "  Kubernetes: ${K8S_VERSION}"

# Start Minikube
if minikube start \
    --driver=$DRIVER \
    --memory=$MINIKUBE_MEM \
    --cpus=$MINIKUBE_CPUS \
    --kubernetes-version=$K8S_VERSION \
    --delete-on-failure \
    --force \
    --wait=true \
    --wait-timeout=600s \
    --v=3; then
    echo "Minikube started successfully"
else
    echo "Minikube start failed"
    minikube logs || echo "No logs available"
    exit 1
fi

# Verify cluster
echo "Verifying cluster..."
minikube status
kubectl get nodes

# Wait for cluster to be ready
echo "Waiting for cluster readiness..."
timeout 300 bash -c 'until kubectl get nodes | grep -q "Ready"; do echo "Waiting..."; sleep 10; done'

# Enable addons
echo "Enabling addons..."
minikube addons enable storage-provisioner || true
minikube addons enable default-storageclass || true
minikube addons enable dashboard || echo "Dashboard failed"
minikube addons enable metrics-server || echo "Metrics-server failed"

echo "Minikube setup completed successfully!"
SCRIPT_END

chmod +x /tmp/start-minikube.sh

# Run the Minikube setup as ubuntu user
echo "Starting Minikube cluster..."
sudo -i -u ubuntu /tmp/start-minikube.sh

# Verify installation
echo "Final verification..."
sudo -i -u ubuntu bash -c '
export MINIKUBE_HOME=/home/ubuntu/.minikube
export KUBECONFIG=/home/ubuntu/.kube/config

if minikube status >/dev/null 2>&1; then
    echo "✅ Minikube verification successful"
    minikube status
else
    echo "❌ Minikube verification failed"
    exit 1
fi
'

# Create Jenkins service account
echo "Creating Jenkins service account..."
sudo -i -u ubuntu bash -c '
export KUBECONFIG=/home/ubuntu/.kube/config

kubectl apply -f - <<JENKINSEOF
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
JENKINSEOF
'

# Create cluster info file
cat <<INFOEOF > /home/ubuntu/cluster-info.txt
Minikube Cluster Information
===========================

Cluster Name: ${cluster_name}
Environment: ${environment}
Setup Date: $(date)

Instance Information:
- Private IP: $PRIVATE_IP
- Public IP: $PUBLIC_IP
- Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)

Minikube Configuration:
- Version: ${minikube_version}
- Kubernetes Version: ${kubernetes_version}
- Driver: ${minikube_driver}
- Memory: ${minikube_memory}MB
- CPUs: ${minikube_cpus}

Access Information:
- SSH: ssh -i ${cluster_name}-key.pem ubuntu@$PUBLIC_IP
- Kubernetes API: https://$PRIVATE_IP:8443

Setup completed at: $(date)
INFOEOF

chown ubuntu:ubuntu /home/ubuntu/cluster-info.txt

# Create utility scripts
cat <<'DASHEOF' > /home/ubuntu/start-dashboard.sh
#!/bin/bash
echo "Starting Kubernetes Dashboard..."
minikube dashboard --url
DASHEOF

cat <<'HEALTHEOF' > /home/ubuntu/cluster-health-check.sh
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
HEALTHEOF

chmod +x /home/ubuntu/start-dashboard.sh
chmod +x /home/ubuntu/cluster-health-check.sh
chown ubuntu:ubuntu /home/ubuntu/start-dashboard.sh
chown ubuntu:ubuntu /home/ubuntu/cluster-health-check.sh

# Create systemd service
cat <<SERVICEEOF > /etc/systemd/system/minikube.service
[Unit]
Description=Minikube Kubernetes Cluster
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=ubuntu
Group=ubuntu
ExecStart=/usr/local/bin/minikube start --driver=${minikube_driver}
RemainAfterExit=yes
Environment=HOME=/home/ubuntu
Environment=MINIKUBE_HOME=/home/ubuntu/.minikube

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl enable minikube.service

# Final health check
echo "Performing final health check..."
sudo -i -u ubuntu bash -c '
export MINIKUBE_HOME=/home/ubuntu/.minikube
export KUBECONFIG=/home/ubuntu/.kube/config

echo "Final cluster status:"
minikube status
kubectl get nodes
kubectl get pods -n kube-system
'

# Create success marker
echo "SUCCESS: Minikube cluster is ready" > /tmp/minikube-ready
chown ubuntu:ubuntu /tmp/minikube-ready

echo "✅ Minikube cluster setup completed successfully at $(date)"
echo "🎉 Cluster is ready for deployments!"

# Cleanup temporary files
rm -f /tmp/start-minikube.sh /tmp/minikube-memory /tmp/minikube-cpus /tmp/minikube-driver /tmp/minikube-k8s-version

echo "Setup script completed successfully!"