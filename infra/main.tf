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
  
  # Handle soft-deleted resources
  restore = false
  
  tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# App Service Plan
resource "azurerm_service_plan" "main" {
  name                = "${local.name_prefix}-plan"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku
  
  tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# App Service
resource "azurerm_linux_web_app" "main" {
  name                = "${local.name_prefix}-app"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  
  # Enable WebSockets
  site_config {
    application_stack {
      python_version = "3.11"
    }
    
    websockets_enabled = true
    
    # Health check
    health_check_path = "/healthz"
    
    # CORS settings
    cors {
      allowed_origins = var.allowed_origins
      support_credentials = true
    }
  }
  
  # System-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # App settings
  app_settings = {
    # Azure Speech settings
    "AZURE_SPEECH_REGION" = azurerm_cognitive_account.speech.location
    "AZURE_SPEECH_KEY"    = "" # Will be set manually after deployment
    
    # Storage settings
    "AZURE_STORAGE_ACCOUNT" = azurerm_storage_account.main.name
    "AZURE_BLOB_CONTAINER" = azurerm_storage_container.transcripts.name
    
    # Application settings
    "ASR_LANGUAGE"         = var.asr_language
    "ASR_MEDICAL"          = var.asr_medical
    "API_BEARER_TOKEN"     = local.bearer_token
    "ALLOWED_ORIGINS"      = join(",", var.allowed_origins)
    "SESSION_TIMEOUT_SEC"  = "300"
    
    # Logging
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"      = "true"
  }
  
  tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# Role assignment for App Service to access Storage
resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# Role assignment for App Service to access Cognitive Services
resource "azurerm_role_assignment" "cognitive_services_user" {
  scope                = azurerm_cognitive_account.speech.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}