output "registry_url" {
  description = "ECR repository URL (no tag)."
  value       = aws_ecr_repository.app.repository_url
}

output "app_url" {
  description = "Stable public application URL (Elastic IP)."
  value       = "http://${aws_eip.app.public_ip}"
}
