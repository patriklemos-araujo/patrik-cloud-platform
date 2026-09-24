variable "file_name" {
  type        = string
  description = "Nome do arquivo que será criado"
  default     = "hello.txt"
}

variable "file_content" {
  type        = string
  description = "Conteudo do arquivo"
  default     = "Hello Terraform with variables!"
}

variable "environment" {
  type        = string
  description = "Ambiente da infraestrutura"
  default     = "dev"
}