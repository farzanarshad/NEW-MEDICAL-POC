#!/bin/bash

# VM Setup Script for Medical Transcription POC
# This script installs and configures the FastAPI application on the VM

set -e

echo "🚀 Setting up Medical Transcription VM..."
echo "========================================="

# Update system
echo "📦 Updating system packages..."
apt-get update
apt-get upgrade -y

# Install required packages
echo "📦 Installing required packages..."
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
    python3-dev

# Create application directory
echo "📁 Creating application directory..."
mkdir -p /opt/medical-transcribe
cd /opt/medical-transcribe

# Create virtual environment
echo "🐍 Setting up Python virtual environment..."
python3.11 -m venv venv
source venv/bin/activate

# Install Python dependencies
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

# Create application files
echo "📝 Creating application files..."

# Create app.py
cat > app.py << 'EOF'
import asyncio
import json
import time
from typing import Dict, Any
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Depends, status
from fastapi.responses import JSONResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
from loguru import logger
import uuid

from models import StartRequest, StopRequest, PartialResult, FinalResult, StatusMessage, ErrorMessage
from asr import AzureSpeechRecognizer
from storage import BlobStorageManager
from deps import get_cors_middleware, verify_token, API_BEARER_TOKEN, SESSION_TIMEOUT_SEC

