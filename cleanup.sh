#!/bin/bash

# Azure Resource Cleanup and Quota Check Script
# This script helps resolve deployment issues

set -e

echo "🔧 Azure Resource Cleanup and Quota Check"
echo "========================================="

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

echo "📊 Checking subscription limits..."
echo ""

# Check App Service Plan limits
echo "🔍 App Service Plan Quotas:"
az vm list-usage --location eastus --query "[?name.value=='AppServicePlans']" --output table
echo ""

# Check for soft-deleted Cognitive Services
echo "🔍 Checking for soft-deleted Cognitive Services..."
SOFT_DELETED_SPEECH=$(az cognitiveservices account list-deleted --query "[?name=='grandsi-dev-speech'].name" -o tsv)

if [ ! -z "$SOFT_DELETED_SPEECH" ]; then
    echo "⚠️  Found soft-deleted speech service: $SOFT_DELETED_SPEECH"
    read -p "Do you want to purge it? (y/N): " PURGE_CONFIRM
    if [[ $PURGE_CONFIRM =~ ^[Yy]$ ]]; then
        echo "🗑️  Purging soft-deleted speech service..."
        az cognitiveservices account purge --name grandsi-dev-speech --location eastus --resource-group grandsi-dev-rg
        echo "✅ Soft-deleted speech service purged"
    else
        echo "ℹ️  Skipping purge. You may need to manually handle this."
    fi
else
    echo "✅ No soft-deleted speech services found"
fi

echo ""
echo "🔍 Checking for existing App Service Plans..."
EXISTING_PLANS=$(az appservice plan list --resource-group grandsi-dev-rg --query "[].name" -o tsv)

if [ ! -z "$EXISTING_PLANS" ]; then
    echo "⚠️  Found existing App Service Plans:"
    echo "$EXISTING_PLANS"
    echo ""
    echo "💡 Options:"
    echo "1. Use existing plan (recommended if it has sufficient quota)"
    echo "2. Delete existing plans and create new ones"
    echo "3. Try a different region"
    echo ""
    read -p "Choose option (1/2/3): " OPTION
    
    case $OPTION in
        1)
            echo "ℹ️  You'll need to modify the Terraform configuration to use existing plans"
            ;;
        2)
            echo "🗑️  Deleting existing App Service Plans..."
            for plan in $EXISTING_PLANS; do
                az appservice plan delete --name "$plan" --resource-group grandsi-dev-rg --yes
            done
            echo "✅ Existing plans deleted"
            ;;
        3)
            echo "ℹ️  Try deploying to a different region (e.g., westus2, centralus)"
            ;;
        *)
            echo "❌ Invalid option"
            exit 1
            ;;
    esac
else
    echo "✅ No existing App Service Plans found"
fi

echo ""
echo "🔍 Checking available regions for App Service Plans..."
echo "Available regions with quota:"
az appservice list-locations --sku F1 --output table

echo ""
echo "💡 Recommendations:"
echo "1. If you have no quota for Free VMs, try a different region"
echo "2. Consider upgrading your subscription to get more quota"
echo "3. Use an existing App Service Plan if available"
echo ""
echo "To try a different region, update your terraform.tfvars:"
echo "location = \"westus2\"  # or another region with quota"