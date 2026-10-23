output "registry_url" {
  description = "Repositorio de imágenes en ACR."
  value       = "${azurerm_container_registry.app.login_server}/${local.repository}"
}

output "app_url" {
  description = "URL pública (vacía hasta que exista la app, es decir con image vacío)."
  value       = length(azurerm_container_app.app) > 0 ? "https://${azurerm_container_app.app[0].ingress[0].fqdn}" : ""
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}
