resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  description             = "created_by: ${var.owner}"

  depends_on = [google_project_service.api]
}

# No Cloud NAT (decision): the nodes are private and reach Google APIs
# (registry, logging, monitoring) via Private Google Access. Without NAT the nodes
# have no general internet egress; this reduces the residual egress of a node
# when compromised. External public images (Docker Hub) are not pullable.
resource "google_compute_subnetwork" "nodes" {
  name                     = "${var.name_prefix}-nodes"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.46.1.0/24"
  private_ip_google_access = true
  description              = "created_by: ${var.owner}"

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.46.16.0/20"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.46.32.0/20"
  }
}
