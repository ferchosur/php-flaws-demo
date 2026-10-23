output "registry_url" {
  description = "URL del repositorio ECR (sin tag)."
  value       = aws_ecr_repository.app.repository_url
}

output "app_url" {
  description = "URL publica estable de la aplicacion (Elastic IP)."
  value       = "http://${aws_eip.app.public_ip}"
}
