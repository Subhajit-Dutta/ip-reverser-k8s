#!/bin/bash

# Minikube Setup Script for AWS EC2 - FIXED VERSION
# This script installs and configures Minikube with Docker driver

set -e

# Logging
exec > >(tee /var/log/minikube-setup.log)
exec 2>&1

echo "Starting Minikube setup at $(date)"

# Variables from Terraform - Using the exact variable names passed from Terraform
CLUSTER_NAME="${cluster_name}"
ENVIRONMENT="${environment}"
MINIKUBE_VERSION="${minikube_version}"
KUBERNETES_VERSION="${kubernetes_version}"
MINIKUBE_DRIVER="${minikube_driver}"
MINIKUBE_MEMORY="${minikube_memory}"
MINIKUBE_CPUS="${minikube_cpus}"

# Get instance metadata
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo "Instance Private IP: $PRIVATE_IP"
echo "Instance Public IP: $PUBLIC_IP"
echo "Cluster Name: $CLUSTER_NAME"
echo "Minikube Version: $MINIKUBE_VERSION"
echo "Kubernetes Version: $KUBERNETES_VERSION"
echo "Minikube Memory: $MINIKUBE_MEMORY"
echo "Minikube CPUs: $MINIKUBE_CPUS"

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

# Configure Docker daemon for Minikube
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
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

# Wait for Docker to be ready
echo "Waiting for Docker to be ready..."
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

# Install crictl (Container Runtime Interface CLI)
echo "Installing crictl..."
CRICTL_VERSION="v1.28.0"
curl -L "https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-$CRICTL_VERSION-linux-amd64.tar.gz" | tar -C /usr/local/bin -xz

# Configure system for Minikube
echo "Configuring system for Minikube..."

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load kernel modules
modprobe br_netfilter
echo 'br_netfilter' >> /etc/modules-load.d/minikube.conf

# Set sysctl parameters
cat <<EOF > /etc/sysctl.d/minikube.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# Start Minikube as ubuntu user
echo "Starting Minikube cluster..."

# Start Minikube directly without separate script file to avoid variable issues
sudo -i -u ubuntu bash -c "
    set -e
    
    echo 'Starting Minikube as ubuntu user...'
    
    # Set environment variables
    export MINIKUBE_HOME=/home/ubuntu/.minikube
    export KUBECONFIG=/home/ubuntu/.kube/config
    export CHANGE_MINIKUBE_NONE_USER=true
    
    # Create directories with proper permissions
    mkdir -p /home/ubuntu/.minikube
    mkdir -p /home/ubuntu/.kube
    chown -R ubuntu:ubuntu /home/ubuntu/.minikube
    chown -R ubuntu:ubuntu /home/ubuntu/.kube
    
    # Start Minikube with configuration
    echo 'Starting Minikube with docker driver...'
    minikube start \
        --driver=docker \
        --memory=$MINIKUBE_MEMORY \
        --cpus=$MINIKUBE_CPUS \
        --kubernetes-version=$KUBERNETES_VERSION \
        --delete-on-failure \
        --force \
        --wait=true \
        --wait-timeout=600s
    
    # Verify Minikube is running
    echo 'Verifying Minikube status...'
    minikube status
    
    # Wait for cluster to be ready
    echo 'Waiting for cluster to be ready...'
    timeout 300 bash -c 'until kubectl get nodes | grep -q \"Ready\"; do echo \"Waiting for nodes...\"; sleep 10; done'
    
    # Enable basic addons only (to avoid timeout issues)
    echo 'Enabling essential Minikube addons...'
    minikube addons enable storage-provisioner || true
    minikube addons enable default-storageclass || true
    
    # Optional addons (enable separately to avoid blocking)
    echo 'Enabling additional addons...'
    minikube addons enable dashboard || echo 'Dashboard addon failed, continuing...'
    minikube addons enable metrics-server || echo 'Metrics-server addon failed, continuing...'
    
    # Final status check
    echo 'Final cluster verification...'
    minikube status
    kubectl get nodes
    kubectl get pods -n kube-system
    
    echo 'Minikube setup completed successfully!'
"

# Wait a bit to ensure everything is stable
sleep 30

# Verify final status
echo "Final verification as ubuntu user..."
sudo -u ubuntu minikube status || {
    echo "ERROR: Minikube failed to start properly"
    sudo -u ubuntu minikube logs
    exit 1
}

# Create Jenkins service account and RBAC - SIMPLIFIED
echo "Creating Jenkins service account..."
sudo -u ubuntu kubectl apply -f - <<EOF
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
cat <<EOF > /home/ubuntu/cluster-info.txt
Minikube Cluster Information
===========================

Cluster Name: $CLUSTER_NAME
Environment: $ENVIRONMENT
Setup Date: $(date)

Instance Information:
- Private IP: $PRIVATE_IP
- Public IP: $PUBLIC_IP
- Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)

Minikube Configuration:
- Version: $MINIKUBE_VERSION
- Kubernetes Version: $KUBERNETES_VERSION
- Driver: $MINIKUBE_DRIVER
- Memory: ${MINIKUBE_MEMORY}MB
- CPUs: $MINIKUBE_CPUS

Access Information:
- SSH: ssh -i ${CLUSTER_NAME}-key.pem ubuntu@$PUBLIC_IP
- Kubernetes API: https://$PRIVATE_IP:8443

Useful Commands:
- minikube status
- minikube dashboard --url
- kubectl get nodes
- kubectl get pods --all-namespaces

Setup completed at: $(date)
EOF

chown ubuntu:ubuntu /home/ubuntu/cluster-info.txt

# Create useful scripts
cat <<'EOF' > /home/ubuntu/start-dashboard.sh
#!/bin/bash
echo "Starting Kubernetes Dashboard..."
minikube dashboard --url
EOF

cat <<'EOF' > /home/ubuntu/cluster-health-check.sh
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
EOF

chmod +x /home/ubuntu/start-dashboard.sh
chmod +x /home/ubuntu/cluster-health-check.sh
chown ubuntu:ubuntu /home/ubuntu/start-dashboard.sh
chown ubuntu:ubuntu /home/ubuntu/cluster-health-check.sh

# Create systemd service for Minikube auto-start
cat <<EOF > /etc/systemd/system/minikube.service
[Unit]
Description=Minikube Kubernetes Cluster
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=ubuntu
Group=ubuntu
ExecStart=/usr/local/bin/minikube start --driver=docker
RemainAfterExit=yes
Environment=HOME=/home/ubuntu
Environment=MINIKUBE_HOME=/home/ubuntu/.minikube

[Install]
WantedBy=multi-user.target
EOF

systemctl enable minikube.service

# Final status check and success signal
echo "Performing final health check..."
sudo -u ubuntu bash -c "
    minikube status
    kubectl get nodes
    kubectl get pods -n kube-system
"

# Create success marker file for Terraform to detect
echo "SUCCESS: Minikube cluster is ready" > /tmp/minikube-ready
chown ubuntu:ubuntu /tmp/minikube-ready

echo "✅ Minikube cluster setup completed successfully at $(date)"
echo "🎉 Cluster is ready for deployments!"
echo ""
echo "📋 Next steps:"
echo "1. SSH to instance and run: ./cluster-health-check.sh"
echo "2. Access dashboard: ./start-dashboard.sh"
echo "3. Test deployment: kubectl run test-pod --image=nginx"

echo "Setup script completed successfully!"
echo "Minikube is running and ready to accept connections."
echo "Minikube is running and ready to accept connections."