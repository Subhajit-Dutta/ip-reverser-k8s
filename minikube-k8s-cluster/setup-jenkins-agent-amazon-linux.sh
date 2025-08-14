#!/bin/bash

# Jenkins Agent Setup Script for Amazon Linux 2
# This script installs all required tools for the Minikube pipeline

set -e

echo "🚀 Setting up Jenkins Agent on Amazon Linux 2"
echo "============================================="

# Update system
echo "📦 Updating system packages..."
sudo yum update -y

# Install essential packages
echo "🔧 Installing essential packages..."
sudo yum install -y \
    wget \
    curl \
    unzip \
    git \
    jq \
    nc \
    tar \
    gzip

# Install Docker (for Jenkins Docker operations)
echo "🐳 Installing Docker..."
sudo yum install -y docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user
sudo usermod -aG docker jenkins  # If jenkins user exists

# Install Java (required for Jenkins agent)
echo "☕ Installing Java..."
sudo yum install -y java-11-amazon-corretto

# Install AWS CLI v2
echo "☁️ Installing AWS CLI v2..."
if ! command -v aws &> /dev/null; then
    cd /tmp
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
fi

# Install Terraform
echo "🏗️ Installing Terraform..."
TERRAFORM_VERSION="1.6.0"
if ! command -v terraform &> /dev/null; then
    cd /tmp
    wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
    unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip
    sudo mv terraform /usr/local/bin/
    rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip
fi

# Install kubectl
echo "☸️ Installing kubectl..."
if ! command -v kubectl &> /dev/null; then
    cd /tmp
    curl -LO "https://dl.k8s.io/release/v1.28.3/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
fi

# Create necessary directories
echo "📁 Creating necessary directories..."
sudo mkdir -p /opt/jenkins
sudo chown ec2-user:ec2-user /opt/jenkins

# Create workspace directory
mkdir -p /home/ec2-user/jenkins-workspace
sudo chown ec2-user:ec2-user /home/ec2-user/jenkins-workspace

# Verify installations
echo "✅ Verifying installations..."
echo "Docker version: $(docker --version)"
echo "AWS CLI version: $(aws --version)"
echo "Terraform version: $(terraform version)"
echo "kubectl version: $(kubectl version --client --short)"
echo "Java version: $(java -version 2>&1 | head -n 1)"

# Create useful aliases
echo "🔗 Creating useful aliases..."
cat <<EOF >> /home/ec2-user/.bashrc

# Jenkins Agent Aliases
alias tf='terraform'
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias docker-clean='docker system prune -f'

# AWS Aliases
alias aws-whoami='aws sts get-caller-identity'
alias aws-regions='aws ec2 describe-regions --query "Regions[].RegionName" --output table'
EOF

# Set up SSH key directory
echo "🔑 Setting up SSH key directory..."
mkdir -p /home/ec2-user/.ssh
chmod 700 /home/ec2-user/.ssh
chown ec2-user:ec2-user /home/ec2-user/.ssh

echo ""
echo "🎉 Jenkins Agent Setup Complete!"
echo "================================"
echo "✅ Docker installed and configured"
echo "✅ AWS CLI v2 installed"
echo "✅ Terraform ${TERRAFORM_VERSION} installed"
echo "✅ kubectl installed"
echo "✅ Java 11 installed"
echo "✅ All directories created"
echo ""
echo "🔄 Please restart your session or run: source ~/.bashrc"
echo "🔐 Remember to configure AWS credentials on this agent"
echo ""
echo "📋 Next steps:"
echo "1. Configure AWS credentials: aws configure"
echo "2. Test Docker: docker run hello-world"
echo "3. Test Terraform: terraform version"
echo "4. Connect this node to Jenkins master"
echo ""
echo "💡 For Jenkins agent connection, you may need to:"
echo "   - Install Jenkins agent.jar"
echo "   - Configure the agent in Jenkins UI"
echo "   - Start the agent service"