output "file_path" {
  description = "Caminho do arquivo criado"
  value       = local_file.example.filename
}

output "file_id" {
  description = "ID do recurso local_file"
  value       = local_file.example.id
}