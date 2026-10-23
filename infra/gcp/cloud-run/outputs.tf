output "registry_url" {
  description = "URL del repositorio de imágenes (sin tag)."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}/php-flaws-demo"
}

output "app_url" {
  description = "URL pública de la aplicación."
  value       = try(google_cloud_run_v2_service.app[0].uri, "")
}
