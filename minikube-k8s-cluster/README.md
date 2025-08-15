# Minikube Infrastructure Pipeline

🚀 **Automated Minikube Cluster Deployment on AWS EC2**

This Jenkins pipeline automates the deployment and destruction of Minikube clusters on AWS EC2 instances using Terraform and IAM roles for secure, credential-free operations.

## 📋 Overview

This pipeline provides a complete infrastructure-as-code solution for managing Minikube clusters in AWS, featuring:

- **Secure Deployment**: Uses IAM roles instead of hardcoded credentials
- **Terraform State Management**: S3 backend with DynamoDB locking
- **Auto-Generated SSH Keys**: No manual key management required
- **Comprehensive Health Checks**: Validates cluster functionality
- **Clean Teardown**: Complete resource cleanup on destruction

## 🏗️ Architecture

```
Jenkins Agent (EC2) → Terraform → AWS Resources
├── VPC & Security Groups
├── EC2 Instance (Ubuntu)
├── Auto-generated SSH Key Pair
├── Minikube Installation
└── Kubernetes Cluster Setup
```


   ```

### Jenkins Setup
1. **Agent Configuration**: Label the Jenkins agent as `ec2-agent-1`
2. **Required Tools** (auto-installed by pipeline):
   - Terraform 1.12.2
   - AWS CLI v2
   - kubectl
   - Standard Linux utilities (git, curl, wget, jq, unzip)

## 📝 Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `DEPLOY_CLUSTER` | Boolean | false | 🚀 Deploy new Minikube cluster |
| `DESTROY_CLUSTER` | Boolean | false | 🔥 Destroy existing cluster |
| `INSTANCE_TYPE` | Choice | t3.medium | EC2 instance type |
| `AWS_REGION` | Choice | us-west-2 | AWS deployment region |
| `CLUSTER_NAME` | String | minikube-demo | Cluster identifier |
| `MINIKUBE_VERSION` | String | v1.32.0 | Minikube version |
| `KUBERNETES_VERSION` | String | v1.28.3 | Kubernetes version |
| `MINIKUBE_MEMORY` | Choice | 3900 | Memory allocation (MB) |
| `MINIKUBE_CPUS` | Choice | 2 | CPU allocation |
| `ENABLE_DASHBOARD` | Boolean | true | Enable Kubernetes Dashboard |
| `ENABLE_INGRESS` | Boolean | true | Enable Ingress Controller |
| `ENABLE_REGISTRY` | Boolean | true | Enable Local Registry |

## 🚀 Usage

### Deploying a Cluster

1. **Navigate** to Jenkins pipeline
2. **Click** "Build with Parameters"
3. **Configure** parameters:
   - Set `DEPLOY_CLUSTER = true`
   - Choose your `INSTANCE_TYPE` and `AWS_REGION`
   - Customize `CLUSTER_NAME` if needed
4. **Review** Terraform plan when prompted
5. **Approve** deployment to proceed

### Destroying a Cluster

1. **Navigate** to Jenkins pipeline
2. **Click** "Build with Parameters"
3. **Configure** parameters:
   - Set `DESTROY_CLUSTER = true`
   - Use same `CLUSTER_NAME` and `AWS_REGION` as deployment
4. **Review** destroy plan when prompted
5. **Type "DESTROY"** in confirmation field
6. **Approve** to proceed with destruction

## 📂 Pipeline Stages

### 1. 🧹 Clean Workspace
- Removes all previous build artifacts
- Ensures fresh start for each run

### 2. 🔍 Agent Info & IAM Verification
- Validates Jenkins agent environment
- Confirms IAM role configuration
- Tests AWS permissions

### 3. ✅ Validation
- Validates input parameters
- Prevents conflicting operations
- Sets environment variables

### 4. 📥 Checkout
- Retrieves source code from repository
- Accesses Terraform configurations

### 5. 🔧 Verify Dependencies
- Installs required tools automatically
- Supports both Amazon Linux 2 and 2023
- Handles package manager differences (yum/dnf)

### 6. 🗃️ Prepare Infrastructure
- Creates Terraform backend configuration
- Generates terraform.tfvars
- Cleans up any conflicting resources

### 7. 🚀 Deploy Minikube Cluster *(Deploy only)*
- Runs Terraform plan with manual approval
- Applies infrastructure changes
- Creates EC2 instance with Minikube

### 8. ⏳ Wait for Cluster Readiness *(Deploy only)*
- Waits for SSH connectivity
- Monitors Minikube installation progress
- Verifies cluster functionality

### 9. 🔧 Configure Jenkins Access *(Deploy only)*
- Downloads kubeconfig from instance
- Copies SSH private key to workspace
- Creates access information file

### 10. 🔥 Cluster Health Check *(Deploy only)*
- Comprehensive cluster validation
- Tests pod deployment
- Verifies all components

### 11. 🔥 Destroy Cluster *(Destroy only)*
- Runs Terraform destroy plan with approval
- Requires manual confirmation
- Cleans up all AWS resources

## 📁 Generated Files

After successful deployment, the following files are available in the Jenkins workspace:

| File | Description |
|------|-------------|
| `jenkins-kubeconfig.yaml` | Kubernetes configuration for cluster access |
| `cluster-ssh-key.pem` | SSH private key for instance access |
| `cluster-access-info.txt` | Complete access information and commands |

## 🌐 Accessing Your Cluster

### SSH Access
```bash
ssh -i cluster-ssh-key.pem ubuntu@<PUBLIC_IP>
```

### Kubectl Access
```bash
kubectl --kubeconfig=jenkins-kubeconfig.yaml get nodes
kubectl --kubeconfig=jenkins-kubeconfig.yaml get pods --all-namespaces
```

### Dashboard Access
```bash
# SSH to instance first
ssh -i cluster-ssh-key.pem ubuntu@<PUBLIC_IP>

# Start dashboard
minikube dashboard --url
```

## 💰 Cost Considerations

**Estimated Costs** (us-west-2 region):
- **t3.medium**: ~$0.04/hour (~$30/month)
- **t3.large**: ~$0.08/hour (~$60/month)
- **t3.xlarge**: ~$0.17/hour (~$125/month)

> ⚠️ **Remember**: Always destroy clusters when not in use to avoid unnecessary charges!

## 🔒 Security Features

- **No Hardcoded Credentials**: Uses IAM roles exclusively
- **Auto-Generated SSH Keys**: Terraform creates unique key pairs
- **State Encryption**: S3 backend with encryption enabled
- **Least Privilege**: Minimal required IAM permissions
- **Secure Communication**: All SSH connections use auto-generated keys

## 🐛 Troubleshooting

### Common Issues

**1. IAM Permission Denied**
```bash
# Verify IAM role is attached
aws sts get-caller-identity



**3. Resource Quota Exceeded**
- Check AWS service quotas in your region
- Try different instance types or regions
- Contact AWS support for quota increases

**4. Minikube Not Starting**
- Check instance has sufficient resources (minimum t3.medium)
- Verify Docker is running on the instance
- Check system logs: `journalctl -u docker`

### Manual Cleanup

If pipeline fails during destruction, manually check and clean:

```bash
# List EC2 instances
aws ec2 describe-instances --filters "Name=tag:Name,Values=*minikube*"

# List security groups
aws ec2 describe-security-groups --filters "Name=group-name,Values=*minikube*"

# List key pairs
aws ec2 describe-key-pairs --filters "Name=key-name,Values=*minikube*"
```




