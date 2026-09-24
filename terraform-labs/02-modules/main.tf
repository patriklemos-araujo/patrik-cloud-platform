terraform {
  backend "local" {
    path = "state/terraform.tfstate"
  }
}

module "dev_file" {
  source = "./modules/local-file"

  file_name    = "module-dev.txt"
  file_content = "Arquivo criado pelo primeiro Terraform module!"
}