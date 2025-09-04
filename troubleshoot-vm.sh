#!/bin/bash

# Troubleshooting script for Medical Transcription VM
# Run this on the VM to diagnose issues

echo "🔍 Medical Transcription VM Troubleshooting"
echo "=========================================="

echo ""
echo "📁 Checking application directory..."
if [ -d "/opt/medical-transcribe" ]; then
    echo "✅ /opt/medical-transcribe exists"
    echo "📋 Directory contents:"
    ls -la /opt/medical-transcribe/
    
    echo ""
    echo "📋 Python files:"
    find /opt/medical-transcribe/ -name "*.py" -type f
    
    echo ""
    echo "📋 Environment file:"
    if [ -f "/opt/medical-transcribe/.env" ]; then
        echo "✅ .env file exists"
        echo "📋 .env contents (without sensitive data):"
        grep -v -E "(KEY|TOKEN|PASSWORD)" /opt/medical-transcribe/.env || echo "No non-sensitive content found"
    else
        echo "❌ .env file missing"
    fi
else
    echo "❌ /opt/medical-transcribe directory missing"
fi

echo ""
echo "🐍 Checking Python virtual environment..."
if [ -d "/opt/medical-transcribe/venv" ]; then
    echo "✅ Virtual environment exists"
    echo "📋 Python version:"
    /opt/medical-transcribe/venv/bin/python --version
    
    echo "📋 Installed packages:"
    /opt/medical-transcribe/venv/bin/pip list | grep -E "(fastapi|uvicorn|azure|pydantic)"
else
    echo "❌ Virtual environment missing"
fi

echo ""
echo "🔧 Checking systemd service..."
if systemctl list-unit-files | grep -q medical-transcribe; then
    echo "✅ Service exists"
    echo "📋 Service status:"
    systemctl status medical-transcribe --no-pager -l
    
    echo ""
    echo "📋 Service logs (last 20 lines):"
    journalctl -u medical-transcribe --no-pager -n 20
else
    echo "❌ Service not found"
fi

echo ""
echo "🌐 Checking nginx..."
if systemctl is-active --quiet nginx; then
    echo "✅ Nginx is running"
    echo "📋 Nginx status:"
    systemctl status nginx --no-pager -l
else
    echo "❌ Nginx is not running"
fi

echo ""
echo "🔌 Checking port 8000..."
if netstat -tlnp | grep :8000; then
    echo "✅ Port 8000 is listening"
else
    echo "❌ Port 8000 is not listening"
fi

echo ""
echo "🌐 Checking external connectivity..."
if curl -s http://localhost:8000/healthz > /dev/null; then
    echo "✅ Application responds to health check"
else
    echo "❌ Application does not respond to health check"
fi

echo ""
echo "📊 System resources..."
echo "📋 Memory usage:"
free -h

echo "📋 Disk usage:"
df -h /

echo "📋 CPU usage:"
top -bn1 | grep "Cpu(s)"

echo ""
echo "🔧 Manual start attempt..."
echo "📋 Trying to start application manually:"
cd /opt/medical-transcribe
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    echo "📋 Python path: $(which python)"
    echo "📋 Python version: $(python --version)"
    echo "📋 Starting application..."
    timeout 10 python app.py || echo "❌ Application failed to start or timed out"
else
    echo "❌ Virtual environment not found"
fi

echo ""
echo "✅ Troubleshooting complete!"
echo "📚 Check the output above for issues and solutions."