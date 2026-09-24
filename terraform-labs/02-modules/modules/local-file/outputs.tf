output "file_path" {
  description = "Caminho do arquivo criado pelo modulo"
  value       = local_file.this.filename
}

output "file_id" {
  description = "ID do arquivo criado pelo modulo"
  value       = local_file.this.id
}