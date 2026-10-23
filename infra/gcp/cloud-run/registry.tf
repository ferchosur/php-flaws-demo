# Contract with deploy.py: address google_artifact_registry_repository.app
# Note: Artifact Registry does not offer immutable tags as a simple option; the
# immutability is achieved using unique tags (timestamp) from deploy.py.
resource "google_artifact_registry_repository" "app" {
  repository_id = "php-flaws-demo"
  format        = "DOCKER"
  location      = var.region
  description   = "php-flaws-demo images. created_by: ${var.owner}"
  labels        = local.labels

  depends_on = [google_project_service.api]
}
