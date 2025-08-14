terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC
resource "aws_vpc" "minikube_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.cluster_name}-vpc"
    Environment = var.environment
    Purpose     = "minikube-demo"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "minikube_igw" {
  vpc_id = aws_vpc.minikube_vpc.id

  tags = {
    Name        = "${var.cluster_name}-igw"
    Environment = var.environment
  }
}

# Public Subnet
resource "aws_subnet" "minikube_subnet" {
  vpc_id                  = aws_vpc.minikube_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.cluster_name}-subnet"
    Environment = var.environment
  }
}

# Route Table
resource "aws_route_table" "minikube_rt" {
  vpc_id = aws_vpc.minikube_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.minikube_igw.id
  }

  tags = {
    Name        = "${var.cluster_name}-rt"
    Environment = var.environment
  }
}

# Route Table Association
resource "aws_route_table_association" "minikube_rta" {
  subnet_id      = aws_subnet.minikube_subnet.id
  route_table_id = aws_route_table.minikube_rt.id
}

# Security Group
resource "aws_security_group" "minikube_sg" {
  name_prefix = "${var.cluster_name}-sg"
  vpc_id      = aws_vpc.minikube_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "SSH access"
  }

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  # Kubernetes API Server
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Minikube API Server"
  }

  # NodePort range
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "NodePort services"
  }

  # Dashboard and other services
  ingress {
    from_port   = 8080
    to_port     = 8090
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Dashboard and services"
  }

  # Docker daemon (if needed)
  ingress {
    from_port   = 2376
    to_port     = 2376
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Docker daemon"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "${var.cluster_name}-sg"
    Environment = var.environment
  }
}

# IAM Role for EC2 instance
resource "aws_iam_role" "minikube_role" {
  name = "${var.cluster_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

# IAM Policy for ECR access
resource "aws_iam_role_policy" "minikube_policy" {
  name = "${var.cluster_name}-ec2-policy"
  role = aws_iam_role.minikube_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "minikube_profile" {
  name = "${var.cluster_name}-ec2-profile"
  role = aws_iam_role.minikube_role.name
}

# Key Pair
resource "aws_key_pair" "minikube_key" {
  key_name   = "${var.cluster_name}-key"
  public_key = var.public_key

  tags = {
    Environment = var.environment
  }
}

# User Data Script
locals {
  user_data = base64encode(templatefile("${path.module}/minikube-setup.sh", {
    cluster_name       = var.cluster_name
    environment        = var.environment
    minikube_version   = var.minikube_version
    kubernetes_version = var.kubernetes_version
    minikube_driver    = var.minikube_driver
    minikube_memory    = var.minikube_memory
    minikube_cpus      = var.minikube_cpus
  }))
}

# EC2 Instance
resource "aws_instance" "minikube_instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.minikube_key.key_name
  vpc_security_group_ids = [aws_security_group.minikube_sg.id]
  subnet_id              = aws_subnet.minikube_subnet.id
  iam_instance_profile   = aws_iam_instance_profile.minikube_profile.name

  user_data = local.user_data

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
}

# Elastic IP
resource "aws_eip" "minikube_eip" {
  count    = var.use_elastic_ip ? 1 : 0
  instance = aws_instance.minikube_instance.id
  domain   = "vpc"

  tags = {
    Name        = "${var.cluster_name}-eip"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.minikube_igw]
}