output "kubeconfig_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name} --overwrite-existing"
}

output "registry_url" {
  description = "Image repository in ACR."
  value       = "${azurerm_container_registry.app.login_server}/${local.repository}"
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "app_url" {
  description = "Empty: the URL comes from the Service after applying the manifests."
  value       = ""
}
