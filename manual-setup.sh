#!/bin/bash

# Manual setup script for Medical Transcription VM
# Run this if the automatic setup fails

set -e

echo "🔧 Manual Medical Transcription VM Setup"
echo "======================================"

# Check if we're running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

echo "📁 Creating application directory..."
mkdir -p /opt/medical-transcribe
cd /opt/medical-transcribe

echo "🐍 Setting up Python virtual environment..."
python3.11 -m venv venv
source venv/bin/activate

echo "📦 Installing Python dependencies..."
pip install --upgrade pip
pip install \
    fastapi==0.104.1 \
    uvicorn[standard]==0.24.0 \
    websockets==12.0 \
    azure-cognitiveservices-speech==1.34.0 \
    azure-identity==1.15.0 \
    azure-storage-blob==12.19.0 \
    pydantic==2.5.0 \
    python-dotenv==1.0.0 \
    loguru==0.7.2 \
    python-multipart==0.0.6

echo "📝 Creating application files..."

# Create a simple test app.py
cat > app.py << 'EOF'
import asyncio
import json
import time
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from loguru import logger

app = FastAPI(title="Medical Transcription API", version="1.0.0")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/healthz")
async def health_check():
    return {"status": "healthy", "timestamp": time.time()}

@app.get("/readyz")
async def readiness_check():
    return {"status": "ready", "timestamp": time.time()}

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    await websocket.send_text(json.dumps({"type": "status", "message": "connected"}))
    
    try:
        while True:
            message = await websocket.receive()
            if message["type"] == "text":
                data = json.loads(message["text"])
                await websocket.send_text(json.dumps({
                    "type": "status", 
                    "message": f"received: {data.get('type', 'unknown')}"
                }))
    except WebSocketDisconnect:
        logger.info("WebSocket disconnected")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

echo "📝 Creating environment file..."
cat > .env << EOF
AZURE_SPEECH_REGION=eastus
AZURE_SPEECH_KEY=your_speech_key_here
AZURE_STORAGE_ACCOUNT=your_storage_account
AZURE_BLOB_CONTAINER=transcripts
ASR_LANGUAGE=ml-IN
ASR_MEDICAL=true
API_BEARER_TOKEN=your_bearer_token_here
ALLOWED_ORIGINS=http://localhost:5500,http://127.0.0.1:5500,http://localhost:8000
SESSION_TIMEOUT_SEC=300
EOF

echo "🔧 Creating systemd service..."
cat > /etc/systemd/system/medical-transcribe.service << EOF
[Unit]
Description=Medical Transcription API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/medical-transcribe
Environment=PATH=/opt/medical-transcribe/venv/bin
ExecStart=/opt/medical-transcribe/venv/bin/python app.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "🚀 Starting the application..."
systemctl daemon-reload
systemctl enable medical-transcribe
systemctl start medical-transcribe

echo "⏳ Waiting for application to start..."
sleep 10

if systemctl is-active --quiet medical-transcribe; then
    echo "✅ Application started successfully"
    echo "🌐 Health check: http://localhost:8000/healthz"
    echo "🔧 Service status: systemctl status medical-transcribe"
    echo "📋 Logs: journalctl -u medical-transcribe -f"
else
    echo "❌ Application failed to start"
    echo "📋 Checking logs..."
    journalctl -u medical-transcribe --no-pager -n 20
fi

echo ""
echo "✅ Manual setup complete!"
echo "📚 Next steps:"
echo "   1. Configure your Speech service key in /opt/medical-transcribe/.env"
echo "   2. Restart the service: systemctl restart medical-transcribe"
echo "   3. Test the application: curl http://localhost:8000/healthz"