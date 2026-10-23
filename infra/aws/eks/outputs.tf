output "registry_url" {
  description = "URL del repositorio ECR (sin tag)."
  value       = aws_ecr_repository.app.repository_url
}

output "kubeconfig_command" {
  description = "Comando para configurar kubectl."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.region}"
}

output "app_url" {
  description = "Vacio: deploy.py obtiene el hostname del LoadBalancer tras aplicar los manifiestos."
  value       = ""
}
