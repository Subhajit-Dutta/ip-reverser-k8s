#!/bin/bash

# Amazon Linux Package Conflict Troubleshooter
# This script helps resolve common package conflicts on Amazon Linux

set -e

echo "🔧 Amazon Linux Package Conflict Troubleshooter"
echo "==============================================="

# Function to check and resolve package conflicts
resolve_conflicts() {
    echo "🔍 Checking for package conflicts..."
    
    # Clean yum cache
    echo "🧹 Cleaning yum cache..."
    sudo yum clean all
    
    # Update package database
    echo "📦 Updating package database..."
    sudo yum makecache
    
    # Check for broken dependencies
    echo "🔍 Checking for broken dependencies..."
    sudo package-cleanup --problems || echo "No package-cleanup tool available"
    
    # Try to fix broken packages
    echo "🔧 Attempting to fix broken packages..."
    sudo yum update -y --skip-broken
}

# Function to install packages with multiple fallback strategies
install_with_fallbacks() {
    local package=$1
    local description=$2
    
    echo "📦 Installing $description ($package)..."
    
    # Strategy 1: Normal install
    if sudo yum install -y "$package"; then
        echo "✅ $description installed successfully"
        return 0
    fi
    
    echo "⚠️ Normal install failed, trying with --allowerasing..."
    # Strategy 2: Allow erasing conflicting packages
    if sudo yum install -y --allowerasing "$package"; then
        echo "✅ $description installed with --allowerasing"
        return 0
    fi
    
    echo "⚠️ --allowerasing failed, trying with --skip-broken..."
    # Strategy 3: Skip broken dependencies
    if sudo yum install -y --skip-broken "$package"; then
        echo "✅ $description installed with --skip-broken"
        return 0
    fi
    
    echo "❌ Failed to install $description, will continue without it"
    return 1
}

# Function to check Amazon Linux version
check_amazon_linux_version() {
    echo "🔍 Checking Amazon Linux version..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "OS: $PRETTY_NAME"
        echo "Version: $VERSION_ID"
        
        # Amazon Linux 2 vs Amazon Linux 2023 have different package managers
        if [[ "$VERSION_ID" == "2023" ]]; then
            echo "⚠️ Detected Amazon Linux 2023 - consider using dnf instead of yum"
            echo "Run: sudo dnf install <packages> instead"
            return 2023
        elif [[ "$VERSION_ID" == "2" ]]; then
            echo "✅ Detected Amazon Linux 2 - yum should work fine"
            return 2
        else
            echo "⚠️ Unknown Amazon Linux version"
            return 1
        fi
    else
        echo "❌ Cannot determine Amazon Linux version"
        return 1
    fi
}

# Function to install using dnf for Amazon Linux 2023
install_with_dnf() {
    echo "🔧 Using DNF package manager for Amazon Linux 2023..."
    
    # Update system
    sudo dnf update -y
    
    # Install packages
    sudo dnf install -y \
        wget \
        curl \
        unzip \
        git \
        jq \
        nc \
        tar \
        gzip \
        docker \
        java-11-amazon-corretto \
        which \
        procps-ng
}

# Main troubleshooting flow
main() {
    # Check Amazon Linux version
    check_amazon_linux_version
    AL_VERSION=$?
    
    if [ $AL_VERSION -eq 2023 ]; then
        echo "🚀 Using DNF for Amazon Linux 2023..."
        install_with_dnf
        return 0
    fi
    
    # For Amazon Linux 2, continue with yum troubleshooting
    echo "🚀 Using YUM troubleshooting for Amazon Linux 2..."
    
    # Step 1: Resolve existing conflicts
    resolve_conflicts
    
    # Step 2: Install packages with fallbacks
    echo "📦 Installing essential packages with conflict resolution..."
    
    # Core utilities
    install_with_fallbacks "wget curl unzip git tar gzip which" "Core Utilities"
    
    # Network tools
    install_with_fallbacks "jq" "JSON Processor"
    install_with_fallbacks "nc" "Netcat"
    install_with_fallbacks "net-tools" "Network Tools"
    install_with_fallbacks "bind-utils" "DNS Utils"
    
    # Docker
    install_with_fallbacks "docker" "Docker"
    
    # Java (try multiple versions)
    if ! install_with_fallbacks "java-11-amazon-corretto" "Java 11 Corretto"; then
        if ! install_with_fallbacks "java-11-openjdk" "Java 11 OpenJDK"; then
            install_with_fallbacks "java-1.8.0-openjdk" "Java 8 OpenJDK"
        fi
    fi
    
    # Process tools
    install_with_fallbacks "procps-ng" "Process Tools"
    
    echo "✅ Package installation completed with conflict resolution"
}

# Function to show manual resolution steps
show_manual_steps() {
    echo ""
    echo "🔧 Manual Resolution Steps:"
    echo "=========================="
    echo ""
    echo "If the automatic resolution fails, try these manual steps:"
    echo ""
    echo "1. Check for conflicting packages:"
    echo "   sudo yum check"
    echo "   sudo package-cleanup --problems"
    echo ""
    echo "2. Remove conflicting packages (if safe):"
    echo "   sudo yum remove <conflicting-package>"
    echo ""
    echo "3. Force install with alternatives:"
    echo "   sudo yum install -y --allowerasing <package>"
    echo "   sudo yum install -y --skip-broken <package>"
    echo ""
    echo "4. For Amazon Linux 2023, use DNF:"
    echo "   sudo dnf install -y <package>"
    echo ""
    echo "5. Use alternative repositories:"
    echo "   sudo yum install -y epel-release"
    echo "   sudo yum install -y <package>"
    echo ""
    echo "6. Install from source if package conflicts persist:"
    echo "   # This should be last resort"
    echo ""
    echo "7. Check enabled repositories:"
    echo "   sudo yum repolist"
    echo "   sudo yum-config-manager --disable <problematic-repo>"
    echo ""
}

# Function to check specific common conflicts
check_common_conflicts() {
    echo "🔍 Checking for common Amazon Linux conflicts..."
    
    # Check for multiple Java versions
    echo "☕ Checking Java installations..."
    rpm -qa | grep -i java | sort
    
    # Check for Docker conflicts
    echo "🐳 Checking Docker installations..."
    rpm -qa | grep -i docker | sort
    
    # Check for repository conflicts
    echo "📦 Checking enabled repositories..."
    sudo yum repolist enabled
    
    # Check for locked packages
    echo "🔒 Checking for package locks..."
    sudo yum versionlock list 2>/dev/null || echo "No version locks found"
}

# Run the troubleshooter
echo "Starting Amazon Linux package conflict resolution..."
echo ""

check_common_conflicts
echo ""

main

echo ""
show_manual_steps

echo ""
echo "🎉 Troubleshooting completed!"
echo "If issues persist, check the manual resolution steps above."