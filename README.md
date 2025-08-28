# IP Reverser Application Deployment Pipeline

🚀 **CI/CD Pipeline for Kubernetes Application Deployment**

This Jenkins pipeline automates the complete CI/CD workflow for the IP Reverser application, from source code to production deployment on Minikube clusters.

## 📋 Overview

This pipeline provides a comprehensive CI/CD solution featuring:

- **Automated Build & Test**: Docker image creation with application testing
- **Security Scanning**: Trivy vulnerability assessment
- **Registry Management**: Automated Docker Hub publishing
- **Remote Deployment**: Secure deployment to Minikube clusters
- **Health Verification**: Comprehensive smoke testing

## 🏗️ Architecture

```
Source Code → Docker Build → Security Scan → Registry Push → Remote Deploy → Smoke Test
     ↓              ↓              ↓              ↓              ↓            ↓
   GitHub      Docker Image    Trivy Scan    Docker Hub     Minikube    Health Check
```

## 🔧 Prerequisites

### Jenkins Setup
1. **Agent Configuration**: Label Jenkins agent as `ec2-agent-1`
2. **Required Tools** (auto-installed by pipeline):
   - Docker
   - kubectl
   - Trivy security scanner
   - Git, curl, wget



2. **SSH Private Key** for Minikube access:
   - File-based private key for connecting to Minikube instance
   - Must be accessible on Jenkins agent

### Repository Structure
```
├── app.py                 # Python Flask application
├── requirements.txt       # Python dependencies
├── Dockerfile            # Container build instructions
├── k8s-deployment.yaml   # Kubernetes deployment manifest
└── Jenkinsfile          # Pipeline definition
```

## 📝 Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `SSH_KEY_FILE_PATH` | String | Required | 🔐 Full path to SSH private key file |
| `MINIKUBE_PUBLIC_IP` | String | Required | 🌐 Minikube EC2 instance public IP |
| `SSH_USER` | String | ubuntu | 👤 SSH user for Minikube instance |
| `SSH_KEY_CREDENTIAL` | String | minikube-ssh-key | 🔑 Jenkins credential ID for SSH key |
| `NODEPORT_SERVICE_PORT` | String | 30080 | 🔌 NodePort service port |
| `SKIP_TESTS` | Boolean | false | ⚡ Skip application tests |
| `SKIP_SECURITY_SCAN` | Boolean | false | 🔒 Skip security scanning |
| `FORCE_REBUILD` | Boolean | false | 🔨 Force rebuild Docker image |



### Quick Development Build
For rapid iteration during development:
```
SKIP_TESTS: true
SKIP_SECURITY_SCAN: true
FORCE_REBUILD: true
```

## 📂 Pipeline Stages

### 1. 🔍 Environment Validation
- Validates all input parameters
- Checks IP address format
- Verifies configuration consistency

### 2. 📥 Checkout
- Retrieves source code from repository
- Generates Git commit hash for image tagging
- Sets up build environment

### 3. 📁 Validate Files
- Ensures all required files are present:
  - `app.py` - Main application
  - `requirements.txt` - Dependencies
  - `Dockerfile` - Container build
  - `k8s-deployment.yaml` - Kubernetes manifest

### 4. 🔗 Test Minikube Connection
- Validates SSH key file existence and format
- Tests network connectivity to Minikube instance
- Verifies SSH authentication
- Checks Minikube and kubectl status

### 5. 🔨 Build Docker Image
- Creates Docker image with build number and Git commit tags
- Tags as both versioned and latest
- Verifies successful build

### 6. 🧪 Test Application *(Optional)*
- Starts container locally for testing
- Tests health endpoint (`/health`)
- Tests main application endpoint (`/`)
- Automatic cleanup after testing

### 7. 🔒 Security Scan *(Optional)*
- Installs Trivy scanner if not present
- Scans Docker image for HIGH/CRITICAL vulnerabilities
- Reports security findings

### 8. 📤 Push to Registry
- Authenticates with Docker Hub
- Pushes both versioned and latest tags
- Secure credential handling

