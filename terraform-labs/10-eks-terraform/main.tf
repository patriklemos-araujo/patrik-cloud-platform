
data "aws_vpc" "eks" {
  id = "vpc-0d1d775537c756400"
}

data "aws_subnet" "public_a" {
  id = "subnet-06ba8176a04213968"
}

data "aws_subnet" "public_b" {
  id = "subnet-066b566c30b4936b8"
}

data "aws_iam_role" "cluster" {
  name = "patrik-eks-cluster-role"
}

data "aws_iam_role" "node" {
  name = "patrik-eks-node-role"
}

resource "aws_eks_cluster" "main" {
  name                          = "patrik-eks-lab"
  role_arn                      = data.aws_iam_role.cluster.arn
  bootstrap_self_managed_addons = false
  version                       = "1.36"

  vpc_config {
    subnet_ids = [
      data.aws_subnet.public_a.id,
      data.aws_subnet.public_b.id
    ]

    endpoint_public_access  = true
    endpoint_private_access = true

    public_access_cidrs = ["189.121.200.188/32"]
  }

  deletion_protection = false

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = {
    Project     = "patrik-cloud-platform"
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "patrik-terraform-state-lab-910093226300"
    key          = "eks/lab-10/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"


  tags = {
    Project     = "patrik-cloud-platform"
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"

  pod_identity_association {
    service_account = "aws-node"
    role_arn        = data.aws_iam_role.vpc_cni.arn
  }

  depends_on = [
    aws_eks_addon.pod_identity
  ]

  tags = {
    Project     = "patrik-cloud-platform"
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

data "aws_iam_role" "vpc_cni" {
  name = "AmazonEKSPodIdentityAmazonVPCCNIRole"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  depends_on = [
    aws_eks_node_group.main
  ]

  tags = {
    Project     = "patrik-cloud-platform"
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"

  tags = {
    Project     = "patrik-cloud-platform"
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "patrik-eks-node-group"
  node_role_arn   = data.aws_iam_role.node.arn

  subnet_ids = [
    data.aws_subnet.public_a.id,
    data.aws_subnet.public_b.id
  ]

  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"
  ami_type       = "AL2023_x86_64_STANDARD"
  disk_size      = 20

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.pod_identity,
    aws_eks_addon.kube_proxy
  ]

  tags = {
    Project     = "patrik-cloud-platform"
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}