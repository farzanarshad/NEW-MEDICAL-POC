import asyncio
import time
from typing import Callable, Optional, Dict, Any
from azure.cognitiveservices.speech import (
    SpeechConfig, SpeechRecognizer, PushAudioInputStream,
    AudioConfig, RecognitionResult, ResultReason, CancellationReason
)
from azure.cognitiveservices.speech.audio import AudioInputStream
from loguru import logger
from deps import AZURE_SPEECH_REGION, AZURE_SPEECH_KEY, ASR_LANGUAGE, ASR_MEDICAL


class AzureSpeechRecognizer:
    def __init__(self, session_id: str, on_partial: Callable, on_final: Callable, on_error: Callable):
        self.session_id = session_id
        self.on_partial = on_partial
        self.on_final = on_final
        self.on_error = on_error
        self.recognizer: Optional[SpeechRecognizer] = None
        self.push_stream: Optional[PushAudioInputStream] = None
        self.audio_config: Optional[AudioConfig] = None
        self.speech_config: Optional[SpeechConfig] = None
        self.is_active = False
        self.start_time = 0.0
        self.segments = []
        
    async def start(self, language: str = ASR_LANGUAGE, medical: bool = ASR_MEDICAL):
        """Start speech recognition"""
        try:
            if not AZURE_SPEECH_KEY:
                raise Exception("Azure Speech key not configured")
            
            # Configure speech service
            self.speech_config = SpeechConfig(
                subscription=AZURE_SPEECH_KEY,
                region=AZURE_SPEECH_REGION
            )
            
            # Configure for medical speech if enabled
            if medical:
                self.speech_config.set_property(
                    "ConversationTranscriptionInRoomAndOnline", "true"
                )
                self.speech_config.set_property(
                    "ConversationTranscriptionWithDiarization", "true"
                )
                # Enable medical dictation
                self.speech_config.set_property(
                    "SpeechServiceConnection_EndSilenceTimeoutMs", "1000"
                )
            
            # Set language
            self.speech_config.speech_recognition_language = language
            
            # Create push stream for audio
            self.push_stream = PushAudioInputStream()
            self.audio_config = AudioConfig(stream=self.push_stream)
            
            # Create recognizer
            self.recognizer = SpeechRecognizer(
                speech_config=self.speech_config,
                audio_config=self.audio_config
            )
            
            # Set up event handlers
            self.recognizer.recognizing.connect(self._on_recognizing)
            self.recognizer.recognized.connect(self._on_recognized)
            self.recognizer.canceled.connect(self._on_canceled)
            self.recognizer.session_started.connect(self._on_session_started)
            self.recognizer.session_stopped.connect(self._on_session_stopped)
            
            # Start recognition
            await asyncio.get_event_loop().run_in_executor(
                None, self.recognizer.start_continuous_recognition
            )
            
            self.is_active = True
            self.start_time = time.time()
            
            logger.info(f"Speech recognition started for session {self.session_id}")
            await self.on_partial({
                "type": "status",
                "message": "recognition-started"
            })
            
        except Exception as e:
            logger.error(f"Failed to start speech recognition: {e}")
            await self.on_error({
                "type": "error",
                "message": f"Failed to start recognition: {str(e)}"
            })
            raise
    
    async def stop(self):
        """Stop speech recognition"""
        try:
            if self.recognizer and self.is_active:
                await asyncio.get_event_loop().run_in_executor(
                    None, self.recognizer.stop_continuous_recognition
                )
                self.is_active = False
                logger.info(f"Speech recognition stopped for session {self.session_id}")
                
        except Exception as e:
            logger.error(f"Error stopping speech recognition: {e}")
    
    async def push_audio(self, audio_data: bytes):
        """Push audio data to the recognition stream"""
        try:
            if self.push_stream and self.is_active:
                await asyncio.get_event_loop().run_in_executor(
                    None, self.push_stream.write, audio_data
                )
        except Exception as e:
            logger.error(f"Error pushing audio data: {e}")
            await self.on_error({
                "type": "error",
                "message": f"Audio processing error: {str(e)}"
            })
    
    def _on_recognizing(self, evt):
        """Handle partial recognition results"""
        try:
            if evt.result.reason == ResultReason.RecognizingSpeech:
                text = evt.result.text
                offset = evt.result.offset / 10000000.0  # Convert to seconds
                duration = evt.result.duration / 10000000.0
                
                segment = {
                    "text": text,
                    "tsStart": offset,
                    "tsEnd": offset + duration
                }
                
                # Send partial result
                asyncio.create_task(self.on_partial({
                    "type": "partial",
                    "text": text,
                    "tsStart": offset,
                    "tsEnd": offset + duration
                }))
                
                logger.debug(f"Partial: {text}")
                
        except Exception as e:
            logger.error(f"Error in partial recognition: {e}")
    
    def _on_recognized(self, evt):
        """Handle final recognition results"""
        try:
            if evt.result.reason == ResultReason.RecognizedSpeech:
                text = evt.result.text
                offset = evt.result.offset / 10000000.0
                duration = evt.result.duration / 10000000.0
                
                segment = {
                    "text": text,
                    "tsStart": offset,
                    "tsEnd": offset + duration
                }
                self.segments.append(segment)
                
                # Send final result
                asyncio.create_task(self.on_final({
                    "type": "final",
                    "text": text,
                    "tsStart": offset,
                    "tsEnd": offset + duration
                }))
                
                logger.info(f"Final: {text}")
                
        except Exception as e:
            logger.error(f"Error in final recognition: {e}")
    
    def _on_canceled(self, evt):
        """Handle recognition cancellation"""
        try:
            if evt.reason == CancellationReason.Error:
                error_details = evt.error_details
                logger.error(f"Recognition canceled: {error_details}")
                asyncio.create_task(self.on_error({
                    "type": "error",
                    "message": f"Recognition error: {error_details}"
                }))
        except Exception as e:
            logger.error(f"Error handling cancellation: {e}")
    
    def _on_session_started(self, evt):
        """Handle session start"""
        logger.info(f"Speech session started for {self.session_id}")
    
    def _on_session_stopped(self, evt):
        """Handle session stop"""
        logger.info(f"Speech session stopped for {self.session_id}")
    
    def get_transcript_data(self) -> Dict[str, Any]:
        """Get transcript data for storage"""
        full_text = " ".join([seg["text"] for seg in self.segments])
        return {
            "segments": self.segments,
            "fullText": full_text
        }
    
    def cleanup(self):
        """Clean up resources"""
        try:
            if self.recognizer:
                self.recognizer.stop_continuous_recognition()
                self.recognizer = None
            if self.push_stream:
                self.push_stream.close()
                self.push_stream = None
        except Exception as e:
            logger.error(f"Error during cleanup: {e}")