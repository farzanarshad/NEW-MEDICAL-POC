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
    "logs/app.log",
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