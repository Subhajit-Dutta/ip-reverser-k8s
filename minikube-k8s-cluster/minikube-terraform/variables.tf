# =====================================
# variables.tf - ENHANCED VERSION
# =====================================
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the Minikube cluster"
  type        = string
  default     = "minikube-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "demo"
}

variable "instance_type" {
  description = "EC2 instance type (minimum t3.medium for Minikube)"
  type        = string
  default     = "t3.medium"
  
  validation {
    condition = contains([
      "t3.medium", "t3.large", "t3.xlarge", "t3.2xlarge",
      "t2.medium", "t2.large", "t2.xlarge", "t2.2xlarge",
      "m5.large", "m5.xlarge", "m5.2xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge"
    ], var.instance_type)
    error_message = "Instance type must be at least t3.medium for Minikube to run properly."
  }
}

variable "root_volume_size" {
  description = "Size of the root volume in GB (minimum 20GB for Minikube)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.root_volume_size >= 20
    error_message = "Root volume size must be at least 20GB for Minikube."
  }
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the cluster"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production
}

variable "use_elastic_ip" {
  description = "Whether to use Elastic IP for the instance"
  type        = bool
  default     = true
}

variable "minikube_version" {
  description = "Minikube version to install"
  type        = string
  default     = "v1.32.0"
}

variable "kubernetes_version" {
  description = "Kubernetes version for Minikube"
  type        = string
  default     = "v1.28.3"
}

variable "minikube_driver" {
  description = "Minikube driver (docker, none, or vm-driver)"
  type        = string
  default     = "docker"
  
  validation {
    condition     = contains(["docker", "none", "virtualbox", "vmware"], var.minikube_driver)
    error_message = "Minikube driver must be one of: docker, none, virtualbox, vmware."
  }
}

variable "minikube_memory" {
  description = "Memory allocation for Minikube in MB"
  type        = string
  default     = "3900"
}

variable "minikube_cpus" {
  description = "CPU allocation for Minikube"
  type        = string
  default     = "2"
}

variable "enable_addons" {
  description = "List of Minikube addons to enable"
  type        = list(string)
  default = [
    "dashboard",
    "metrics-server",
    "ingress",
    "registry"
  ]
}

variable "create_jenkins_config" {
  description = "Whether to create Jenkins kubeconfig automatically"
  type        = bool
  default     = true
}