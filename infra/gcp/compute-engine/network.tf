resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  description             = "created_by: ${var.owner}"

  depends_on = [google_project_service.api]
}

resource "google_compute_address" "app" {
  name        = "${var.name_prefix}-ip"
  region      = var.region
  description = "IP publica estable de la demo. created_by: ${var.owner}"
  labels      = local.labels

  depends_on = [google_project_service.api]
}

resource "google_compute_subnetwork" "subnet" {
  name                     = "${var.name_prefix}-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.45.1.0/24"
  private_ip_google_access = true
  description              = "created_by: ${var.owner}"
}

# Único ingreso: HTTP al puerto de la app. No hay reglas 22/3389.
resource "google_compute_firewall" "allow_http" {
  name          = "${var.name_prefix}-allow-http"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.web_tag]
  description   = "Ingreso HTTP publico a la app. created_by: ${var.owner}"

  allow {
    protocol = "tcp"
    ports    = [tostring(local.app_port)]
  }
}

resource "google_compute_firewall" "egress_443_dns" {
  name               = "${var.name_prefix}-egress-443-dns"
  network            = google_compute_network.vpc.name
  direction          = "EGRESS"
  priority           = 1000
  destination_ranges = ["0.0.0.0/0"]
  target_tags        = [local.web_tag]
  description        = "Egreso 443 y DNS. created_by: ${var.owner}"

  allow {
    protocol = "tcp"
    ports    = ["443", "53"]
  }

  allow {
    protocol = "udp"
    ports    = ["53"]
  }
}

resource "google_compute_firewall" "deny_egress" {
  name               = "${var.name_prefix}-deny-egress"
  network            = google_compute_network.vpc.name
  direction          = "EGRESS"
  priority           = 65000
  destination_ranges = ["0.0.0.0/0"]
  target_tags        = [local.web_tag]
  description        = "Deniega todo otro egreso. created_by: ${var.owner}"

  deny {
    protocol = "all"
  }
}
