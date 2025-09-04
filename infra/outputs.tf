output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "vm_name" {
  description = "Name of the virtual machine"
  value       = azurerm_linux_virtual_machine.main.name
}

output "vm_public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.main.ip_address
}

output "vm_ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh azureuser@${azurerm_public_ip.main.ip_address}"
  sensitive   = true
}

output "vm_password" {
  description = "VM admin password"
  value       = random_password.vm_password.result
  sensitive   = true
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
  value       = azurerm_linux_virtual_machine.main.identity[0].principal_id
  sensitive   = true
}

output "api_bearer_token" {
  description = "Generated API Bearer token"
  value       = local.bearer_token
  sensitive   = true
}

output "application_url" {
  description = "URL of the application"
  value       = "http://${azurerm_public_ip.main.ip_address}"
}

output "websocket_url" {
  description = "WebSocket URL for the application"
  value       = "ws://${azurerm_public_ip.main.ip_address}/ws"
}

output "deployment_instructions" {
  description = "Instructions for completing the deployment"
  value = <<-EOT
    Deployment completed successfully!
    
    Next steps:
    1. Get the Speech service key:
       az cognitiveservices account keys list -g ${azurerm_resource_group.main.name} -n ${azurerm_cognitive_account.speech.name}
    
    2. SSH into the VM and set the Speech service key:
       ssh azureuser@${azurerm_public_ip.main.ip_address}
       sudo nano /opt/medical-transcribe/.env
       # Add AZURE_SPEECH_KEY=<key_from_step_1>
       sudo systemctl restart medical-transcribe
    
    3. Open the frontend (frontend/index.html) and configure:
       - WebSocket URL: ws://${azurerm_public_ip.main.ip_address}/ws
       - Bearer Token: (see api_bearer_token output)
    
    4. Test the application by connecting and starting a recording session.
    
    VM Public IP: ${azurerm_public_ip.main.ip_address}
    SSH Command: ssh azureuser@${azurerm_public_ip.main.ip_address}
    Application URL: http://${azurerm_public_ip.main.ip_address}
    WebSocket URL: ws://${azurerm_public_ip.main.ip_address}/ws
  EOT
  sensitive = true
}