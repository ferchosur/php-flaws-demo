output "registry_url" {
  description = "ECR repository URL (no tag)."
  value       = aws_ecr_repository.app.repository_url
}

output "app_url" {
  description = "Public application URL."
  value       = "http://${aws_lb.main.dns_name}"
}
