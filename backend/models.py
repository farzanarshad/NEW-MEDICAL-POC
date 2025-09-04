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