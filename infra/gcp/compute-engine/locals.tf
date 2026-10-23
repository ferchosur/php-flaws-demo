locals {
  labels = {
    created_by = lower(var.owner)
    expires_at = var.expires_at
    app        = "php-flaws-demo"
    managed_by = "terraform"
  }

  apis = ["compute.googleapis.com", "artifactregistry.googleapis.com", "iam.googleapis.com"]

  machine_type = { small = "e2-small", medium = "e2-medium" }[var.size]

  # Fixed zone -a (demo decision: single instance, no high availability).
  zone    = "${var.region}-a"
  web_tag = "php-flaws-demo-web"

  # The container listens on 8080. Konlet (COS) runs with --network=host, so
  # there is no 80->8080 remap: the public port is 8080.
  app_port = 8080
}
