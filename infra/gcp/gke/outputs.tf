output "registry_url" {
  description = "Image repository URL (no tag)."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}/php-flaws-demo"
}

output "kubeconfig_command" {
  description = "Command to fetch cluster credentials."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.main.name} --zone ${local.zone} --project ${var.project_id}"
}

output "app_url" {
  description = "Empty: the URL is published by the Kubernetes Service applied by deploy.py."
  value       = ""
}
