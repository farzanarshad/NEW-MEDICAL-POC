#!/bin/bash

# Deployment Configuration Switcher
# This script helps switch between different deployment options

set -e

echo "🔄 Medical Transcription POC - Deployment Configuration Switcher"
echo "=============================================================="

# Check current configuration
if [ -f "main.tf" ]; then
    echo "📋 Current configuration:"
    if grep -q "azurerm_linux_virtual_machine" main.tf; then
        echo "   ✅ VM-based deployment (Virtual Machine)"
    elif grep -q "azurerm_container_group" main.tf; then
        echo "   ✅ Container-based deployment (Azure Container Instances)"
    elif grep -q "azurerm_linux_function_app" main.tf; then
        echo "   ✅ Function-based deployment (Azure Functions)"
    elif grep -q "azurerm_linux_web_app" main.tf; then
        echo "   ✅ App Service-based deployment (Azure App Service)"
    else
        echo "   ❓ Unknown configuration"
    fi
else
    echo "❌ No main.tf found"
    exit 1
fi

echo ""
echo "🎯 Available deployment options:"
echo "   1. Virtual Machine (Recommended - No quota issues)"
echo "   2. Azure Container Instances (Alternative)"
echo "   3. Azure Functions (Alternative)"
echo "   4. Azure App Service (May have quota issues)"
echo ""

read -p "Choose deployment option (1-4): " OPTION

case $OPTION in
    1)
        echo "🖥️  Switching to VM-based deployment..."
        if [ -f "main-app-service.tf.backup" ]; then
            mv main.tf main-app-service.tf.backup
        fi
        if [ -f "main-aci.tf.backup" ]; then
            mv main.tf main-aci.tf.backup
        fi
        if [ -f "main-functions.tf.backup" ]; then
            mv main.tf main-functions.tf.backup
        fi
        mv main-vm.tf.backup main.tf 2>/dev/null || echo "VM configuration already active"
        echo "✅ VM-based deployment configured"
        echo "🚀 Run: ./deploy-vm.sh"
        ;;
    2)
        echo "🐳 Switching to Container-based deployment..."
        mv main.tf main-vm.tf.backup
        mv main-aci.tf.backup main.tf
        echo "✅ Container-based deployment configured"
        echo "🚀 Run: ./deploy-alternative.sh and choose option 2"
        ;;
    3)
        echo "⚡ Switching to Function-based deployment..."
        mv main.tf main-vm.tf.backup
        mv main-functions.tf.backup main.tf
        echo "✅ Function-based deployment configured"
        echo "🚀 Run: ./deploy-alternative.sh and choose option 1"
        ;;
    4)
        echo "🌐 Switching to App Service-based deployment..."
        mv main.tf main-vm.tf.backup
        mv main-app-service.tf.backup main.tf
        echo "✅ App Service-based deployment configured"
        echo "🚀 Run: ./deploy.sh"
        ;;
    *)
        echo "❌ Invalid option"
        exit 1
        ;;
esac

echo ""
echo "📋 Next steps:"
echo "   1. Run the appropriate deployment script"
echo "   2. Follow the deployment instructions"
echo "   3. Configure the application"
echo ""
echo "📚 For more information, see README.md"