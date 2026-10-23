output "registry_url" {
  description = "URL del repositorio de imágenes (sin tag)."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}/php-flaws-demo"
}

output "app_url" {
  description = "URL pública estable de la aplicación (IP reservada, HTTP, puerto 8080)."
  value       = "http://${google_compute_address.app.address}:${local.app_port}"
}
