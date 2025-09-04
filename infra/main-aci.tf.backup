# Alternative deployment using Azure Container Instances
# This avoids App Service Plan quota issues

locals {
  # Resource naming
  name_prefix = "${var.project}-${var.env}"
  
  # Generate random suffix for uniqueness
  random_suffix = random_string.suffix.result
  
  # Generate bearer token if not provided
  bearer_token = var.api_bearer_token != "" ? var.api_bearer_token : random_string.bearer_token.result
}

# Random resources
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "random_string" "bearer_token" {
  length  = 32
  special = false
  upper   = true
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  
  tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# Storage Account
resource "azurerm_storage_account" "main" {
  name                     = "${replace(local.name_prefix, "-", "")}st${local.random_suffix}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  
  # Enable blob storage
  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# Blob Container
resource "azurerm_storage_container" "transcripts" {
  name                  = "transcripts"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Cognitive Services (Speech)
resource "azurerm_cognitive_account" "speech" {
  name                = "${local.name_prefix}-speech"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "SpeechServices"
  sku_name            = var.speech_service_sku
  
  tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# Container Registry (for storing the Docker image)
resource "azurerm_container_registry" "main" {
  name                = "${replace(local.name_prefix, "-", "")}acr${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
  
  tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# Application Insights (for monitoring)
resource "azurerm_application_insights" "main" {
  name                = "${local.name_prefix}-insights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# Container Group (replaces App Service)
resource "azurerm_container_group" "main" {
  name                = "${local.name_prefix}-app"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  restart_policy      = "Always"
  ip_address_type     = "Public"
  dns_name_label      = "${replace(local.name_prefix, "-", "")}app${local.random_suffix}"
  
  container {
    name   = "app"
    image  = "${azurerm_container_registry.main.login_server}/medical-transcribe:latest"
    cpu    = "1.0"
    memory = "2.0"
    
    ports {
      port     = 8000
      protocol = "TCP"
    }
    
    environment_variables = {
      "AZURE_SPEECH_REGION" = azurerm_cognitive_account.speech.location
      "AZURE_SPEECH_KEY"    = "" # Will be set manually
      "AZURE_STORAGE_ACCOUNT" = azurerm_storage_account.main.name
      "AZURE_BLOB_CONTAINER" = azurerm_storage_container.transcripts.name
      "ASR_LANGUAGE"         = var.asr_language
      "ASR_MEDICAL"          = var.asr_medical
      "API_BEARER_TOKEN"     = local.bearer_token
      "ALLOWED_ORIGINS"      = join(",", var.allowed_origins)
      "SESSION_TIMEOUT_SEC"  = "300"
    }
    
    secure_environment_variables = {
      "AZURE_SPEECH_KEY" = "" # Will be set manually
    }
  }
  
  tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# Role assignment for Container Group to access Storage
resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_container_group.main.identity[0].principal_id
}

# Role assignment for Container Group to access Cognitive Services
resource "azurerm_role_assignment" "cognitive_services_user" {
  scope                = azurerm_cognitive_account.speech.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_container_group.main.identity[0].principal_id
}