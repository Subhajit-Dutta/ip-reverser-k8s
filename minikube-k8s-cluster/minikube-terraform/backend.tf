# =====================================
# backend.tf - FIXED VERSION
# =====================================
terraform {
  backend "s3" {
    # Configuration will be provided via backend-config.hcl
    # No variables allowed in backend configuration
  }
}