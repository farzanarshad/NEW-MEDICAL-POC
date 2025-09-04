#!/bin/bash

# Alternative Deployment Script for Quota Issues
# This script tries different deployment approaches

set -e

echo "🚀 Alternative Deployment for Quota Issues"
echo "=========================================="

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI is not installed. Please install it first:"
    echo "   https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
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

echo ""
echo "🔍 Checking subscription limits and available options..."
echo ""

# Check what's available
echo "📊 Checking App Service Plan quotas in different regions:"
REGIONS=("eastus" "westus2" "centralus" "southcentralus" "northcentralus" "canadacentral" "westeurope")

for region in "${REGIONS[@]}"; do
    echo "Checking $region..."
    QUOTA=$(az vm list-usage --location "$region" --query "[?name.value=='AppServicePlans'].{Region:name.localizedValue, Limit:limit, Used:currentValue}" -o table 2>/dev/null || echo "No quota info available")
    echo "$QUOTA"
    echo ""
done

echo "💡 Available deployment options:"
echo "1. Try Azure Functions (Consumption plan - often has quota)"
echo "2. Try Azure Container Instances (no App Service Plan needed)"
echo "3. Use existing App Service Plan if available"
echo "4. Request quota increase from Microsoft"
echo "5. Try a different subscription"
echo ""

read -p "Choose deployment option (1-5): " OPTION

case $OPTION in
    1)
        echo "🔧 Deploying with Azure Functions..."
        deploy_functions
        ;;
    2)
        echo "🔧 Deploying with Azure Container Instances..."
        deploy_aci
        ;;
    3)
        echo "🔧 Using existing App Service Plan..."
        use_existing_plan
        ;;
    4)
        echo "📞 Request quota increase:"
        echo "   https://docs.microsoft.com/en-us/azure/azure-portal/supportability/resource-manager-core-quotas-request"
        ;;
    5)
        echo "🔄 Switch to a different subscription:"
        echo "   az account list --output table"
        echo "   az account set --subscription <subscription-id>"
        ;;
    *)
        echo "❌ Invalid option"
        exit 1
        ;;
esac

deploy_functions() {
    echo "📝 Creating Azure Functions deployment..."
    
    # Create terraform.tfvars for functions
    cat > infra/terraform.tfvars << EOF
project = "$PROJECT_NAME"
env = "dev"
location = "eastus"
asr_language = "en-US"
asr_medical = true
api_bearer_token = ""
allowed_origins = [
  "http://localhost:5500",
  "http://127.0.0.1:5500",
  "http://localhost:8000",
  "http://localhost:3000"
]
speech_service_sku = "S0"
EOF
    
    # Copy functions configuration
    cp infra/main-functions.tf infra/main.tf.backup
    cp infra/main-functions.tf infra/main.tf
    
    echo "🏗️  Deploying Azure Functions infrastructure..."
    cd infra
    terraform init
    terraform apply -auto-approve
    
    echo "✅ Azure Functions deployed successfully!"
    echo "📋 Next steps:"
    echo "   1. Deploy your function code to the Function App"
    echo "   2. Configure the Speech service key"
    echo "   3. Test the WebSocket endpoint"
}

deploy_aci() {
    echo "📝 Creating Azure Container Instances deployment..."
    
    # Create terraform.tfvars for ACI
    cat > infra/terraform.tfvars << EOF
project = "$PROJECT_NAME"
env = "dev"
location = "eastus"
asr_language = "en-US"
asr_medical = true
api_bearer_token = ""
allowed_origins = [
  "http://localhost:5500",
  "http://127.0.0.1:5500",
  "http://localhost:8000",
  "http://localhost:3000"
]
speech_service_sku = "S0"
EOF
    
    # Copy ACI configuration
    cp infra/main-aci.tf infra/main.tf.backup
    cp infra/main-aci.tf infra/main.tf
    
    echo "🏗️  Deploying Azure Container Instances infrastructure..."
    cd infra
    terraform init
    terraform apply -auto-approve
    
    echo "✅ Azure Container Instances deployed successfully!"
    echo "📋 Next steps:"
    echo "   1. Build and push your Docker image to ACR"
    echo "   2. Configure the Speech service key"
    echo "   3. Test the WebSocket endpoint"
}

use_existing_plan() {
    echo "🔍 Checking for existing App Service Plans..."
    
    # List existing plans
    EXISTING_PLANS=$(az appservice plan list --query "[].{Name:name, SKU:sku.name, Location:location}" -o table)
    
    if [ ! -z "$EXISTING_PLANS" ]; then
        echo "Found existing plans:"
        echo "$EXISTING_PLANS"
        echo ""
        echo "💡 You can modify the Terraform configuration to use an existing plan"
        echo "   by setting the service_plan_id to an existing plan's ID"
    else
        echo "❌ No existing App Service Plans found"
        echo "💡 Try options 1 or 2 instead"
    fi
}