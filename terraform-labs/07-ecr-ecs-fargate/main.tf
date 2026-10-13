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

resource "aws_ecr_repository" "app" {
  name                 = "patrik-cloud-platform-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "patrik-cloud-platform-app"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after 1 day"

        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecs_cluster" "app" {
  name = "patrik-cloud-platform-cluster"

  tags = {
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/patrik-cloud-platform-app"
  retention_in_days = 7

  tags = {
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

data "aws_iam_policy_document" "ecs_task_execution_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "ecs-tasks.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "patrik-ecs-task-execution-role"

  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role.json

  tags = {
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "patrik-cloud-platform-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name = "app"

      image = "${aws_ecr_repository.app.repository_url}:v1"

      essential = true

      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc" "app" {
  cidr_block           = "10.30.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "patrik-cloud-platform-vpc"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name        = "patrik-cloud-platform-igw"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = "10.30.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "patrik-public-a"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = "10.30.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name        = "patrik-public-b"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }

  tags = {
    Name        = "patrik-public-rt"
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
  name        = "patrik-alb-sg"
  description = "Allow HTTP from the internet to the ALB"
  vpc_id      = aws_vpc.app.id

  ingress {
    description = "HTTP from internet"
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
    Name        = "patrik-alb-sg"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_security_group" "ecs" {
  name        = "patrik-ecs-sg"
  description = "Allow HTTP only from the ALB"
  vpc_id      = aws_vpc.app.id

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
    Name        = "patrik-ecs-sg"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_lb" "app" {
  name               = "patrik-cloud-platform-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name        = "patrik-cloud-platform-alb"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_lb_target_group" "app" {
  name        = "patrik-cloud-platform-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.app.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "patrik-cloud-platform-tg"
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_ecs_service" "app" {
  name            = "patrik-cloud-platform-service"
  cluster         = aws_ecs_cluster.app.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets = [
      aws_subnet.public_a.id,
      aws_subnet.public_b.id
    ]

    security_groups = [
      aws_security_group.ecs.id
    ]

    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.ecs_task_execution
  ]

  tags = {
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"

      identifiers = [
        "arn:aws:iam::910093226300:oidc-provider/token.actions.githubusercontent.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"

      values = [
        "repo:patriklemos-araujo/patrik-cloud-platform:ref:refs/heads/main",
        "repo:patriklemos-araujo/patrik-cloud-platform:ref:refs/heads/feat/ecr-ecs-fargate-lab"
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name = "github-actions-ecs-deploy"

  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
  }
}

data "aws_iam_policy_document" "github_actions_ecr" {
  statement {
    sid = "ECRAuthentication"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }

  statement {
    sid = "PushImageToECR"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage"
    ]

    resources = [
      aws_ecr_repository.app.arn
    ]
  }
}

resource "aws_iam_policy" "github_actions_ecr" {
  name        = "github-actions-ecr-push"
  description = "Allow GitHub Actions to push images to the Lab 07 ECR repository"

  policy = data.aws_iam_policy_document.github_actions_ecr.json
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_ecr.arn
}