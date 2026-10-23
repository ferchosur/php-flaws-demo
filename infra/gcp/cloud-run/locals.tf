locals {
  labels = {
    created_by = lower(var.owner)
    expires_at = var.expires_at
    app        = "php-flaws-demo"
    managed_by = "terraform"
  }

  apis = ["run.googleapis.com", "artifactregistry.googleapis.com", "iam.googleapis.com"]

  size = {
    small  = { cpu = "1", memory = "512Mi" }
    medium = { cpu = "2", memory = "1Gi" }
  }[var.size]
}
