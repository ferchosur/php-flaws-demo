locals {
  labels = {
    created_by = lower(var.owner)
    expires_at = var.expires_at
    app        = "php-flaws-demo"
    managed_by = "terraform"
  }

  apis = ["container.googleapis.com", "compute.googleapis.com", "artifactregistry.googleapis.com", "iam.googleapis.com"]

  machine_type = { small = "e2-medium", medium = "e2-standard-2" }[var.size]
  zone         = "${var.region}-a"
  node_count   = min(var.replicas, 3)
}
