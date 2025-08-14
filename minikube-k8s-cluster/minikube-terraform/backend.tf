# backend.tf
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "minikube-clusters/${var.cluster_name}/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
    
    # Optional: Use workspace-based state management
    workspace_key_prefix = "minikube-environments"
  }
}