### 9. 🚀 Deploy to Minikube
- Copies deployment manifest to remote instance
- Updates image references with new tag
- Applies Kubernetes deployment
- Waits for rollout completion
- Verifies deployment status

### 10. 💨 Smoke Test
- Tests application internally via Minikube service URL
- Attempts external access via NodePort
- Validates application functionality

## 🏷️ Image Tagging Strategy

Each build creates two Docker images:
- **Versioned**: `{BUILD_NUMBER}-{GIT_COMMIT_SHORT}`
  - Example: `42-a1b2c3d4e5f6`
- **Latest**: `latest`
  - Always points to most recent build

## 🌐 Application Access

After successful deployment, access your application via:

### NodePort Access (External)
```bash
curl http://<MINIKUBE_PUBLIC_IP>:30080
```

### SSH Access (Internal)
```bash
# SSH to Minikube instance
ssh -i /path/to/key.pem ubuntu@<MINIKUBE_PUBLIC_IP>

# Get internal service URL
minikube service ip-reverse-app-service --url -n default

# Test application
curl $(minikube service ip-reverse-app-service --url -n default)
```

## 🔍 Monitoring & Debugging

### Check Deployment Status
```bash
# SSH to Minikube instance
ssh -i /path/to/key.pem ubuntu@<MINIKUBE_PUBLIC_IP>

# Check pods
kubectl get pods -n default -l app=ip-reverse-app

# Check services
kubectl get services -n default -l app=ip-reverse-app

# View logs
kubectl logs -n default -l app=ip-reverse-app

# Describe deployment
kubectl describe deployment ip-reverse-app -n default
```

### Common kubectl Commands
```bash
# Get all resources
kubectl get all -n default -l app=ip-reverse-app

# Check events
kubectl get events -n default --sort-by='.lastTimestamp'

# Scale deployment
kubectl scale deployment ip-reverse-app --replicas=3 -n default

# Update image
kubectl set image deployment/ip-reverse-app ip-reverse-app=subhajitdutta/ip-reverse-app:latest -n default
```

## 🐛 Troubleshooting

### Common Issues & Solutions

**1. SSH Connection Failed**
```bash
# Check SSH key permissions
chmod 600 /path/to/your/key.pem

# Test SSH connection manually
ssh -i /path/to/your/key.pem ubuntu@<IP> "echo 'Connection successful'"

# Try different SSH user
ssh -i /path/to/your/key.pem ec2-user@<IP>
```

**2. Docker Push Failed**
- Verify Docker Hub credentials in Jenkins
- Check credential ID matches pipeline configuration
- Ensure Docker Hub access token has push permissions

**3. Deployment Failed**
```bash
# Check Minikube status
minikube status

# Check cluster resources
kubectl get nodes
kubectl top nodes

# Check deployment events
kubectl describe deployment ip-reverse-app -n default
```

**4. Application Not Accessible**
```bash
# Check service configuration
kubectl get svc ip-reverse-app-service -n default -o yaml

# Check security groups (AWS)
# Ensure port 30080 is open for NodePort access

# Check pod logs
kubectl logs -n default -l app=ip-reverse-app
```

### Debug Commands

**Pipeline Debug**
```bash
# Check workspace
ls -la ${WORKSPACE}

# Check Docker images
docker images | grep ip-reverse-app

# Check running containers
docker ps
```

**Kubernetes Debug**
```bash
# Get detailed pod information
kubectl get pods -n default -l app=ip-reverse-app -o wide

# Check resource usage
kubectl top pods -n default

# Get pod YAML
kubectl get pod <POD_NAME> -n default -o yaml

# Execute into pod
kubectl exec -it <POD_NAME> -n default -- /bin/sh
```

#
## 📊 Pipeline Metrics

The pipeline provides comprehensive feedback:

**Build Information**:
- Build number and Git commit hash
- Image tags and registry locations
- Deployment targets and configurations

**Quality Gates**:
- Application test results
- Security scan findings
- Deployment health checks

**Access Information**:
- Service URLs and endpoints
- SSH commands for debugging
- kubectl commands for management
