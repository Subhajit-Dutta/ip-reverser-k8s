#!/bin/bash

# Jenkins Agent Verification Script for Amazon Linux 2
# Run this script to verify your agent is ready for the Minikube pipeline

echo "🔍 Jenkins Agent Verification Script"
echo "===================================="
echo "Agent: $(hostname)"
echo "Date: $(date)"
echo "User: $(whoami)"
echo ""

# Function to check command
check_command() {
    local cmd=$1
    local name=$2
    if command -v $cmd &> /dev/null; then
        echo "✅ $name: Available"
        case $cmd in
            terraform)
                terraform version | head -1
                ;;
            aws)
                aws --version
                ;;
            kubectl)
                kubectl version --client --short 2>/dev/null || echo "  kubectl client installed"
                ;;
            docker)
                docker --version
                echo "  Docker status: $(sudo systemctl is-active docker)"
                ;;
            java)
                java -version 2>&1 | head -1
                ;;
            git)
                git --version
                ;;
            *)
                $cmd --version 2>/dev/null || $cmd -v 2>/dev/null || echo "  Command available"
                ;;
        esac
    else
        echo "❌ $name: Not found"
        return 1
    fi
    echo ""
}

# Function to check directory permissions
check_directory() {
    local dir=$1
    local name=$2
    if [ -d "$dir" ]; then
        echo "✅ $name: $dir exists"
        echo "  Permissions: $(ls -ld $dir | awk '{print $1, $3, $4}')"
        echo "  Available space: $(df -h $dir | tail -1 | awk '{print $4}')"
    else
        echo "❌ $name: $dir does not exist"
        return 1
    fi
    echo ""
}

# Function to check AWS credentials
check_aws_credentials() {
    echo "🔐 Checking AWS Credentials:"
    if aws sts get-caller-identity &> /dev/null; then
        echo "✅ AWS credentials are configured"
        echo "  Account: $(aws sts get-caller-identity --query Account --output text)"
        echo "  User/Role: $(aws sts get-caller-identity --query Arn --output text)"
    else
        echo "❌ AWS credentials not configured or invalid"
        echo "  Run: aws configure"
        return 1
    fi
    echo ""
}

# Function to check Docker
check_docker() {
    echo "🐳 Checking Docker:"
    if sudo systemctl is-active docker &> /dev/null; then
        echo "✅ Docker service is running"
        
        # Check if current user can run docker
        if docker ps &> /dev/null; then
            echo "✅ Current user can run Docker commands"
        else
            echo "⚠️  Current user cannot run Docker commands"
            echo "  Solution: sudo usermod -aG docker $(whoami) && newgrp docker"
        fi
        
        # Check Docker version
        docker --version
    else
        echo "❌ Docker service is not running"
        echo "  Solution: sudo systemctl start docker && sudo systemctl enable docker"
        return 1
    fi
    echo ""
}

# Function to check network connectivity
check_network() {
    echo "🌐 Checking Network Connectivity:"
    
    # Check internet connectivity
    if curl -s --connect-timeout 5 https://www.google.com > /dev/null; then
        echo "✅ Internet connectivity: Available"
    else
        echo "❌ Internet connectivity: Failed"
        return 1
    fi
    
    # Check AWS API connectivity
    if curl -s --connect-timeout 5 https://sts.amazonaws.com > /dev/null; then
        echo "✅ AWS API connectivity: Available"
    else
        echo "❌ AWS API connectivity: Failed"
        return 1
    fi
    
    # Check Docker Hub connectivity
    if curl -s --connect-timeout 5 https://registry-1.docker.io > /dev/null; then
        echo "✅ Docker Hub connectivity: Available"
    else
        echo "❌ Docker Hub connectivity: Failed"
        return 1
    fi
    
    echo ""
}

# Main verification
echo "📦 Checking Required Tools:"
echo "=========================="

TOOLS_OK=true

check_command terraform "Terraform" || TOOLS_OK=false
check_command aws "AWS CLI" || TOOLS_OK=false
check_command kubectl "kubectl" || TOOLS_OK=false
check_command docker "Docker" || TOOLS_OK=false
check_command java "Java" || TOOLS_OK=false
check_command git "Git" || TOOLS_OK=false
check_command curl "curl" || TOOLS_OK=false
check_command unzip "unzip" || TOOLS_OK=false
check_command jq "jq" || TOOLS_OK=false

echo "📁 Checking Directories:"
echo "======================="

DIRS_OK=true

