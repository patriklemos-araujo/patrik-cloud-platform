terraform {
  required_version = ">= 1.15.0"

  required_providers {
    local = {
      source = "hashicorp/local"
    }
  }
}

provider "local" {}

resource "local_file" "example" {
  filename = "${path.module}/${var.file_name}"
  content  = local.full_content

  lifecycle {
     ignore_changes = [
       content
     ]
  }
}

resource "local_file" "count_example" {
  count = var.file_count

  filename = "${path.module}/count-${count.index}.txt"
  content  = "Arquivo numero ${count.index}"
}

resource "local_file" "foreach_example" {
  for_each = var.environments

  filename = "${path.module}/env-${each.key}.txt"
  content  = "Environment: ${each.value}"
}

resource "local_file" "dependency_base" {
  filename = "${path.module}/dependency-base.txt"
  content  = "Recurso base criado primeiro"

  lifecycle {
    prevent_destroy = true
  }
}

resource "local_file" "dependency_child" {
  filename = "${path.module}/dependency-child.txt"
  content  = "Recurso dependente"

  depends_on = [
    local_file.dependency_base
  ]
}

resource "terraform_data" "ignore_lab" {
  input = "valor-alterado"

  lifecycle {
    ignore_changes = [
      input
    ]
  }
}

data "local_file" "existing_file" {
  filename = "${path.module}/dependency-base.txt"
}

resource "local_file" "from_data_source" {
  filename = "${path.module}/copied-from-data.txt"

  content = "Conteudo lido pelo data source: ${data.local_file.existing_file.content}"
}