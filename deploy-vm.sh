#!/bin/bash

# VM-based Deployment Script for Medical Transcription POC
# This script deploys using Azure Virtual Machines to avoid quota issues

set -e

echo "🚀 VM-based Medical Transcription POC Deployment"
echo "================================================"

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
echo "   VM Size: Standard_B1s (1 vCPU, 1 GB RAM)"
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
enable_rbac_assignments = false
allowed_origins = [
  "http://localhost:5500",
  "http://127.0.0.1:5500",
  "http://localhost:8000",
  "http://localhost:3000"
]
speech_service_sku = "S0"
EOF

# Use VM configuration
echo "🖥️  Using VM-based configuration..."
# main.tf is already the VM configuration

# Deploy infrastructure
echo "🏗️  Deploying VM infrastructure..."
terraform apply -auto-approve

# Get outputs
echo "📊 Getting deployment outputs..."
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
SPEECH_NAME=$(terraform output -raw speech_account_name)
STORAGE_ACCOUNT=$(terraform output -raw storage_account_name)
VM_IP=$(terraform output -raw vm_public_ip)
BEARER_TOKEN=$(terraform output -raw api_bearer_token)
VM_PASSWORD=$(terraform output -raw vm_password)

echo ""
echo "✅ VM infrastructure deployed successfully!"
echo ""

# Get Speech service key
echo "🔑 Getting Speech service key..."
SPEECH_KEY=$(az cognitiveservices account keys list -g "$RESOURCE_GROUP" -n "$SPEECH_NAME" --query "key1" -o tsv)

if [ -z "$SPEECH_KEY" ]; then
    echo "❌ Failed to get Speech service key"
    exit 1
fi

echo ""
echo "🎉 VM deployment completed successfully!"
echo ""
echo "📋 Configuration Summary:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   VM Public IP: $VM_IP"
echo "   Speech Service: $SPEECH_NAME"
echo "   Bearer Token: $BEARER_TOKEN"
echo "   VM Password: $VM_PASSWORD"
echo ""
echo "🚀 Next Steps:"
echo "   1. SSH into the VM:"
echo "      ssh azureuser@$VM_IP"
echo "      Password: $VM_PASSWORD"
echo ""
echo "   2. Configure the Speech service key:"
echo "      sudo nano /opt/medical-transcribe/.env"
echo "      # Add: AZURE_SPEECH_KEY=$SPEECH_KEY"
echo ""
echo "   3. Configure Storage access (choose one):"
echo "      Option A - Connection String (recommended for this setup):"
echo "        az storage account show-connection-string -g $RESOURCE_GROUP -n $STORAGE_ACCOUNT"
echo "        # Add: AZURE_STORAGE_CONNECTION_STRING=<connection_string>"
echo "      Option B - Enable RBAC (requires Owner permissions):"
echo "        # Edit terraform.tfvars: enable_rbac_assignments = true"
echo "        # Re-run: terraform apply"
echo ""
echo "   4. Restart the application:"
echo "      sudo systemctl restart medical-transcribe"
echo ""
echo "   5. Open frontend/index.html and configure:"
echo "      - WebSocket URL: ws://$VM_IP/ws"
echo "      - Bearer Token: $BEARER_TOKEN"
echo ""
echo "   6. Test the application by connecting and starting a recording session."
echo ""
echo "🔧 Useful commands:"
echo "   Check app status: systemctl status medical-transcribe"
echo "   View logs: journalctl -u medical-transcribe -f"
echo "   Check nginx: systemctl status nginx"
echo "   Test health: curl http://$VM_IP/healthz"
echo ""
echo "📚 For more information, see README.md"