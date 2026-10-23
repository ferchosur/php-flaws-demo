locals {
  labels = {
    created_by = lower(var.owner)
    expires_at = var.expires_at
    app        = "php-flaws-demo"
    managed_by = "terraform"
  }

  apis = ["compute.googleapis.com", "artifactregistry.googleapis.com", "iam.googleapis.com"]

  machine_type = { small = "e2-small", medium = "e2-medium" }[var.size]

  # Zona fija -a (decisión de demo: instancia única, sin alta disponibilidad).
  zone    = "${var.region}-a"
  web_tag = "php-flaws-demo-web"

  # El contenedor escucha en 8080. Konlet (COS) ejecuta con --network=host, por
  # lo que no hay remapeo 80->8080: el puerto público es 8080.
  app_port = 8080
}
