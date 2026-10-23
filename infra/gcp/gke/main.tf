resource "google_service_account" "node" {
  account_id   = "${var.name_prefix}-node"
  display_name = "${var.name_prefix}-node"
  description  = "Identidad de nodos GKE con roles estandar minimos. created_by: ${var.owner}"

  depends_on = [google_project_service.api]
}

resource "google_project_iam_member" "node" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.node.email}"
}

# Reader a nivel de repositorio únicamente.
resource "google_artifact_registry_repository_iam_member" "node_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.node.email}"
}

# Binary Authorization no se habilita (fuera de alcance de la demo).
# Cluster zonal en ${region}-a: sin alta disponibilidad del plano de control.
resource "google_container_cluster" "main" {
  name        = "${var.name_prefix}-gke"
  location    = local.zone
  description = "created_by: ${var.owner}"

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false
  resource_labels          = local.labels

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.nodes.id

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  addons_config {
    network_policy_config {
      disabled = false
    }
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.admin_cidrs
      content {
        cidr_block   = cidr_blocks.value
        display_name = "admin-${cidr_blocks.key}"
      }
    }
  }

  # GKE_METADATA en el node pool exige el workload pool en el clúster. Se
  # habilita el pool, pero no se crean bindings KSA->GSA: los pods no obtienen
  # identidad GCP y el servidor de metadatos de GKE bloquea el token de la SA
  # del nodo.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  enable_shielded_nodes = true

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  lifecycle {
    precondition {
      condition     = length(var.admin_cidrs) > 0
      error_message = "admin_cidrs es obligatorio en GKE (IP del operador, x.x.x.x/32)."
    }
  }

  depends_on = [google_project_service.api]
}

resource "google_container_node_pool" "default" {
  name       = "${var.name_prefix}-pool"
  cluster    = google_container_cluster.main.name
  location   = local.zone
  node_count = local.node_count

  management {
    auto_upgrade = true
    auto_repair  = true
  }

  node_config {
    machine_type    = local.machine_type
    service_account = google_service_account.node.email
    # Requerido por GKE; el acceso real lo limitan los roles de la SA.
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = local.labels
    resource_labels = local.labels

    metadata = {
      disable-legacy-endpoints = "true"
      block-project-ssh-keys   = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  depends_on = [
    google_project_iam_member.node,
    google_artifact_registry_repository_iam_member.node_reader,
  ]
}
