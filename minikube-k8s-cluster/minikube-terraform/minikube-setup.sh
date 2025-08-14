#!/bin/bash

# Minikube Setup Script for AWS EC2
# This script installs and configures Minikube with Docker driver

set -e

# Logging
exec > >(tee /var/log/minikube-setup.log)
exec 2>&1

echo "Starting Minikube setup at $(date)"

# Variables from Terraform
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

# Update system
echo "Updating system packages..."
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
sudo -u ubuntu bash <<EOF
set -e

# Set environment variables
export MINIKUBE_HOME=/home/ubuntu/.minikube
export KUBECONFIG=/home/ubuntu/.kube/config

# Create directories
mkdir -p /home/ubuntu/.minikube
mkdir -p /home/ubuntu/.kube

# Start Minikube
minikube start \
    --driver=$MINIKUBE_DRIVER \
    --memory=$MINIKUBE_MEMORY \
    --cpus=$MINIKUBE_CPUS \
    --kubernetes-version=$KUBERNETES_VERSION \
    --apiserver-ips=$PRIVATE_IP,$PUBLIC_IP \
    --apiserver-name=$CLUSTER_NAME \
    --embed-certs \
    --delete-on-failure

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Enable addons
echo "Enabling Minikube addons..."
minikube addons enable dashboard
minikube addons enable metrics-server  
minikube addons enable ingress
minikube addons enable registry

# Wait for addon pods to be ready
echo "Waiting for addon pods to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/kubernetes-dashboard -n kubernetes-dashboard || true
kubectl wait --for=condition=available --timeout=300s deployment/metrics-server -n kube-system || true

# Create namespace for applications
kubectl create namespace default || true

# Get cluster status
echo "Checking cluster status..."
minikube status
kubectl get nodes -o wide
kubectl get pods --all-namespaces

EOF

# Create Jenkins service account and RBAC
echo "Creating Jenkins service account..."
sudo -u ubuntu kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-deployer
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: jenkins-deployer
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-deployer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: jenkins-deployer
subjects:
- kind: ServiceAccount
  name: jenkins-deployer
  namespace: default
---
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-deployer-token
  namespace: default
  annotations:
    kubernetes.io/service-account.name: jenkins-deployer
type: kubernetes.io/service-account-token
EOF

# Wait for secret to be created
sleep 10

# Create kubeconfig for Jenkins
echo "Creating Jenkins kubeconfig..."
sudo -u ubuntu bash <<EOF
set -e

# Get token and cluster info
TOKEN=\$(kubectl get secret jenkins-deployer-token -o jsonpath='{.data.token}' | base64 -d)
CLUSTER_ENDPOINT="https://$PUBLIC_IP:8443"
CLUSTER_CA=\$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# Create kubeconfig for Jenkins
cat <<EOL > /home/ubuntu/jenkins-kubeconfig.yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: \$CLUSTER_CA
    server: \$CLUSTER_ENDPOINT
  name: $CLUSTER_NAME
contexts:
- context:
    cluster: $CLUSTER_NAME
    user: jenkins-deployer
  name: jenkins-deployer@$CLUSTER_NAME
current-context: jenkins-deployer@$CLUSTER_NAME
users:
- name: jenkins-deployer
  user:
    token: \$TOKEN
EOL

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
- SSH: ssh -i ${cluster_name}-key.pem ubuntu@$PUBLIC_IP
- Kubernetes API: https://$PUBLIC_IP:8443
- Dashboard: Run 'minikube dashboard --url' on the instance

Files Created:
- /home/ubuntu/jenkins-kubeconfig.yaml (Upload to Jenkins)
- /home/ubuntu/cluster-info.txt (This file)

Useful Commands:
- minikube status
- minikube dashboard --url
- kubectl get nodes
- kubectl get pods --all-namespaces

Access Dashboard:
1. SSH to instance: ssh -i ${cluster_name}-key.pem ubuntu@$PUBLIC_IP
2. Run: minikube dashboard --url
3. Set up port forwarding: kubectl proxy --address='0.0.0.0' --port=8080 --accept-hosts='.*'

Setup completed at: $(date)
EOF

chown ubuntu:ubuntu /home/ubuntu/cluster-info.txt
chown ubuntu:ubuntu /home/ubuntu/jenkins-kubeconfig.yaml

# Create useful scripts
cat <<'EOF' > /home/ubuntu/start-dashboard.sh
#!/bin/bash
echo "Starting Kubernetes Dashboard..."
minikube dashboard --url &
sleep 5
echo "Setting up kubectl proxy for external access..."
kubectl proxy --address='0.0.0.0' --port=8080 --accept-hosts='.*'
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
kubectl get nodes -o wide
echo ""
echo "System Pods:"
kubectl get pods -n kube-system
echo ""
echo "Dashboard Pods:"
kubectl get pods -n kubernetes-dashboard
echo ""
echo "Services:"
kubectl get svc --all-namespaces
echo ""
echo "Ingress Controller:"
kubectl get pods -n ingress-nginx
EOF

chmod +x /home/ubuntu/start-dashboard.sh
chmod +x /home/ubuntu/cluster-health-check.sh
chown ubuntu:ubuntu /home/ubuntu/start-dashboard.sh
chown ubuntu:ubuntu /home/ubuntu/cluster-health-check.sh

# Configure automatic Minikube start on boot
cat <<EOF > /etc/systemd/system/minikube.service
[Unit]
Description=Minikube Kubernetes Cluster
After=docker.service
Requires=docker.service

[Service]
Type=forking
User=ubuntu
ExecStart=/usr/local/bin/minikube start --driver=$MINIKUBE_DRIVER
ExecStop=/usr/local/bin/minikube stop
RemainAfterExit=yes
Environment=HOME=/home/ubuntu

[Install]
WantedBy=multi-user.target
EOF

systemctl enable minikube.service

# Final status check
echo "Final cluster status check..."
sudo -u ubuntu minikube status
sudo -u ubuntu kubectl get all --all-namespaces

echo "✅ Minikube cluster setup completed successfully at $(date)"
echo "🎉 Cluster is ready for deployments!"
echo ""
echo "📋 Next steps:"
echo "1. Upload jenkins-kubeconfig.yaml to Jenkins"
echo "2. SSH to instance and run: ./cluster-health-check.sh"
echo "3. Access dashboard: ./start-dashboard.sh"
echo "4. Test deployment: kubectl run test-pod --image=nginx"

echo "Setup script completed successfully!"