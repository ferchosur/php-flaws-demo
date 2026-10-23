output "registry_url" {
  description = "Image repository URL (no tag)."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}/php-flaws-demo"
}

output "app_url" {
  description = "Stable public application URL (reserved IP, HTTP, port 8080)."
  value       = "http://${google_compute_address.app.address}:${local.app_port}"
}
