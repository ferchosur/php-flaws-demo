resource "google_service_account" "vm" {
  account_id   = "${var.name_prefix}-vm"
  display_name = "${var.name_prefix}-vm"
  description  = "VM identity, repository read-only. created_by: ${var.owner}"

  depends_on = [google_project_service.api]
}

# Repository-level reader only (no project roles).
resource "google_artifact_registry_repository_iam_member" "vm_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_compute_instance" "vm" {
  count = var.image == "" ? 0 : 1

  name         = "${var.name_prefix}-vm"
  machine_type = local.machine_type
  zone         = local.zone
  tags         = [local.web_tag]
  labels       = local.labels
  description  = "created_by: ${var.owner}"

  boot_disk {
    initialize_params {
      image  = "projects/cos-cloud/global/images/family/cos-stable"
      labels = local.labels
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id

    # Stable public IP: the demo URL does not change when the instance is replaced.
    access_config {
      nat_ip = google_compute_address.app.address
    }
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    block-project-ssh-keys    = "true"
    enable-oslogin            = "TRUE"
    google-logging-enabled    = "true"
    gce-container-declaration = templatefile("${path.module}/container-declaration.yaml.tftpl", { image = var.image })
  }

  # Minimal scopes: registry read (storage) and write of
  # logs/metrics. Actual permissions are limited by the SA (repo reader).
  # If the pull fails due to scope, switch to cloud-platform.
  service_account {
    email = google_service_account.vm.email
    scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
    ]
  }

  depends_on = [
    google_artifact_registry_repository_iam_member.vm_reader,
    google_compute_firewall.allow_http,
    google_compute_firewall.egress_443_dns,
    google_compute_firewall.deny_egress,
  ]
}
