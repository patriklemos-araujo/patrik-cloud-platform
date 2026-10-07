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
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "lab-alb-asg-vpc"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "lab-public-a"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name        = "lab-public-b"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name        = "lab-alb-asg-igw"
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

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "lab-alb-sg"
  description = "Allow HTTP traffic from Internet to ALB"
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
    Name        = "lab-alb-sg"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_security_group" "web" {
  name        = "lab-web-sg"
  description = "Allow HTTP only from ALB"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "lab-web-sg"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_lb_target_group" "web" {
  name     = "lab-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.lab.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name        = "lab-web-tg"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_lb" "web" {
  name               = "lab-web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name        = "lab-web-alb"
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

resource "aws_launch_template" "web" {
  name_prefix   = "lab-web-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.web.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash

              dnf install -y nginx

              TOKEN=$(curl -s -X PUT \
                -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
                http://169.254.169.254/latest/api/token)

              INSTANCE_ID=$(curl -s \
                -H "X-aws-ec2-metadata-token: $TOKEN" \
                http://169.254.169.254/latest/meta-data/instance-id)

              AZ=$(curl -s \
                -H "X-aws-ec2-metadata-token: $TOKEN" \
                http://169.254.169.254/latest/meta-data/placement/availability-zone)

              cat <<HTML > /usr/share/nginx/html/index.html
              <h1>Patrik Cloud Platform</h1>
              <p>Lab 05 - ALB + Auto Scaling</p>
              <p>Instance: $INSTANCE_ID</p>
              <p>AZ: $AZ</p>
              HTML

              systemctl enable nginx
              systemctl start nginx
              EOF
  )

  instance_market_options {
    market_type = "spot"
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name        = "lab-web-asg"
      Environment = "lab"
      Project     = "patrik-cloud-platform"
      ManagedBy   = "Terraform"
    }
  }
}

resource "aws_autoscaling_group" "web" {
  name = "lab-web-asg"

  min_size         = 2
  max_size         = 3
  desired_capacity = 2

  vpc_zone_identifier = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  target_group_arns = [
    aws_lb_target_group.web.arn
  ]

  health_check_type         = "ELB"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "lab-web-asg"
    propagate_at_launch = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_cloudwatch_metric_alarm" "healthy_hosts" {
  alarm_name          = "lab-alb-insufficient-healthy-hosts"
  alarm_description   = "Alarm when ALB target group has fewer than 2 healthy targets"

  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"

  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 1

  comparison_operator = "LessThanThreshold"
  threshold           = 2

  treat_missing_data = "breaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.web.arn_suffix
    LoadBalancer = aws_lb.web.arn_suffix
  }

  tags = {
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_autoscaling_policy" "request_target" {
  name                   = "lab-web-request-target"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"

      resource_label = "${aws_lb.web.arn_suffix}/${aws_lb_target_group.web.arn_suffix}"
    }

    target_value = 20.0
  }
}