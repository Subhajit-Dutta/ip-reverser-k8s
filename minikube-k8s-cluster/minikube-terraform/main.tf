# EC2 Instance - FINAL WORKING VERSION
resource "aws_instance" "minikube_instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.minikube_key.key_name
  vpc_security_group_ids = [aws_security_group.minikube_sg.id]
  subnet_id              = aws_subnet.minikube_subnet.id
  iam_instance_profile   = aws_iam_instance_profile.minikube_profile.name

  # Basic user data for initial setup
  user_data = base64encode(<<-EOF
#!/bin/bash
apt-get update
apt-get install -y awscli python3 python3-pip curl

# Create a marker that instance is ready for provisioning
echo "Instance ready for provisioning" > /tmp/instance-ready
EOF
  )

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = {
    Name        = "${var.cluster_name}-minikube"
    Environment = var.environment
    Role        = "minikube-cluster"
  }

  lifecycle {
    create_before_destroy = true
  }

  # Wait for instance to be ready
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",
      "echo 'Instance is ready for setup'"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.minikube_key.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
    }
  }

  # Copy the final working script to the instance
  provisioner "file" {
    source      = "${path.module}/setup-minikube-final.sh"
    destination = "/tmp/setup-minikube-final.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.minikube_key.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
    }
  }

  # Execute the setup script with parameters
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup-minikube-final.sh",
      "echo '🚀 Starting Minikube setup with proven working script...'",
      "sudo /tmp/setup-minikube-final.sh '${var.cluster_name}' '${var.environment}' '${var.minikube_version}' '${var.kubernetes_version}' '${var.minikube_driver}' '${var.minikube_memory}' '${var.minikube_cpus}' 2>&1 | tee /tmp/minikube-setup.log",
      "echo '⏳ Waiting for setup completion...'",
      "timeout 1800 bash -c 'until [ -f /tmp/minikube-ready ]; do echo \"Still setting up Minikube...\"; sleep 30; done'",
      "if [ -f /tmp/minikube-ready ]; then echo '✅ Setup marker found!'; cat /tmp/minikube-ready; else echo '❌ Setup timeout - check logs'; cat /tmp/minikube-setup.log | tail -50; exit 1; fi",
      "echo '🎉 Minikube setup completed successfully!'",
      "echo '🔍 Final verification:'",
      "sudo -i -u ubuntu minikube status",
      "sudo -i -u ubuntu kubectl get nodes",
      "echo '✅ All systems go! Minikube is ready for deployments!'"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.minikube_key.private_key_pem
      host        = self.public_ip
      timeout     = "35m"  # Generous timeout for complete setup
    }
  }
}