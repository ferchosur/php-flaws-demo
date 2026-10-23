resource "azurerm_resource_group" "main" {
  name     = "${var.name_prefix}-rg"
  location = var.region
  tags     = local.tags
}

resource "random_string" "acr_suffix" {
  length  = 6
  lower   = true
  numeric = true
  upper   = false
  special = false
}

# Private registry. public_network_access_enabled = true: the deployer (operator
# machine) pushes and the services pull over the public endpoint; the
# authentication is Entra ID/RBAC only (admin_enabled = false, no anonymous pull).
# Defender for Containers (image scanning) is out of scope.
resource "azurerm_container_registry" "app" {
  name                          = replace("${var.name_prefix}acr${random_string.acr_suffix.result}", "-", "")
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  sku                           = "Standard"
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  public_network_access_enabled = true
  tags                          = local.tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name_prefix}-law"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# Only created with alert_email; without it there is no one to notify.
resource "azurerm_consumption_budget_resource_group" "main" {
  count             = var.alert_email != "" ? 1 : 0
  name              = "${var.name_prefix}-budget"
  resource_group_id = azurerm_resource_group.main.id
  amount            = var.budget_usd
  time_grain        = "Monthly"

  time_period {
    start_date = local.budget_start
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
  }
}
