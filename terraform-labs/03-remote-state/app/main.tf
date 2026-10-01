terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "patrik-terraform-state-lab-910093226300"
    key          = "03-remote-state/app/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_ssm_parameter" "remote_state_lab" {
  name  = "/patrik-cloud-platform/remote-state-lab/message"
  type  = "String"
  value = "Terraform CI remote state lab"

  tags = {
    Environment = "lab"
    Project     = "patrik-cloud-platform"
    ManagedBy   = "Terraform"
    Repository  = "patrik-cloud-platform"
  }
}