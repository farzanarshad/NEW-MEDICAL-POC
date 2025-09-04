output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "webapp_url" {
  description = "URL of the web application"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "webapp_name" {
  description = "Name of the web application"
  value       = azurerm_linux_web_app.main.name
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "blob_container_name" {
  description = "Name of the blob container"
  value       = azurerm_storage_container.transcripts.name
}

output "speech_account_name" {
  description = "Name of the Speech service account"
  value       = azurerm_cognitive_account.speech.name
}

output "speech_account_id" {
  description = "ID of the Speech service account"
  value       = azurerm_cognitive_account.speech.id
}

output "speech_region" {
  description = "Region of the Speech service"
  value       = azurerm_cognitive_account.speech.location
}

output "managed_identity_principal_id" {
  description = "Principal ID of the managed identity"
  value       = azurerm_linux_web_app.main.identity[0].principal_id
  sensitive   = true
}

output "api_bearer_token" {
  description = "Generated API Bearer token"
  value       = local.bearer_token
  sensitive   = true
}

output "websocket_url" {
  description = "WebSocket URL for the application"
  value       = "wss://${azurerm_linux_web_app.main.default_hostname}/ws"
}

output "deployment_instructions" {
  description = "Instructions for completing the deployment"
  value = <<-EOT
    Deployment completed successfully!
    
    Next steps:
    1. Get the Speech service key:
       az cognitiveservices account keys list -g ${azurerm_resource_group.main.name} -n ${azurerm_cognitive_account.speech.name}
    
    2. Set the Speech service key as an app setting:
       az webapp config appsettings set -g ${azurerm_resource_group.main.name} -n ${azurerm_linux_web_app.main.name} --settings AZURE_SPEECH_KEY=<key_from_step_1>
    
    3. Open the frontend (frontend/index.html) and configure:
       - WebSocket URL: wss://${azurerm_linux_web_app.main.default_hostname}/ws
       - Bearer Token: ${local.bearer_token}
    
    4. Test the application by connecting and starting a recording session.
    
    API Bearer Token: ${local.bearer_token}
    WebSocket URL: wss://${azurerm_linux_web_app.main.default_hostname}/ws
  EOT
}