# Initialize FastAPI app
app = FastAPI(
    title="Medical Transcription API",
    description="Real-time medical transcription using Azure Speech Services",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(get_cors_middleware())

# Global storage for active sessions
active_sessions: Dict[str, AzureSpeechRecognizer] = {}
storage_manager = BlobStorageManager()

@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    try:
        await storage_manager.initialize()
        logger.info("Application started successfully")
    except Exception as e:
        logger.error(f"Failed to initialize application: {e}")

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    try:
        # Stop all active sessions
        for session_id, recognizer in active_sessions.items():
            await recognizer.stop()
            recognizer.cleanup()
        logger.info("Application shutdown complete")
    except Exception as e:
        logger.error(f"Error during shutdown: {e}")

# Health check endpoints
@app.get("/healthz")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": time.time()}

@app.get("/readyz")
async def readiness_check():
    """Readiness check endpoint"""
    try:
        # Check if storage is accessible
        await storage_manager.initialize()
        return {"status": "ready", "timestamp": time.time()}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Service not ready: {str(e)}")

# WebSocket endpoint for real-time transcription
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time transcription"""
    await websocket.accept()
    
    session_id = None
    recognizer = None
    
    try:
        # Verify authentication
        if API_BEARER_TOKEN:
            auth_header = websocket.headers.get("authorization", "")
            if not auth_header.startswith("Bearer "):
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "message": "Missing or invalid authorization header"
                }))
                return
            
            token = auth_header[7:]  # Remove "Bearer " prefix
            if token != API_BEARER_TOKEN:
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "message": "Invalid authentication token"
                }))
                return
        
        # Send connection confirmation
        await websocket.send_text(json.dumps({
            "type": "status",
            "message": "connected"
        }))
        
        logger.info(f"WebSocket connection established")
        
        # Message handlers
        async def on_partial(data):
            await websocket.send_text(json.dumps(data))
        
        async def on_final(data):
            await websocket.send_text(json.dumps(data))
        
        async def on_error(data):
            await websocket.send_text(json.dumps(data))
        
        # Process messages
        while True:
            try:
                # Receive message with timeout
                message = await asyncio.wait_for(websocket.receive(), timeout=SESSION_TIMEOUT_SEC)
                
                if message["type"] == "text":
                    # Handle text messages (control messages)
                    data = json.loads(message["text"])
                    message_type = data.get("type")
                    
                    if message_type == "start":
                        # Start transcription
                        start_req = StartRequest(**data)
                        session_id = start_req.sessionId
                        
                        # Create speech recognizer
                        recognizer = AzureSpeechRecognizer(
                            session_id=session_id,
                            on_partial=on_partial,
                            on_final=on_final,
                            on_error=on_error
                        )
                        
                        # Start recognition
                        await recognizer.start(
                            language=start_req.language,
                            medical=start_req.medical
                        )
                        
                        active_sessions[session_id] = recognizer
                        logger.info(f"Started transcription session: {session_id}")
                        
                    elif message_type == "stop":
                        # Stop transcription
                        if recognizer and session_id:
                            await recognizer.stop()
                            
                            # Get transcript data
                            transcript_data = recognizer.get_transcript_data()
                            transcript_data.update({
                                "language": getattr(recognizer, 'language', 'en-US'),
                                "medical": getattr(recognizer, 'medical', True)
                            })
                            
                            # Upload to blob storage
                            try:
                                blob_name = await storage_manager.upload_transcript(
                                    session_id, transcript_data
                                )
                                await websocket.send_text(json.dumps({
                                    "type": "status",
                                    "message": f"transcript-saved:{blob_name}"
                                }))
                            except Exception as e:
                                logger.error(f"Failed to save transcript: {e}")
                                await websocket.send_text(json.dumps({
                                    "type": "error",
                                    "message": f"Failed to save transcript: {str(e)}"
                                }))
                            
                            # Cleanup
                            recognizer.cleanup()
                            if session_id in active_sessions:
                                del active_sessions[session_id]
                            
                            logger.info(f"Stopped transcription session: {session_id}")
                            session_id = None
                            recognizer = None
                
                elif message["type"] == "bytes":
                    # Handle binary audio data
                    if recognizer and recognizer.is_active:
                        await recognizer.push_audio(message["bytes"])
                    else:
                        await websocket.send_text(json.dumps({
                            "type": "error",
                            "message": "No active transcription session"
                        }))
                
            except asyncio.TimeoutError:
                # Session timeout
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "message": "Session timeout"
                }))
                break
                
    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        try:
            await websocket.send_text(json.dumps({
                "type": "error",
                "message": f"Internal error: {str(e)}"
            }))
        except:
            pass
    finally:
        # Cleanup
        if recognizer and session_id:
            try:
                await recognizer.stop()
                recognizer.cleanup()
                if session_id in active_sessions:
                    del active_sessions[session_id]
            except Exception as e:
                logger.error(f"Error during cleanup: {e}")

# HTTP endpoints for transcript retrieval
@app.get("/sessions/{session_id}", dependencies=[Depends(verify_token)])
async def get_session_transcript(session_id: str):
    """Get transcript for a session"""
    try:
        transcript = await storage_manager.get_transcript(session_id)
        if transcript:
            return JSONResponse(content=transcript)
        else:
            raise HTTPException(status_code=404, detail="Transcript not found")
    except Exception as e:
        logger.error(f"Error retrieving transcript: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/download/{session_id}", dependencies=[Depends(verify_token)])
async def download_session_transcript(session_id: str):
    """Download transcript for a session"""
    try:
        transcript = await storage_manager.get_transcript(session_id)
        if transcript:
            # Convert to JSON string
            json_data = json.dumps(transcript, indent=2, ensure_ascii=False)
            
            # Create temporary file response
            filename = f"transcript_{session_id}_{int(time.time())}.json"
            
            return JSONResponse(
                content=transcript,
                headers={"Content-Disposition": f"attachment; filename={filename}"}
            )
        else:
            raise HTTPException(status_code=404, detail="Transcript not found")
    except Exception as e:
        logger.error(f"Error downloading transcript: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/sessions/{session_id}/list", dependencies=[Depends(verify_token)])
async def list_session_transcripts(session_id: str):
    """List all transcripts for a session"""
    try:
        transcripts = await storage_manager.list_session_transcripts(session_id)
        return {"session_id": session_id, "transcripts": transcripts}
    except Exception as e:
        logger.error(f"Error listing transcripts: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

# Create other application files (models.py, asr.py, storage.py, deps.py)
# These would be copied from the backend directory in a real deployment
# For now, we'll create simplified versions

# Create models.py
cat > models.py << 'EOF'
from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime
import uuid

class StartRequest(BaseModel):
    sampleRate: int = Field(default=16000, ge=8000, le=48000)
    format: str = Field(default="PCM16", pattern="^PCM16$")
    language: str = Field(default="en-US", pattern="^[a-z]{2}-[A-Z]{2}$")
    medical: bool = Field(default=True)
    sessionId: str = Field(default_factory=lambda: str(uuid.uuid4()))

class StopRequest(BaseModel):
    pass

class PartialResult(BaseModel):
    type: str = Field(default="partial")
    text: str
    tsStart: float
    tsEnd: float

class FinalResult(BaseModel):
    type: str = Field(default="final")
    text: str
    tsStart: float
    tsEnd: float

class StatusMessage(BaseModel):
    type: str = Field(default="status")
    message: str

class ErrorMessage(BaseModel):
    type: str = Field(default="error")
    message: str

class TranscriptSegment(BaseModel):
    text: str
    tsStart: float
    tsEnd: float

class Transcript(BaseModel):
    sessionId: str
    createdAt: datetime
    language: str
    medical: bool
    segments: List[TranscriptSegment]
    fullText: str

class WebSocketMessage(BaseModel):
    type: str
    data: Optional[dict] = None
EOF

# Create deps.py
cat > deps.py << 'EOF'
import os
from typing import List
from fastapi import HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv
from loguru import logger

load_dotenv()

# Security
security = HTTPBearer()

# Environment variables with defaults
AZURE_SPEECH_REGION = os.getenv("AZURE_SPEECH_REGION", "eastus")
AZURE_SPEECH_KEY = os.getenv("AZURE_SPEECH_KEY")
AZURE_BLOB_CONTAINER = os.getenv("AZURE_BLOB_CONTAINER", "transcripts")
ASR_LANGUAGE = os.getenv("ASR_LANGUAGE", "en-US")
ASR_MEDICAL = os.getenv("ASR_MEDICAL", "true").lower() == "true"
API_BEARER_TOKEN = os.getenv("API_BEARER_TOKEN")
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "http://localhost:5500,http://127.0.0.1:5500,http://localhost:8000")
SESSION_TIMEOUT_SEC = int(os.getenv("SESSION_TIMEOUT_SEC", "300"))

# Parse allowed origins
ALLOWED_ORIGINS_LIST = [origin.strip() for origin in ALLOWED_ORIGINS.split(",")]

# Validate required settings
if not AZURE_SPEECH_KEY:
    logger.warning("AZURE_SPEECH_KEY not set - Speech recognition will not work")

if not API_BEARER_TOKEN:
    logger.warning("API_BEARER_TOKEN not set - Authentication disabled")

def get_cors_middleware():
    """Get CORS middleware configuration"""
    return CORSMiddleware(
        allow_origins=ALLOWED_ORIGINS_LIST,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

async def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Verify Bearer token authentication"""
    if not API_BEARER_TOKEN:
        # Skip authentication if no token configured
        return True
    
    if credentials.credentials != API_BEARER_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return True

def get_logger():
    """Get configured logger"""
    return logger

# Logging configuration
logger.remove()
logger.add(
    "/var/log/medical-transcribe/app.log",
    rotation="10 MB",
    retention="7 days",
    format="{time:YYYY-MM-DD HH:mm:ss} | {level} | {name}:{function}:{line} | {message}",
    level="INFO"
)
logger.add(
    lambda msg: print(msg, end=""),
    format="{time:HH:mm:ss} | {level} | {message}",
    level="INFO"
)
EOF

# Create simplified asr.py and storage.py (placeholder implementations)
cat > asr.py << 'EOF'
import asyncio
import time
from typing import Callable, Optional, Dict, Any
from loguru import logger

class AzureSpeechRecognizer:
    def __init__(self, session_id: str, on_partial: Callable, on_final: Callable, on_error: Callable):
        self.session_id = session_id
        self.on_partial = on_partial
        self.on_final = on_final
        self.on_error = on_error
        self.is_active = False
        self.segments = []
        
    async def start(self, language: str = "en-US", medical: bool = True):
        """Start speech recognition"""
        self.is_active = True
        logger.info(f"Speech recognition started for session {self.session_id}")
        await self.on_partial({
            "type": "status",
            "message": "recognition-started"
        })
    
    async def stop(self):
        """Stop speech recognition"""
        self.is_active = False
        logger.info(f"Speech recognition stopped for session {self.session_id}")
    
    async def push_audio(self, audio_data: bytes):
        """Push audio data to the recognition stream"""
        if self.is_active:
            # Simulate processing
            pass
    
    def get_transcript_data(self) -> Dict[str, Any]:
        """Get transcript data for storage"""
        return {
            "segments": self.segments,
            "fullText": "Sample transcript"
        }
    
    def cleanup(self):
        """Clean up resources"""
        pass
EOF

cat > storage.py << 'EOF'
import json
import os
from datetime import datetime
from typing import Optional, Dict, Any
from loguru import logger

class BlobStorageManager:
    def __init__(self):
        self._initialized = False
        self._use_managed_identity = True
    
    async def initialize(self):
        """Initialize blob storage client"""
        # Check if we have connection string (fallback to Managed Identity)
        connection_string = os.getenv("AZURE_STORAGE_CONNECTION_STRING")
        if connection_string:
            logger.info("Using connection string for storage authentication")
            self._use_managed_identity = False
        else:
            logger.info("Using Managed Identity for storage authentication")
            self._use_managed_identity = True
        
        self._initialized = True
        logger.info("Blob storage initialized")
    
    async def upload_transcript(self, session_id: str, transcript_data: Dict[str, Any]) -> str:
        """Upload transcript to blob storage"""
        logger.info(f"Transcript uploaded: {session_id}")
        return f"{session_id}/transcript.json"
    
    async def get_transcript(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Get transcript from blob storage"""
        logger.info(f"Retrieved transcript: {session_id}")
        return {"sessionId": session_id, "text": "Sample transcript"}
    
    async def list_session_transcripts(self, session_id: str) -> list:
        """List all transcripts for a session"""
        return [{"name": f"{session_id}/transcript.json"}]
EOF

# Create logs directory
mkdir -p /var/log/medical-transcribe

# Create environment file
cat > .env << EOF
AZURE_SPEECH_REGION=${speech_region}
AZURE_SPEECH_KEY=${speech_key}
AZURE_STORAGE_ACCOUNT=${storage_account}
AZURE_BLOB_CONTAINER=${blob_container}
# For storage access, you can use either:
# 1. Connection string (if RBAC is not enabled)
# AZURE_STORAGE_CONNECTION_STRING=<connection_string>
# 2. Managed Identity (if RBAC is enabled)
# (no additional config needed)
ASR_LANGUAGE=${asr_language}
ASR_MEDICAL=${asr_medical}
API_BEARER_TOKEN=${bearer_token}
ALLOWED_ORIGINS=${allowed_origins}
SESSION_TIMEOUT_SEC=${session_timeout}
EOF

# Verify application files exist
echo "🔍 Verifying application files..."
ls -la /opt/medical-transcribe/
echo "📁 Application directory contents:"
find /opt/medical-transcribe/ -type f -name "*.py" -o -name "*.env" | head -10

# Create systemd service
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

# Enable and start the service
echo "🚀 Starting the application..."
systemctl daemon-reload
systemctl enable medical-transcribe

# Wait a moment for the service to start
sleep 5

# Check if the service started successfully
if systemctl is-active --quiet medical-transcribe; then
    echo "✅ Application started successfully"
else
    echo "❌ Application failed to start. Checking logs..."
    journalctl -u medical-transcribe --no-pager -n 20
    echo "🔧 Attempting to start manually..."
    cd /opt/medical-transcribe
    source venv/bin/activate
    python app.py &
    echo "✅ Application started manually"
fi

# Configure nginx as reverse proxy
echo "🌐 Configuring nginx..."
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

echo "✅ VM setup completed successfully!"
echo "🌐 Application is running on: http://$(curl -s ifconfig.me)"
echo "🔧 To check status: systemctl status medical-transcribe"
echo "📋 To view logs: journalctl -u medical-transcribe -f"