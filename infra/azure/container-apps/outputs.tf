output "registry_url" {
  description = "Image repository in ACR."
  value       = "${azurerm_container_registry.app.login_server}/${local.repository}"
}

output "app_url" {
  description = "Public URL (empty until the app exists, i.e. with an empty image)."
  value       = length(azurerm_container_app.app) > 0 ? "https://${azurerm_container_app.app[0].ingress[0].fqdn}" : ""
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}
