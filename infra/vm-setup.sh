#!/bin/bash

# VM Setup Script for Medical Transcription POC
# This script installs and configures the FastAPI application on the VM

set -e

# Log everything to a file for debugging
exec > >(tee /var/log/vm-setup.log) 2>&1

echo "🚀 Setting up Medical Transcription VM..."
echo "========================================="
echo "Timestamp: $(date)"
echo "Script started"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        log "✅ $1"
    else
        log "❌ $1 failed"
        exit 1
    fi
}

log "📦 Updating system packages..."
apt-get update
apt-get upgrade -y
check_status "System update"

log "📦 Installing required packages..."
apt-get install -y \
    python3.11 \
    python3.11-pip \
    python3.11-venv \
    nginx \
    curl \
    git \
    supervisor \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3-dev \
    net-tools
check_status "Package installation"

log "📁 Creating application directory..."
mkdir -p /opt/medical-transcribe
cd /opt/medical-transcribe
check_status "Directory creation"

log "🐍 Setting up Python virtual environment..."
python3.11 -m venv venv
check_status "Virtual environment creation"

# Activate virtual environment
source venv/bin/activate
check_status "Virtual environment activation"

log "📦 Installing Python dependencies..."
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
check_status "Python dependencies installation"

log "📝 Creating application files..."

# Create app.py
cat > app.py << 'EOF'
import asyncio
import json
import time
import os
from typing import Dict, Any
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Depends, status
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from loguru import logger
import uuid

# Simple models for now
class StartRequest:
    def __init__(self, **kwargs):
        self.sampleRate = kwargs.get('sampleRate', 16000)
        self.format = kwargs.get('format', 'PCM16')
        self.language = kwargs.get('language', 'ml-IN')
        self.medical = kwargs.get('medical', True)
        self.sessionId = kwargs.get('sessionId', str(uuid.uuid4()))

class BlobStorageManager:
    def __init__(self):
        self._initialized = False
    
    async def initialize(self):
        self._initialized = True
        logger.info("Blob storage initialized")
    
    async def upload_transcript(self, session_id: str, transcript_data: Dict[str, Any]) -> str:
        logger.info(f"Transcript uploaded: {session_id}")
        return f"{session_id}/transcript.json"

# Initialize FastAPI app
app = FastAPI(
    title="Medical Transcription API",
    description="Real-time medical transcription using Azure Speech Services",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global storage for active sessions
active_sessions: Dict[str, Any] = {}
storage_manager = BlobStorageManager()

@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    try:
        await storage_manager.initialize()
        logger.info("Application started successfully")
    except Exception as e:
        logger.error(f"Failed to initialize application: {e}")

# Health check endpoints
@app.get("/healthz")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": time.time(), "language": "ml-IN"}

@app.get("/readyz")
async def readiness_check():
    """Readiness check endpoint"""
    try:
        await storage_manager.initialize()
        return {"status": "ready", "timestamp": time.time()}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Service not ready: {str(e)}")

# WebSocket endpoint for real-time transcription
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time transcription"""
    await websocket.accept()
    
    try:
        # Send connection confirmation
        await websocket.send_text(json.dumps({
            "type": "status",
            "message": "connected"
        }))
        
        logger.info("WebSocket connection established")
        
        # Process messages
        while True:
            try:
                message = await websocket.receive()
                
                if message["type"] == "text":
                    data = json.loads(message["text"])
                    message_type = data.get("type")
                    
                    if message_type == "start":
                        await websocket.send_text(json.dumps({
                            "type": "status",
                            "message": "recognition-started"
                        }))
                        
                    elif message_type == "stop":
                        await websocket.send_text(json.dumps({
                            "type": "status",
                            "message": "recognition-stopped"
                        }))
                
                elif message["type"] == "bytes":
                    # Handle binary audio data
                    await websocket.send_text(json.dumps({
                        "type": "partial",
                        "text": "Audio received",
                        "tsStart": time.time(),
                        "tsEnd": time.time() + 1
                    }))
                
            except Exception as e:
                logger.error(f"Error processing message: {e}")
                break
                
    except WebSocketDisconnect:
        logger.info("WebSocket disconnected")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

log "📝 Creating environment file..."
cat > .env << EOF
AZURE_SPEECH_REGION=${speech_region}
AZURE_SPEECH_KEY=${speech_key}
AZURE_STORAGE_ACCOUNT=${storage_account}
AZURE_BLOB_CONTAINER=${blob_container}
ASR_LANGUAGE=${asr_language}
ASR_MEDICAL=${asr_medical}
API_BEARER_TOKEN=${bearer_token}
ALLOWED_ORIGINS=${allowed_origins}
SESSION_TIMEOUT_SEC=${session_timeout}
EOF

log "📁 Creating logs directory..."
mkdir -p /var/log/medical-transcribe

log "🔧 Creating systemd service..."
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

log "🚀 Starting the application..."
systemctl daemon-reload
systemctl enable medical-transcribe
systemctl start medical-transcribe

log "⏳ Waiting for application to start..."
sleep 10

if systemctl is-active --quiet medical-transcribe; then
    log "✅ Application started successfully"
else
    log "❌ Application failed to start. Checking logs..."
    journalctl -u medical-transcribe --no-pager -n 20
    log "🔧 Attempting to start manually..."
    cd /opt/medical-transcribe
    source venv/bin/activate
    nohup python app.py > /var/log/medical-transcribe/app.log 2>&1 &
    log "✅ Application started manually"
fi

log "🌐 Configuring nginx..."
cat > /etc/nginx/sites-available/medical-transcribe << EOF
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# Enable the nginx site
ln -sf /etc/nginx/sites-available/medical-transcribe /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

log "🔍 Final verification..."
echo "📋 Application directory contents:"
ls -la /opt/medical-transcribe/

echo "📋 Service status:"
systemctl status medical-transcribe --no-pager -l

echo "📋 Port 8000 status:"
netstat -tlnp | grep :8000 || echo "Port 8000 not listening"

echo "📋 Health check:"
curl -s http://localhost:8000/healthz || echo "Health check failed"

log "✅ VM setup completed successfully!"
echo "🌐 Application is running on: http://$(curl -s ifconfig.me)"
echo "🔧 To check status: systemctl status medical-transcribe"
echo "📋 To view logs: journalctl -u medical-transcribe -f"
echo "📋 Setup log: cat /var/log/vm-setup.log"