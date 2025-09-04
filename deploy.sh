#!/bin/bash

# Medical Transcription POC Deployment Script
# This script helps deploy the infrastructure and configure the application

set -e

echo "🚀 Medical Transcription POC Deployment Script"
echo "=============================================="

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI is not installed. Please install it first:"
    echo "   https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed. Please install it first:"
    echo "   https://www.terraform.io/downloads.html"
    exit 1
fi

# Check if user is logged in to Azure
if ! az account show &> /dev/null; then
    echo "❌ Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Get project name
read -p "Enter project name (e.g., medasr): " PROJECT_NAME
if [ -z "$PROJECT_NAME" ]; then
    echo "❌ Project name is required"
    exit 1
fi

# Get environment
read -p "Enter environment (dev/staging/prod) [dev]: " ENV_NAME
ENV_NAME=${ENV_NAME:-dev}

# Get location
read -p "Enter Azure region [eastus]: " LOCATION
LOCATION=${LOCATION:-eastus}

echo ""
echo "📋 Deployment Configuration:"
echo "   Project: $PROJECT_NAME"
echo "   Environment: $ENV_NAME"
echo "   Location: $LOCATION"
echo ""

read -p "Continue with deployment? (y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

# Navigate to infra directory
cd infra

# Initialize Terraform
echo "🔧 Initializing Terraform..."
terraform init

# Create terraform.tfvars
echo "📝 Creating terraform.tfvars..."
cat > terraform.tfvars << EOF
project = "$PROJECT_NAME"
env = "$ENV_NAME"
location = "$LOCATION"
asr_language = "en-US"
asr_medical = true
api_bearer_token = ""
allowed_origins = [
  "http://localhost:5500",
  "http://127.0.0.1:5500",
  "http://localhost:8000",
  "http://localhost:3000"
]
app_service_plan_sku = "B1"
speech_service_sku = "S0"
EOF

# Deploy infrastructure
echo "🏗️  Deploying infrastructure..."
terraform apply -auto-approve

# Get outputs
echo "📊 Getting deployment outputs..."
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
WEBAPP_NAME=$(terraform output -raw webapp_name)
SPEECH_NAME=$(terraform output -raw speech_account_name)
BEARER_TOKEN=$(terraform output -raw api_bearer_token)
WEBSOCKET_URL=$(terraform output -raw websocket_url)

echo ""
echo "✅ Infrastructure deployed successfully!"
echo ""

# Get Speech service key
echo "🔑 Getting Speech service key..."
SPEECH_KEY=$(az cognitiveservices account keys list -g "$RESOURCE_GROUP" -n "$SPEECH_NAME" --query "key1" -o tsv)

if [ -z "$SPEECH_KEY" ]; then
    echo "❌ Failed to get Speech service key"
    exit 1
fi

# Set Speech service key
echo "⚙️  Configuring Speech service key..."
az webapp config appsettings set -g "$RESOURCE_GROUP" -n "$WEBAPP_NAME" --settings AZURE_SPEECH_KEY="$SPEECH_KEY"

echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "📋 Configuration Summary:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Web App: $WEBAPP_NAME"
echo "   Speech Service: $SPEECH_NAME"
echo "   WebSocket URL: $WEBSOCKET_URL"
echo "   Bearer Token: $BEARER_TOKEN"
echo ""
echo "🚀 Next Steps:"
echo "   1. Open frontend/index.html in your browser"
echo "   2. Configure WebSocket URL: $WEBSOCKET_URL"
echo "   3. Configure Bearer Token: $BEARER_TOKEN"
echo "   4. Click Connect and Start Recording"
echo ""
echo "📚 For more information, see README.md"