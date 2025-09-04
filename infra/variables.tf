variable "project" {
  description = "Project name for resource naming"
  type        = string
}

variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "asr_language" {
  description = "Default speech recognition language"
  type        = string
  default     = "en-US"
}

variable "asr_medical" {
  description = "Enable medical speech recognition"
  type        = bool
  default     = true
}

variable "api_bearer_token" {
  description = "API Bearer token for authentication (auto-generated if empty)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "allowed_origins" {
  description = "List of allowed CORS origins"
  type        = list(string)
  default = [
    "http://localhost:5500",
    "http://127.0.0.1:5500",
    "http://localhost:8000",
    "http://localhost:3000"
  ]
}

variable "app_service_plan_sku" {
  description = "App Service Plan SKU"
  type        = string
  default     = "F1"
}

variable "speech_service_sku" {
  description = "Speech Service SKU"
  type        = string
  default     = "S0"
}