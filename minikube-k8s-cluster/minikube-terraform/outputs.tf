# =====================================
# outputs.tf - ENHANCED VERSION
# =====================================
output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.minikube_instance.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = var.use_elastic_ip ? aws_eip.minikube_eip[0].public_ip : aws_instance.minikube_instance.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.minikube_instance.private_ip
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${var.cluster_name}-key.pem ubuntu@${var.use_elastic_ip ? aws_eip.minikube_eip[0].public_ip : aws_instance.minikube_instance.public_ip}"
}

output "private_key_path" {
  description = "Path to the generated private key"
  value       = local_file.minikube_private_key.filename
}

output "minikube_ip" {
  description = "Minikube cluster IP (same as instance IP for this setup)"
  value       = var.use_elastic_ip ? aws_eip.minikube_eip[0].public_ip : aws_instance.minikube_instance.public_ip
}

output "kubernetes_dashboard_url" {
  description = "URL to access Kubernetes Dashboard (requires port forwarding)"
  value       = "http://${var.use_elastic_ip ? aws_eip.minikube_eip[0].public_ip : aws_instance.minikube_instance.public_ip}:8080"
}

output "minikube_dashboard_command" {
  description = "Command to access Minikube dashboard with port forwarding"
  value       = "ssh -i ${var.cluster_name}-key.pem -L 8080:localhost:8080 ubuntu@${var.use_elastic_ip ? aws_eip.minikube_eip[0].public_ip : aws_instance.minikube_instance.public_ip} 'minikube dashboard --url'"
}

output "minikube_status_command" {
  description = "Command to check Minikube status"
  value       = "ssh -i ${var.cluster_name}-key.pem ubuntu@${var.use_elastic_ip ? aws_eip.minikube_eip[0].public_ip : aws_instance.minikube_instance.public_ip} 'minikube status'"
}

output "kubectl_config_command" {
  description = "Command to copy kubectl config"
  value       = "scp -i ${var.cluster_name}-key.pem ubuntu@${var.use_elastic_ip ? aws_eip.minikube_eip[0].public_ip : aws_instance.minikube_instance.public_ip}:~/.kube/config ./kubeconfig"
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.minikube_sg.id
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.minikube_vpc.id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = aws_subnet.minikube_subnet.id
}

output "minikube_addons" {
  description = "List of enabled Minikube addons"
  value       = var.enable_addons
}

output "cluster_info" {
  description = "Useful cluster information"
  value = {
    cluster_name       = var.cluster_name
    minikube_version   = var.minikube_version
    kubernetes_version = var.kubernetes_version
    instance_type      = var.instance_type
    public_ip         = var.use_elastic_ip ? aws_eip.minikube_eip[0].public_ip : aws_instance.minikube_instance.public_ip
    private_key_path  = local_file.minikube_private_key.filename
    ssh_command       = "ssh -i ${var.cluster_name}-key.pem ubuntu@${var.use_elastic_ip ? aws_eip.minikube_eip[0].public_ip : aws_instance.minikube_instance.public_ip}"
  }
}

output "minikube_setup_command" {
  description = "Command to manually run Minikube setup if needed"
  value = "sudo /tmp/setup-minikube-terraform.sh '${var.cluster_name}' '${var.environment}' '${var.minikube_version}' '${var.kubernetes_version}' '${var.minikube_driver}' '${var.minikube_memory}' '${var.minikube_cpus}'"
}

output "debug_commands" {
  description = "Useful commands for debugging"
  value = [
    "ssh -i ${var.cluster_name}-key.pem ubuntu@${var.use_elastic_ip ? aws_eip.minikube_eip[0].public_ip : aws_instance.minikube_instance.public_ip}",
    "tail -f /var/log/minikube-setup.log",
    "sudo -u ubuntu minikube status",
    "sudo -u ubuntu kubectl get nodes"
  ]
}

output "minikube_log_tail_command" {
  description = "SSH command to tail the Minikube setup log live"
  value       = "ssh -i ${var.cluster_name}-key.pem ubuntu@${var.use_elastic_ip ? aws_eip.minikube_eip[0].public_ip : aws_instance.minikube_instance.public_ip} 'sudo tail -f /var/log/minikube-setup.log'"
}

output "minikube_log_show_command" {
  description = "SSH command to show the last 200 lines of the Minikube setup log"
  value       = "ssh -i ${var.cluster_name}-key.pem ubuntu@${var.use_elastic_ip ? aws_eip.minikube_eip[0].public_ip : aws_instance.minikube_instance.public_ip} 'sudo tail -n 200 /var/log/minikube-setup.log'"
}

output "minikube_ready_check_command" {
  description = "SSH command to check the Terraform success marker"
  value       = "ssh -i ${var.cluster_name}-key.pem ubuntu@${var.use_elastic_ip ? aws_eip.minikube_eip[0].public_ip : aws_instance.minikube_instance.public_ip} 'cat /tmp/minikube-ready || echo not-ready'"
}
