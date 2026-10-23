locals {
  tags = {
    created_by = var.owner
    expires_at = var.expires_at
    app        = "php-flaws-demo"
    managed_by = "terraform"
  }

  name = var.name_prefix
}

locals {
  instance_type = var.size == "medium" ? "t3.large" : "t3.medium"
  cluster_name  = "${local.name}-eks"
  node_min      = var.replicas
  node_max      = var.replicas + 1
}
