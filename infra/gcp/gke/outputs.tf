output "registry_url" {
  description = "URL del repositorio de imágenes (sin tag)."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}/php-flaws-demo"
}

output "kubeconfig_command" {
  description = "Comando para obtener credenciales del clúster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.main.name} --zone ${local.zone} --project ${var.project_id}"
}

output "app_url" {
  description = "Vacío: la URL la publica el Service de Kubernetes aplicado por deploy.py."
  value       = ""
}
