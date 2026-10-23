locals {
  sizes = {
    small  = { cpu = 0.5, memory = "1Gi" }
    medium = { cpu = 1, memory = "2Gi" }
  }
  sz = local.sizes[var.size]
}

# Only identity attached to the app: it can only pull images (AcrPull
# on the registry). The app has no SystemAssigned identity or other roles.
resource "azurerm_user_assigned_identity" "pull" {
  name                = "${var.name_prefix}-pull"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "pull" {
  scope                = azurerm_container_registry.app.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.pull.principal_id
}

# No VNet (residual: unrestricted egress from the Consumption environment).
resource "azurerm_container_app_environment" "main" {
  name                       = "${var.name_prefix}-env"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.tags
}

# count = 0 during registry bootstrap (empty image).
resource "azurerm_container_app" "app" {
  count                        = var.image == "" ? 0 : 1
  name                         = "${var.name_prefix}-app"
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.pull.id]
  }

  registry {
    server   = azurerm_container_registry.app.login_server
    identity = azurerm_user_assigned_identity.pull.id
  }

  ingress {
    external_enabled           = true
    target_port                = 8080
    transport                  = "http"
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = var.replicas

    # Container Apps does not support a read-only root filesystem (residual).
    container {
      name   = "app"
      image  = var.image
      cpu    = local.sz.cpu
      memory = local.sz.memory

      startup_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/healthz"
      }

      liveness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/healthz"
      }

      readiness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/healthz"
      }
    }
  }

  depends_on = [azurerm_role_assignment.pull]
}
