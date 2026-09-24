terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }
  }

  backend "s3" {
    bucket = "patrik-terraform-state-lab-910093226300"
    key    = "03-remote-state/app/terraform.tfstate"
    region = "us-east-1"
    use_lockfile = true
  }
}

resource "local_file" "remote_state_lab" {
  filename = "${path.module}/remote-state-lab.txt"
  content  = "Teste de state locking com backend S3."
}