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
  cpu_memory = {
    small  = { cpu = 256, memory = 512 }
    medium = { cpu = 512, memory = 1024 }
  }
  cpu    = local.cpu_memory[var.size].cpu
  memory = local.cpu_memory[var.size].memory
}
