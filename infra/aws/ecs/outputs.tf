output "registry_url" {
  description = "URL del repositorio ECR (sin tag)."
  value       = aws_ecr_repository.app.repository_url
}

output "app_url" {
  description = "URL publica de la aplicacion."
  value       = "http://${aws_lb.main.dns_name}"
}
