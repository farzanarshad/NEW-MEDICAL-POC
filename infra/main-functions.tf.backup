# Alternative deployment using Azure Functions
# This often has better quota availability than App Service Plans

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

# Application Insights
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

# Service Plan for Functions (Consumption plan - pay per use)
resource "azurerm_service_plan" "main" {
  name                = "${local.name_prefix}-plan"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption plan
  
  tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# Function App
resource "azurerm_linux_function_app" "main" {
  name                       = "${local.name_prefix}-func"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  service_plan_id            = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  site_config {
    application_stack {
      python {
        version = "3.11"
      }
    }
    
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
  }
  
  app_settings = {
    "AZURE_SPEECH_REGION" = azurerm_cognitive_account.speech.location
    "AZURE_SPEECH_KEY"    = "" # Will be set manually
    "AZURE_STORAGE_ACCOUNT" = azurerm_storage_account.main.name
    "AZURE_BLOB_CONTAINER" = azurerm_storage_container.transcripts.name
    "ASR_LANGUAGE"         = var.asr_language
    "ASR_MEDICAL"          = var.asr_medical
    "API_BEARER_TOKEN"     = local.bearer_token
    "ALLOWED_ORIGINS"      = join(",", var.allowed_origins)
    "SESSION_TIMEOUT_SEC"  = "300"
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
  }
  
  tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}