pipeline {
    agent {
        label 'ec2-agent-1'
    }
    
    environment {
        // Docker Registry Configuration
        DOCKER_REGISTRY = 'docker.io'
        DOCKER_REPO = 'subhajitdutta/ip-reverse-app'
        DOCKER_CREDENTIALS_ID = 'docker-hub-credentials'
        
        // Application Configuration
        APP_NAME = 'ip-reverse-app'
        APP_PORT = '8080'
        K8S_NAMESPACE = 'default'
        REPLICAS = '2'
        
        // Git Configuration
        GIT_REPO = 'https://github.com/Subhajit-Dutta/ip-reverser-k8s'
        GIT_BRANCH = 'master'
        
        // Build Configuration
        BUILD_NUMBER_TAG = "${BUILD_NUMBER}"
        LATEST_TAG = 'latest'
        
        // Kubernetes Configuration
        KUBECONFIG = credentials('kubeconfig-minikube')
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
    }
    
    stages {
        stage('Checkout') {
            steps {
                echo "🔄 Checking out code from ${GIT_REPO} - ${GIT_BRANCH} branch"
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: "*/${GIT_BRANCH}"]],
                    userRemoteConfigs: [[url: "${GIT_REPO}"]]
                ])
                
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
        
        stage('Validate Files') {
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
        
        stage('Build Docker Image') {
            steps {
                echo "🔨 Building Docker image..."
                script {
                    // Build image with both build-specific and latest tags
                    sh """
                        docker build -t ${DOCKER_REPO}:${IMAGE_TAG} .
                        docker tag ${DOCKER_REPO}:${IMAGE_TAG} ${DOCKER_REPO}:${LATEST_TAG}
                    """
                    echo "✅ Docker image built successfully"
                }
            }
        }
        
        stage('Test Application') {
            steps {
                echo "🧪 Testing application..."
                script {
                    // Run container for testing
                    sh """
                        # Start container in background
                        docker run -d --name test-${BUILD_NUMBER} -p 8081:8080 ${DOCKER_REPO}:${IMAGE_TAG}
                        
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
                    // Cleanup test container
                    sh """
                        docker stop test-${BUILD_NUMBER} || true
                        docker rm test-${BUILD_NUMBER} || true
                    """
                }
            }
        }
        
        stage('Security Scan') {
            steps {
                echo "🔐 Running security scan..."
                script {
                    try {
                        // Use Trivy for security scanning if available
                        sh """
                            if command -v trivy >/dev/null 2>&1; then
                                echo "📊 Running Trivy security scan..."
                                trivy image --exit-code 0 --severity HIGH,CRITICAL ${DOCKER_REPO}:${IMAGE_TAG}
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
        
        stage('Push to Registry') {
            steps {
                echo "📤 Pushing image to Docker registry..."
                script {
                    docker.withRegistry("https://${DOCKER_REGISTRY}", "${DOCKER_CREDENTIALS_ID}") {
                        sh """
                            docker push ${DOCKER_REPO}:${IMAGE_TAG}
                            docker push ${DOCKER_REPO}:${LATEST_TAG}
                        """
                        echo "✅ Images pushed successfully"
                    }
                }
            }
        }
        
        stage('Deploy to Minikube') {
            steps {
                echo "🚀 Deploying to Minikube..."
                script {
                    // Update image tag in deployment YAML
                    sh """
                        # Create temporary deployment file with correct image tag
                        sed 's|image: ip-reverse-app:latest|image: ${DOCKER_REPO}:${IMAGE_TAG}|g' k8s-deployment.yaml > k8s-deployment-${BUILD_NUMBER}.yaml
                        
                        # Apply the deployment
                        kubectl apply -f k8s-deployment-${BUILD_NUMBER}.yaml
                        
                        # Wait for rollout to complete
                        echo "⏳ Waiting for deployment rollout..."
                        kubectl rollout status deployment/${APP_NAME} -n ${K8S_NAMESPACE} --timeout=300s
                        
                        # Verify deployment
                        echo "✅ Verifying deployment..."
                        kubectl get pods -n ${K8S_NAMESPACE} -l app=${APP_NAME}
                        kubectl get services -n ${K8S_NAMESPACE} -l app=${APP_NAME}
                    """
                    echo "✅ Deployment completed successfully"
                }
            }
            post {
                always {
                    // Cleanup temporary files
                    sh "rm -f k8s-deployment-${BUILD_NUMBER}.yaml"
                }
            }
        }
        
        stage('Smoke Test') {
            steps {
                echo "💨 Running smoke tests..."
                script {
                    sh """
                        # Get service URL
                        SERVICE_URL=\$(minikube service ${APP_NAME}-service --url -n ${K8S_NAMESPACE})
                        echo "🌐 Service URL: \$SERVICE_URL"
                        
                        # Wait for service to be ready
                        echo "⏳ Waiting for service to be ready..."
                        sleep 15
                        
                        # Test the deployed application
                        echo "🧪 Testing deployed application..."
                        curl -f \$SERVICE_URL/health || exit 1
                        curl -f \$SERVICE_URL/ || exit 1
                        
                        echo "✅ Smoke tests passed"
                        echo "🎉 Application is ready at: \$SERVICE_URL"
                    """
                }
            }
        }
    }
    
    post {
        always {
            echo "🧹 Cleaning up..."
            script {
                // Cleanup local Docker images to save space
                sh """
                    docker rmi ${DOCKER_REPO}:${IMAGE_TAG} || true
                    docker rmi ${DOCKER_REPO}:${LATEST_TAG} || true
                    
                    # Clean up dangling images
                    docker image prune -f || true
                """
            }
        }
        
        success {
            echo """
            🎉 Pipeline completed successfully!
            
            📋 Deployment Summary:
            • Application: ${APP_NAME}
            • Image: ${DOCKER_REPO}:${IMAGE_TAG}
            • Namespace: ${K8S_NAMESPACE}
            • Replicas: ${REPLICAS}
            
            🔗 Access your application:
            minikube service ${APP_NAME}-service --url -n ${K8S_NAMESPACE}
            
            📊 Or check the status:
            kubectl get all -n ${K8S_NAMESPACE} -l app=${APP_NAME}
            """
        }
        
        failure {
            echo """
            ❌ Pipeline failed!
            
            🔍 Troubleshooting commands:
            kubectl get pods -n ${K8S_NAMESPACE} -l app=${APP_NAME}
            kubectl logs -n ${K8S_NAMESPACE} -l app=${APP_NAME}
            kubectl describe deployment ${APP_NAME} -n ${K8S_NAMESPACE}
            """
        }
        
        unstable {
            echo "⚠️ Pipeline completed with warnings. Please check the logs."
        }
    }
}