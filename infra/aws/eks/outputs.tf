output "registry_url" {
  description = "ECR repository URL (no tag)."
  value       = aws_ecr_repository.app.repository_url
}

output "kubeconfig_command" {
  description = "Command to configure kubectl."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.region}"
}

output "app_url" {
  description = "Empty: deploy.py gets the LoadBalancer hostname after applying the manifests."
  value       = ""
}
