terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }
  }
}

resource "local_file" "this" {
  filename = "${path.root}/${var.file_name}"
  content  = var.file_content
}