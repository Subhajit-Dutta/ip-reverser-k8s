pipeline {
    agent {
        label 'ec2-agent-1'
    }
    
    environment {
        // Docker Registry Configuration
        DOCKER_REGISTRY = 'docker.io'
        DOCKER_REPO = 'subhajitdutta/ip-reverse-app'
        DOCKER_CREDENTIALS_ID = 'dockerhub-creds'
        
        // Application Configuration
        APP_NAME = 'ip-reverse-app'
        APP_PORT = '8080'
        K8S_NAMESPACE = 'default'
        REPLICAS = '2'
        
        // Git Configuration
        GIT_REPO = 'git@github.com:Subhajit-Dutta/ip-reverser-k8s.git'
        GIT_BRANCH = 'master'
        
        // Build Configuration
        BUILD_NUMBER_TAG = "${BUILD_NUMBER}"
        LATEST_TAG = 'latest'
        
        // Minikube Configuration - CONFIGURABLE PARAMETERS
        MINIKUBE_PUBLIC_IP = "${params.MINIKUBE_PUBLIC_IP ?: '52.42.72.58'}"
        SSH_USER = "${params.SSH_USER ?: 'ubuntu'}"
        SSH_KEY_CREDENTIAL = "${params.SSH_KEY_CREDENTIAL ?: 'minikube-ssh-key'}"
        NODEPORT_SERVICE_PORT = "${params.NODEPORT_SERVICE_PORT ?: '30080'}"
        
        // Initialize IMAGE_TAG with safe default
        IMAGE_TAG = "${BUILD_NUMBER}-unknown"
    }
    
    parameters {
        string(
            name: 'MINIKUBE_PUBLIC_IP',
            defaultValue: '52.42.72.58',
            description: '🌐 Minikube EC2 instance public IP address'
        )
        string(
            name: 'SSH_USER',
            defaultValue: 'ubuntu',
            description: '👤 SSH user for Minikube instance'
        )
        string(
            name: 'SSH_KEY_CREDENTIAL',
            defaultValue: 'minikube-ssh-key',
            description: '🔑 Jenkins credential ID for SSH private key (NOT Docker credentials)'
        )
        string(
            name: 'NODEPORT_SERVICE_PORT',
            defaultValue: '30080',
            description: '🔌 NodePort service port for application access'
        )
        booleanParam(
            name: 'SKIP_TESTS',
            defaultValue: false,
            description: '⚡ Skip application tests'
        )
        booleanParam(
            name: 'SKIP_SECURITY_SCAN',
            defaultValue: false,
            description: '🔐 Skip security scan'
        )
        booleanParam(
            name: 'FORCE_REBUILD',
            defaultValue: false,
            description: '🔨 Force rebuild Docker image'
        )
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
    }
    
    stages {
        stage('🔍 Environment Validation') {
            steps {
                echo "🔍 Validating environment and parameters..."
                script {
                    echo "📋 Configuration Summary:"
                    echo "   - Minikube Public IP: ${MINIKUBE_PUBLIC_IP}"
                    echo "   - SSH User: ${SSH_USER}"
                    echo "   - SSH Credential: ${SSH_KEY_CREDENTIAL}"
                    echo "   - NodePort: ${NODEPORT_SERVICE_PORT}"
                    echo "   - Docker Repo: ${DOCKER_REPO}"
                    echo "   - Git Credentials: ${params.GIT_CREDENTIALS_ID}"
                    echo "   - Namespace: ${K8S_NAMESPACE}"
                    
                    // Validate IP format
                    if (!params.MINIKUBE_PUBLIC_IP.matches(/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)) {
                        error("❌ Invalid IP address format: ${params.MINIKUBE_PUBLIC_IP}")
                    }
                    
                    echo "✅ Environment validation completed"
                }
            }
        }
        
        stage('📥 Checkout') {
            steps {
                echo "🔄 Checking out code from repository - ${GIT_BRANCH} branch"
                checkout scm
                
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                    env.IMAGE_TAG = "${BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
                }
                
                echo "📝 Git commit: ${env.GIT_COMMIT_SHORT}"
                echo "🏷️ Image tag: ${env.IMAGE_TAG}"
            }
        }
        
        stage('🔍 Validate Files') {
            steps {
                echo "🔍 Validating required files..."
                script {
                    def requiredFiles = ['app.py', 'requirements.txt', 'Dockerfile', 'k8s-deployment.yaml']
                    requiredFiles.each { file ->
                        if (!fileExists(file)) {
                            error("❌ Required file ${file} not found!")
                        } else {
                            echo "✅ Found ${file}"
                        }
                    }
                }
            }
        }
        
        stage('🔗 Test Minikube Connection') {
            steps {
                echo "🔗 Testing connection to Minikube instance..."
                script {
                    try {
                        sh """
                            echo "🔍 Using hardcoded SSH key path..."
                            SSH_KEY_PATH="/home/ec2-user/jenkins/workspace/Jenkinsfile-Minikube-Amazon-Linux/minikube-k8s-cluster/minikube-terraform/minikube-demo-key.pem"
                            
                            echo "🔐 Checking SSH key file..."
                            if [ -f "\$SSH_KEY_PATH" ]; then
                                echo "✅ SSH key found: \$SSH_KEY_PATH"
                                chmod 600 "\$SSH_KEY_PATH"
                            else
                                echo "❌ SSH key not found at: \$SSH_KEY_PATH"
                                echo "📂 Available files in directory:"
                                ls -la /home/ec2-user/jenkins/workspace/Jenkinsfile-Minikube-Amazon-Linux/minikube-k8s-cluster/minikube-terraform/ || true
                                exit 1
                            fi
                            
                            echo "🔍 Testing SSH connection to ${MINIKUBE_PUBLIC_IP}..."
                            timeout 30 ssh -i "\$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \\
                                ${SSH_USER}@${MINIKUBE_PUBLIC_IP} "
                                echo '✅ SSH connection successful'
                                echo '📋 Instance info:'
                                echo '   - Hostname: \$(hostname)'
                                echo '   - User: \$(whoami)'
                                echo '   - Working directory: \$(pwd)'
                                
                                echo '🔍 Checking Minikube status...'
                                if command -v minikube >/dev/null 2>&1; then
                                    minikube status || echo 'Minikube not running'
                                else
                                    echo 'Minikube command not found'
                                fi
                                
                                echo '🔍 Checking kubectl...'
                                if command -v kubectl >/dev/null 2>&1; then
                                    kubectl cluster-info || echo 'Kubectl not connected'
                                    kubectl get nodes || echo 'No nodes found'
                                else
                                    echo 'Kubectl command not found'
                                fi
                            "
                            
                            echo "✅ Minikube connection test completed"
                        """
                    } catch (Exception e) {
                        echo "❌ SSH Connection failed: ${e.getMessage()}"
                        echo "🔧 Possible issues:"
                        echo "   1. SSH key file not found at hardcoded path"
                        echo "   2. Minikube instance not accessible at ${MINIKUBE_PUBLIC_IP}"
                        echo "   3. Security group doesn't allow SSH from Jenkins instance"
                        echo "   4. Wrong SSH user (currently using: ${SSH_USER})"
                        echo ""
                        echo "⚠️ Continuing pipeline - but deployment will likely fail"
                        
                        // Mark build as unstable but continue
                        currentBuild.result = 'UNSTABLE'
                    }
                }
            }
        }
        
        stage('🔨 Build Docker Image') {
            steps {
                echo "🔨 Building Docker image..."
                script {
                    sh """
                        echo "📋 Build Information:"
                        echo "   - Repository: ${DOCKER_REPO}"
                        echo "   - Image Tag: ${env.IMAGE_TAG}"
                        echo "   - Latest Tag: ${LATEST_TAG}"
                        echo "   - Git Commit: ${env.GIT_COMMIT_SHORT}"
                        
                        # Verify Docker is accessible
                        echo "🐳 Docker version:"
                        docker --version
                        
                        echo "🔨 Building Docker image..."
                        docker build -t ${DOCKER_REPO}:${env.IMAGE_TAG} .
                        docker tag ${DOCKER_REPO}:${env.IMAGE_TAG} ${DOCKER_REPO}:${LATEST_TAG}
                        
                        echo "📊 Verifying built images:"
                        docker images ${DOCKER_REPO}
                    """
                    echo "✅ Docker image built successfully"
                }
            }
        }
        
        stage('🧪 Test Application') {
            when {
                not { 
                    expression { params.SKIP_TESTS == true }
                }
            }
            steps {
                echo "🧪 Testing application..."
                script {
                    sh """
                        # Start container in background
                        docker run -d --name test-${BUILD_NUMBER} -p 8081:8080 ${DOCKER_REPO}:${env.IMAGE_TAG}
                        
                        # Wait for application to start
                        echo "⏳ Waiting for application to start..."
                        sleep 10
                        
                        # Test health endpoint
                        echo "🏥 Testing health endpoint..."
                        curl -f http://localhost:8081/health || exit 1
                        
                        # Test main endpoint
                        echo "🌐 Testing main endpoint..."
                        curl -f http://localhost:8081/ || exit 1
                        
                        echo "✅ Application tests passed"
                    """
                }
            }
            post {
                always {
                    sh """
                        docker stop test-${BUILD_NUMBER} || true
                        docker rm test-${BUILD_NUMBER} || true
                    """
                }
            }
        }
        
        stage('🔐 Security Scan') {
            when {
                not { 
                    expression { params.SKIP_SECURITY_SCAN == true }
                }
            }
            steps {
                echo "🔐 Running security scan..."
                script {
                    try {
                        sh """
                            if command -v trivy >/dev/null 2>&1; then
                                echo "📊 Running Trivy security scan..."
                                trivy image --exit-code 0 --severity HIGH,CRITICAL ${DOCKER_REPO}:${env.IMAGE_TAG}
                            else
                                echo "⚠️ Trivy not installed, skipping security scan"
                            fi
                        """
                    } catch (Exception e) {
                        echo "⚠️ Security scan failed but continuing: ${e.getMessage()}"
                    }
                }
            }
        }
        
        stage('📤 Push to Registry') {
            steps {
                echo "📤 Pushing image to Docker registry..."
                script {
                    docker.withRegistry("https://${DOCKER_REGISTRY}", "${DOCKER_CREDENTIALS_ID}") {
                        sh """
                            echo "📤 Pushing images to registry..."
                            echo "   - ${DOCKER_REPO}:${env.IMAGE_TAG}"
                            echo "   - ${DOCKER_REPO}:${LATEST_TAG}"
                            
                            docker push ${DOCKER_REPO}:${env.IMAGE_TAG}
                            docker push ${DOCKER_REPO}:${LATEST_TAG}
                        """
                        echo "✅ Images pushed successfully"
                    }
                }
            }
        }
        
        stage('🚀 Deploy to Minikube') {
            steps {
                echo "🚀 Deploying to remote Minikube cluster..."
                script {
                    try {
                        sh """
                            echo "📦 Preparing deployment for remote Minikube..."
                            echo "   - Target: ${SSH_USER}@${MINIKUBE_PUBLIC_IP}"
                            echo "   - Image: ${DOCKER_REPO}:${env.IMAGE_TAG}"
                            echo "   - Namespace: ${K8S_NAMESPACE}"
                            
                            # Set SSH key path
                            SSH_KEY_PATH="/home/ec2-user/jenkins/workspace/Jenkinsfile-Minikube-Amazon-Linux/minikube-k8s-cluster/minikube-terraform/minikube-demo-key.pem"
                            
                            echo "🔐 Ensuring SSH key permissions..."
                            chmod 600 "\$SSH_KEY_PATH"
                            
                            # Create deployment file with updated image
                            sed 's|image: ip-reverse-app:latest|image: ${DOCKER_REPO}:${env.IMAGE_TAG}|g' k8s-deployment.yaml > k8s-deployment-${BUILD_NUMBER}.yaml
                            
                            # Copy deployment file to Minikube instance
                            scp -i "\$SSH_KEY_PATH" -o StrictHostKeyChecking=no \\
                                k8s-deployment-${BUILD_NUMBER}.yaml \\
                                ${SSH_USER}@${MINIKUBE_PUBLIC_IP}:/tmp/k8s-deployment-${BUILD_NUMBER}.yaml
                            
                            # Connect and deploy
                            ssh -i "\$SSH_KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${MINIKUBE_PUBLIC_IP} "
                                echo '🚀 Starting deployment on Minikube...'
                                
                                # Ensure namespace exists
                                kubectl get namespace ${K8S_NAMESPACE} || kubectl create namespace ${K8S_NAMESPACE}
                                
                                # Apply the deployment
                                kubectl apply -f /tmp/k8s-deployment-${BUILD_NUMBER}.yaml
                                
                                # Wait for rollout to complete
                                echo '⏳ Waiting for deployment rollout...'
                                kubectl rollout status deployment/${APP_NAME} -n ${K8S_NAMESPACE} --timeout=300s
                                
                                # Verify deployment
                                echo '✅ Verifying deployment...'
                                kubectl get pods -n ${K8S_NAMESPACE} -l app=${APP_NAME}
                                kubectl get services -n ${K8S_NAMESPACE} -l app=${APP_NAME}
                                
                                # Get service details
                                echo '📋 Service Details:'
                                kubectl describe service ${APP_NAME}-service -n ${K8S_NAMESPACE} || true
                                
                                # Cleanup temp file
                                rm -f /tmp/k8s-deployment-${BUILD_NUMBER}.yaml
                                
                                echo '✅ Deployment completed successfully'
                            "
                        """
                    } catch (Exception e) {
                        echo "❌ Deployment failed: ${e.getMessage()}"
                        throw e
                    }
                }
            }
            post {
                always {
                    sh "rm -f k8s-deployment-${BUILD_NUMBER}.yaml"
                }
            }
        }
        
        stage('💨 Smoke Test') {
            steps {
                echo "💨 Running smoke tests on deployed application..."
                script {
                    try {
                        sh """
                            echo "🧪 Testing application via multiple methods..."
                            
                            # Set SSH key path
                            SSH_KEY_PATH="/home/ec2-user/jenkins/workspace/Jenkinsfile-Minikube-Amazon-Linux/minikube-k8s-cluster/minikube-terraform/minikube-demo-key.pem"
                            chmod 600 "\$SSH_KEY_PATH"
                            
                            # Method 1: Test via SSH on Minikube instance
                            ssh -i "\$SSH_KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${MINIKUBE_PUBLIC_IP} "
                                echo '🔍 Getting service URL from Minikube...'
                                SERVICE_URL=\\\$(minikube service ${APP_NAME}-service --url -n ${K8S_NAMESPACE})
                                echo '🌐 Internal Service URL: '\\\$SERVICE_URL
                                
                                # Wait for service to be ready
                                echo '⏳ Waiting for service to be ready...'
                                sleep 15
                                
                                # Test the deployed application
                                echo '🧪 Testing deployed application internally...'
                                curl -f \\\$SERVICE_URL/health || exit 1
                                curl -f \\\$SERVICE_URL/ || exit 1
                                
                                echo '✅ Internal smoke tests passed'
                            "
                            
                            # Method 2: Test via NodePort from Jenkins (if accessible)
                            echo "🔗 Testing application via NodePort..."
                            echo "   - URL: http://${MINIKUBE_PUBLIC_IP}:${NODEPORT_SERVICE_PORT}"
                            
                            # Try to access via NodePort (may fail if security group doesn't allow)
                            if curl -f --connect-timeout 10 http://${MINIKUBE_PUBLIC_IP}:${NODEPORT_SERVICE_PORT}/health 2>/dev/null; then
                                echo "✅ NodePort access successful"
                                curl -f http://${MINIKUBE_PUBLIC_IP}:${NODEPORT_SERVICE_PORT}/
                            else
                                echo "⚠️  NodePort access failed (security group may not allow access)"
                                echo "   Application is still accessible from within the Minikube instance"
                            fi
                            
                            echo "🎉 Smoke tests completed"
                        """
                    } catch (Exception e) {
                        echo "❌ Smoke tests failed: ${e.getMessage()}"
                        currentBuild.result = 'UNSTABLE'
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo "🧹 Cleaning up..."
            script {
                try {
                    def dockerRepo = env.DOCKER_REPO ?: 'subhajitdutta/ip-reverse-app'
                    def imageTag = env.IMAGE_TAG ?: "${BUILD_NUMBER}-unknown"
                    def latestTag = env.LATEST_TAG ?: 'latest'
                    
                    sh """
                        echo "🐳 Cleaning up Docker images..."
                        echo "   - Removing: ${dockerRepo}:${imageTag}"
                        echo "   - Removing: ${dockerRepo}:${latestTag}"
                        
                        docker rmi ${dockerRepo}:${imageTag} || true
                        docker rmi ${dockerRepo}:${latestTag} || true
                        
                        # Clean up dangling images
                        docker image prune -f || true
                        
                        echo "✅ Docker cleanup completed"
                    """
                } catch (Exception e) {
                    echo "⚠️ Warning: Could not complete Docker cleanup: ${e.message}"
                }
            }
        }
        
        success {
            script {
                def appName = env.APP_NAME ?: 'ip-reverse-app'
                def dockerRepo = env.DOCKER_REPO ?: 'subhajitdutta/ip-reverse-app'
                def imageTag = env.IMAGE_TAG ?: "${BUILD_NUMBER}-unknown"
                def namespace = env.K8S_NAMESPACE ?: 'default'
                def replicas = env.REPLICAS ?: '2'
                
                echo """
🎉 Pipeline completed successfully!

📋 Deployment Summary:
• Application: ${appName}
• Image: ${dockerRepo}:${imageTag}
• Namespace: ${namespace}
• Replicas: ${replicas}
• Build Number: ${BUILD_NUMBER}
• Git Commit: ${env.GIT_COMMIT_SHORT ?: 'unknown'}

🌐 Access Your Application:
• NodePort URL: http://${MINIKUBE_PUBLIC_IP}:${NODEPORT_SERVICE_PORT}
• SSH to Minikube: ssh -i your-key.pem ${SSH_USER}@${MINIKUBE_PUBLIC_IP}

📊 Check Status (via SSH):
ssh -i your-key.pem ${SSH_USER}@${MINIKUBE_PUBLIC_IP}
kubectl get all -n ${namespace} -l app=${appName}
kubectl get pods -n ${namespace} -l app=${appName}
kubectl logs -n ${namespace} -l app=${appName}

🔗 Get Service URL:
minikube service ${appName}-service --url -n ${namespace}

🎯 Minikube Commands:
kubectl describe deployment ${appName} -n ${namespace}
kubectl get events -n ${namespace} --sort-by='.lastTimestamp'
"""
            }
        }
        
        failure {
            script {
                def appName = env.APP_NAME ?: 'ip-reverse-app'
                def namespace = env.K8S_NAMESPACE ?: 'default'
                
                echo """
❌ Pipeline failed!

🔍 Troubleshooting Commands (via SSH):
ssh -i your-key.pem ${SSH_USER}@${MINIKUBE_PUBLIC_IP}

kubectl get pods -n ${namespace} -l app=${appName}
kubectl logs -n ${namespace} -l app=${appName}
kubectl describe deployment ${appName} -n ${namespace}
kubectl get events -n ${namespace} --sort-by='.lastTimestamp'

🚨 Common Issues:
1. Check if Minikube cluster is running: minikube status
2. Verify SSH key permissions: chmod 600 your-key.pem  
3. Check security groups allow SSH (port 22)
4. Verify Docker registry credentials
5. Ensure sufficient resources on Minikube node

📋 Build Information:
• Build Number: ${BUILD_NUMBER}
• Git Commit: ${env.GIT_COMMIT_SHORT ?: 'unknown'}
• Image Tag: ${env.IMAGE_TAG ?: 'unknown'}
• Target IP: ${MINIKUBE_PUBLIC_IP}
"""
            }
        }
        
        unstable {
            echo "⚠️ Pipeline completed with warnings. Please check the logs."
        }
    }
}