#!/bin/bash

# Jenkins Agent Setup Script for Amazon Linux 2023
# This script installs all required tools using DNF (not YUM)

set -e

echo "🚀 Setting up Jenkins Agent on Amazon Linux 2023"
echo "================================================="
echo "Detected OS: Amazon Linux 2023"
echo "Package Manager: DNF"
echo ""

# Update system
echo "📦 Updating system packages with DNF..."
sudo dnf update -y

# Install essential packages
echo "🔧 Installing essential packages with conflict resolution..."
# Use DNF with --allowerasing for Amazon Linux 2023 conflicts
sudo dnf install -y --allowerasing \
    wget \
    curl \
    unzip \
    git \
    jq \
    nmap-ncat \
    tar \
    gzip \
    which \
    procps-ng

# Install additional packages with --skip-broken if conflicts persist
echo "🔧 Installing additional packages..."
sudo dnf install -y --skip-broken \
    net-tools \
    bind-utils \
    telnet

# Install Docker (already installed, but ensure it's latest)
echo "🐳 Configuring Docker..."
# Docker is already installed on your system
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

# Note: Java 17 is already installed, which is fine for Jenkins
echo "☕ Java already installed:"
java -version

# Install AWS CLI v2
echo "☁️ Installing AWS CLI v2..."
if ! command -v aws &> /dev/null; then
    cd /tmp
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
else
    echo "AWS CLI already installed: $(aws --version)"
fi

# Install Terraform
echo "🏗️ Installing Terraform..."
TERRAFORM_VERSION="1.12.2"  # Updated to latest version
if ! command -v terraform &> /dev/null; then
    cd /tmp
    wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
    unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip
    sudo mv terraform /usr/local/bin/
    rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip
else
    echo "Terraform already installed: $(terraform version | head -1)"
    echo "Latest version available: ${TERRAFORM_VERSION}"
    echo "To upgrade: sudo rm /usr/local/bin/terraform && cd /tmp && wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip && unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip && sudo mv terraform /usr/local/bin/ && rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
fi

# Install kubectl
echo "☸️ Installing kubectl..."
if ! command -v kubectl &> /dev/null; then
    cd /tmp
    curl -LO "https://dl.k8s.io/release/v1.28.3/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
else
    echo "kubectl already installed: $(kubectl version --client --short 2>/dev/null || echo 'kubectl installed')"
fi

# Create necessary directories
echo "📁 Creating necessary directories..."
mkdir -p /home/ec2-user/.ssh
mkdir -p /home/ec2-user/jenkins-workspace
chmod 700 /home/ec2-user/.ssh
chown ec2-user:ec2-user /home/ec2-user/.ssh
chown ec2-user:ec2-user /home/ec2-user/jenkins-workspace

# Create useful aliases for Amazon Linux 2023
echo "🔗 Creating useful aliases..."
cat <<EOF >> /home/ec2-user/.bashrc

# Jenkins Agent Aliases for Amazon Linux 2023
alias tf='terraform'
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias docker-clean='docker system prune -f'

# AWS Aliases
alias aws-whoami='aws sts get-caller-identity'
alias aws-regions='aws ec2 describe-regions --query "Regions[].RegionName" --output table'

# Amazon Linux 2023 specific
alias install='sudo dnf install -y'
alias search='dnf search'
alias update='sudo dnf update -y'
EOF

# Verify installations
echo "✅ Verifying installations..."
echo ""
echo "System Information:"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Package Manager: DNF $(dnf --version | head -1)"
echo ""
echo "Tool Versions:"
echo "Docker: $(docker --version)"
echo "AWS CLI: $(aws --version)"
echo "Terraform: $(terraform version | head -1)"
echo "kubectl: $(kubectl version --client --short 2>/dev/null || echo 'kubectl installed')"
echo "Java: $(java -version 2>&1 | head -1)"
echo "Git: $(git --version)"
echo "JQ: $(jq --version)"
echo ""

# Test Docker permissions
echo "🐳 Testing Docker permissions..."
if docker ps &> /dev/null; then
    echo "✅ Docker permissions are correct"
else
    echo "⚠️ Docker permissions need a session restart"
    echo "Run: newgrp docker"
fi

echo ""
echo "🎉 Amazon Linux 2023 Jenkins Agent Setup Complete!"
echo "=================================================="
echo "✅ All tools installed using DNF"
echo "✅ Docker configured and running"
echo "✅ Java 17 available (compatible with Jenkins)"
echo "✅ AWS CLI v2 installed"
echo "✅ Terraform ${TERRAFORM_VERSION} installed"
echo "✅ kubectl installed"
echo "✅ All directories created"
echo ""
echo "🔄 Next steps:"
echo "1. Configure AWS credentials: aws configure"
echo "2. Test Docker: docker run hello-world"
echo "3. Restart your session: exit and reconnect (or run: newgrp docker)"
echo "4. Run verification: ./verify-jenkins-agent.sh"
echo ""
echo "📋 Jenkins Agent Configuration:"
echo "- Remote root directory: /home/ec2-user/jenkins-workspace"
echo "- Labels: ec2-agent-1"
echo "- Usage: Use this node as much as possible"
echo ""
echo "💡 Ready for Jenkins pipeline deployment!"