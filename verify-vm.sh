#!/bin/bash

# Quick verification script for VM deployment
# Run this after deployment to check if everything is working

echo "🔍 Quick VM Verification"
echo "======================="

echo ""
echo "📁 Checking application directory..."
if [ -d "/opt/medical-transcribe" ]; then
    echo "✅ /opt/medical-transcribe exists"
    ls -la /opt/medical-transcribe/
else
    echo "❌ /opt/medical-transcribe missing"
    echo "📋 Checking if setup script ran..."
    if [ -f "/var/log/vm-setup.log" ]; then
        echo "📋 Setup log exists, checking last 20 lines:"
        tail -20 /var/log/vm-setup.log
    else
        echo "❌ Setup log missing - script didn't run"
    fi
    exit 1
fi

echo ""
echo "🐍 Checking Python environment..."
if [ -d "/opt/medical-transcribe/venv" ]; then
    echo "✅ Virtual environment exists"
    /opt/medical-transcribe/venv/bin/python --version
else
    echo "❌ Virtual environment missing"
fi

echo ""
echo "🔧 Checking systemd service..."
if systemctl is-active --quiet medical-transcribe; then
    echo "✅ Service is running"
else
    echo "❌ Service is not running"
    echo "📋 Service status:"
    systemctl status medical-transcribe --no-pager -l
fi

echo ""
echo "🔌 Checking port 8000..."
if netstat -tlnp | grep :8000; then
    echo "✅ Port 8000 is listening"
else
    echo "❌ Port 8000 is not listening"
fi

echo ""
echo "🌐 Testing health endpoint..."
if curl -s http://localhost:8000/healthz > /dev/null; then
    echo "✅ Health check passed"
    curl -s http://localhost:8000/healthz | jq . || curl -s http://localhost:8000/healthz
else
    echo "❌ Health check failed"
fi

echo ""
echo "📋 Checking logs..."
echo "📋 Recent service logs:"
journalctl -u medical-transcribe --no-pager -n 10

echo ""
echo "✅ Verification complete!"