check_directory "/home/ec2-user" "Home Directory" || DIRS_OK=false
check_directory "/home/ec2-user/.ssh" "SSH Directory" || DIRS_OK=false
check_directory "/usr/local/bin" "Local Bin Directory" || DIRS_OK=false

# Check workspace directory (will be created by Jenkins)
if [ ! -d "/home/ec2-user/jenkins-workspace" ]; then
    echo "📁 Creating jenkins-workspace directory..."
    mkdir -p /home/ec2-user/jenkins-workspace
    check_directory "/home/ec2-user/jenkins-workspace" "Jenkins Workspace" || DIRS_OK=false
fi

echo "🔧 Checking Services:"
echo "==================="

SERVICES_OK=true

check_docker || SERVICES_OK=false

echo "🔐 Checking Credentials:"
echo "======================="

CREDS_OK=true

check_aws_credentials || CREDS_OK=false

echo "🌐 Checking Network:"
echo "=================="

NETWORK_OK=true

check_network || NETWORK_OK=false

echo "📊 System Information:"
echo "===================="

echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo "CPU: $(nproc) cores"
echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
echo "Disk Space: $(df -h / | tail -1 | awk '{print $4}') available"
echo "Uptime: $(uptime -p)"
echo ""

echo "🎯 Jenkins Agent Readiness Summary:"
echo "=================================="

if [ "$TOOLS_OK" = true ]; then
    echo "✅ All required tools are installed"
else
    echo "❌ Some tools are missing - run setup script"
fi

if [ "$DIRS_OK" = true ]; then
    echo "✅ All required directories exist with proper permissions"
else
    echo "❌ Some directories are missing or have wrong permissions"
fi

if [ "$SERVICES_OK" = true ]; then
    echo "✅ All required services are running"
else
    echo "❌ Some services need attention"
fi

if [ "$CREDS_OK" = true ]; then
    echo "✅ AWS credentials are properly configured"
else
    echo "❌ AWS credentials need configuration"
fi

if [ "$NETWORK_OK" = true ]; then
    echo "✅ Network connectivity is working"
else
    echo "❌ Network connectivity issues detected"
fi

echo ""

if [ "$TOOLS_OK" = true ] && [ "$DIRS_OK" = true ] && [ "$SERVICES_OK" = true ] && [ "$CREDS_OK" = true ] && [ "$NETWORK_OK" = true ]; then
    echo "🎉 AGENT IS READY!"
    echo "=================="
    echo "✅ Your Jenkins agent is ready for the Minikube pipeline"
    echo "✅ You can now run the Jenkins pipeline job"
    echo ""
    echo "📋 Next Steps:"
    echo "1. Connect this agent to your Jenkins master"
    echo "2. Label the agent as 'ec2-agent-1' (or update Jenkinsfile)"
    echo "3. Run the Minikube pipeline with DEPLOY_CLUSTER=true"
    echo ""
    echo "🔗 Agent Connection Commands:"
    echo "   Label: ec2-agent-1"
    echo "   Remote root directory: /home/ec2-user/jenkins-workspace"
    echo "   Usage: Use this node as much as possible"
else
    echo "❌ AGENT NEEDS SETUP!"
    echo "===================="
    echo "⚠️  Your Jenkins agent is not ready yet"
    echo ""
    echo "🔧 Required Actions:"
    
    if [ "$TOOLS_OK" = false ]; then
        echo "• Install missing tools: run setup-jenkins-agent-amazon-linux.sh"
    fi
    
    if [ "$DIRS_OK" = false ]; then
        echo "• Fix directory permissions: check ownership and create missing dirs"
    fi
    
    if [ "$SERVICES_OK" = false ]; then
        echo "• Start required services: sudo systemctl start docker"
        echo "• Add user to docker group: sudo usermod -aG docker ec2-user"
    fi
    
    if [ "$CREDS_OK" = false ]; then
        echo "• Configure AWS credentials: aws configure"
        echo "• Or use IAM role attached to EC2 instance"
    fi
    
    if [ "$NETWORK_OK" = false ]; then
        echo "• Check security groups allow outbound HTTPS"
        echo "• Verify internet gateway and routing"
    fi
    
    echo ""
    echo "📝 Setup Script:"
    echo "curl -O https://your-repo/setup-jenkins-agent-amazon-linux.sh"
    echo "chmod +x setup-jenkins-agent-amazon-linux.sh"
    echo "./setup-jenkins-agent-amazon-linux.sh"
fi

echo ""
echo "📄 Verification completed at: $(date)"
echo "🖥️  Agent: $(hostname) ($(whoami))"