locals {
  node_sizes = {
    small  = "Standard_B2s"
    medium = "Standard_B2ms"
  }
  node_count = max(1, min(var.replicas, 3))
}

data "azurerm_client_config" "current" {}

resource "azurerm_virtual_network" "main" {
  name                = "${var.name_prefix}-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.44.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "${var.name_prefix}-nodes"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.44.1.0/24"]
}

# AKS administra las reglas del LoadBalancer en su propio NSG de nodos; un NSG
# propio con deny-all en la subred rompería el Service tipo LoadBalancer, por
# eso no se crea. Residual: los nodos tienen egreso libre (outbound LB por
# defecto, sin NAT gateway ni Azure Firewall).

resource "azurerm_kubernetes_cluster" "main" {
  name                              = "${var.name_prefix}-aks"
  resource_group_name               = azurerm_resource_group.main.name
  location                          = azurerm_resource_group.main.location
  dns_prefix                        = var.name_prefix
  sku_tier                          = "Free"
  local_account_disabled            = true
  role_based_access_control_enabled = true
  image_cleaner_enabled             = true
  tags                              = local.tags

  default_node_pool {
    name                         = "default"
    vm_size                      = local.node_sizes[var.size]
    node_count                   = local.node_count
    auto_scaling_enabled         = false
    vnet_subnet_id               = azurerm_subnet.nodes.id
    only_critical_addons_enabled = false
    temporary_name_for_rotation  = "tmpdefault"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  api_server_access_profile {
    authorized_ip_ranges = var.admin_cidrs
  }

  lifecycle {
    precondition {
      condition     = length(var.admin_cidrs) > 0
      error_message = "admin_cidrs es obligatorio en AKS (por ejemplo [\"203.0.113.10/32\"])."
    }
  }
}

resource "azurerm_role_assignment" "kubelet_pull" {
  scope                            = azurerm_container_registry.app.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
