output "kubeconfig_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name} --overwrite-existing"
}

output "registry_url" {
  description = "Repositorio de imágenes en ACR."
  value       = "${azurerm_container_registry.app.login_server}/${local.repository}"
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "app_url" {
  description = "Vacío: la URL se obtiene del Service tras aplicar los manifiestos."
  value       = ""
}
