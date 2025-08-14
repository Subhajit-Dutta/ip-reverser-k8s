# AWS Configuration
aws_region = "us-west-2"

# Cluster Configuration
cluster_name = "minikube-demo"
environment  = "development"

# Instance Configuration
instance_type      = "t3.medium"
root_volume_size   = 30
use_elastic_ip     = true

# Security Configuration
allowed_cidr_blocks = [
  "0.0.0.0/0"  # Change this to your specific IP range for production
  # "YOUR_IP/32"  # Example: "203.0.113.0/32"
]

# Minikube Configuration
minikube_version   = "v1.32.0"
kubernetes_version = "v1.28.3"
minikube_driver    = "docker"
minikube_memory    = "3900"
minikube_cpus      = "2"

# Additional Features
enable_addons = [
  "dashboard",
  "metrics-server",
  "ingress",
  "storage-provisioner"
]

create_jenkins_config = true