# Contrato con deploy.py: dirección google_artifact_registry_repository.app
# Nota: Artifact Registry no ofrece tags inmutables como opción simple; la
# inmutabilidad se logra usando tags únicos (timestamp) desde deploy.py.
resource "google_artifact_registry_repository" "app" {
  repository_id = "php-flaws-demo"
  format        = "DOCKER"
  location      = var.region
  description   = "Imágenes de php-flaws-demo. created_by: ${var.owner}"
  labels        = local.labels

  depends_on = [google_project_service.api]
}
