terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.8.0"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "lab" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "lab-networking-vpc"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "lab-public-subnet"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name        = "lab-networking-igw"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name        = "lab-public-rt"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name        = "lab-private-subnet"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name        = "lab-private-rt"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "public_web" {
  name        = "lab-public-web-sg"
  description = "Allow HTTP traffic for public lab workloads"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "lab-public-web-sg"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.public_web.id]
  associate_public_ip_address = true

  instance_market_options {
    market_type = "spot"

    spot_options {
      instance_interruption_behavior = "terminate"
      spot_instance_type             = "one-time"
    }
  }

  user_data = <<-EOF
              #!/bin/bash
              dnf install -y nginx
              echo "<h1>Patrik Cloud Platform</h1><p>Lab 04 - AWS Networking</p>" > /usr/share/nginx/html/index.html
              systemctl enable nginx
              systemctl start nginx
              EOF

  tags = {
    Name        = "lab-web-ec2"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "lab-web-ec2-high-cpu"
  alarm_description   = "Triggers when EC2 CPU utilization is above 70 percent"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 70

  dimensions = {
    InstanceId = aws_instance.web.id
  }

  treat_missing_data = "notBreaching"

  tags = {
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}