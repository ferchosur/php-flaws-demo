# Cloud Run: único punto público intencional = allUsers run.invoker.
# Egreso residual: Cloud Run tiene salida a internet por defecto (sin VPC
# connector); un contenedor comprometido podría salir a internet.
resource "google_service_account" "run" {
  account_id   = "${var.name_prefix}-run"
  display_name = "${var.name_prefix}-run"
  description  = "Identidad sin roles del servicio Cloud Run. created_by: ${var.owner}"

  depends_on = [google_project_service.api]
}

# El service agent de Cloud Run necesita leer imágenes del repositorio.
resource "google_artifact_registry_repository_iam_member" "run_agent_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:service-${data.google_project.current.number}@serverless-robot-prod.iam.gserviceaccount.com"
}

resource "google_cloud_run_v2_service" "app" {
  count = var.image == "" ? 0 : 1

  name                = var.name_prefix
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false
  labels              = local.labels
  description         = "created_by: ${var.owner}"

  template {
    service_account                  = google_service_account.run.email
    execution_environment            = "EXECUTION_ENVIRONMENT_GEN2"
    max_instance_request_concurrency = 40
    timeout                          = "30s"
    labels                           = local.labels

    scaling {
      min_instance_count = 0
      max_instance_count = var.replicas
    }

    containers {
      image = var.image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = local.size.cpu
          memory = local.size.memory
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      startup_probe {
        http_get {
          path = "/healthz"
        }
      }

      liveness_probe {
        http_get {
          path = "/healthz"
        }
      }
    }
  }

  depends_on = [
    google_project_service.api,
    google_artifact_registry_repository_iam_member.run_agent_reader,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  count = var.image == "" ? 0 : 1

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.app[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
