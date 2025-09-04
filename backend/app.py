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