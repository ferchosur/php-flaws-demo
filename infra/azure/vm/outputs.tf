output "registry_url" {
  description = "Repositorio de imágenes en ACR."
  value       = "${azurerm_container_registry.app.login_server}/${local.repository}"
}

output "app_url" {
  value = "http://${azurerm_public_ip.vm.ip_address}"
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}
