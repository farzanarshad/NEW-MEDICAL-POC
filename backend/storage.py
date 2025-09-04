import json
import os
from datetime import datetime
from typing import Optional, Dict, Any
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient, ContainerClient
from loguru import logger
from deps import AZURE_BLOB_CONTAINER


class BlobStorageManager:
    def __init__(self):
        self.credential = DefaultAzureCredential()
        self.blob_service_client: Optional[BlobServiceClient] = None
        self.container_client: Optional[ContainerClient] = None
        self._initialized = False
    
    async def initialize(self):
        """Initialize blob storage client"""
        try:
            # Get storage account name from environment
            storage_account = os.getenv("AZURE_STORAGE_ACCOUNT")
            if not storage_account:
                raise Exception("AZURE_STORAGE_ACCOUNT environment variable not set")
            
            # Create blob service client
            account_url = f"https://{storage_account}.blob.core.windows.net"
            self.blob_service_client = BlobServiceClient(
                account_url=account_url,
                credential=self.credential
            )
            
            # Get or create container
            self.container_client = self.blob_service_client.get_container_client(AZURE_BLOB_CONTAINER)
            
            # Ensure container exists
            await self._ensure_container_exists()
            
            self._initialized = True
            logger.info(f"Blob storage initialized for container: {AZURE_BLOB_CONTAINER}")
            
        except Exception as e:
            logger.error(f"Failed to initialize blob storage: {e}")
            raise
    
    async def _ensure_container_exists(self):
        """Ensure the container exists, create if it doesn't"""
        try:
            # Check if container exists
            container_properties = self.container_client.get_container_properties()
            logger.info(f"Container {AZURE_BLOB_CONTAINER} already exists")
        except Exception:
            # Container doesn't exist, create it
            try:
                self.container_client.create_container()
                logger.info(f"Created container: {AZURE_BLOB_CONTAINER}")
            except Exception as e:
                logger.error(f"Failed to create container: {e}")
                raise
    
    async def upload_transcript(self, session_id: str, transcript_data: Dict[str, Any]) -> str:
        """Upload transcript to blob storage"""
        if not self._initialized:
            await self.initialize()
        
        try:
            # Create transcript object
            transcript = {
                "sessionId": session_id,
                "createdAt": datetime.utcnow().isoformat() + "Z",
                "language": transcript_data.get("language", "en-US"),
                "medical": transcript_data.get("medical", True),
                "segments": transcript_data.get("segments", []),
                "fullText": transcript_data.get("fullText", "")
            }
            
            # Create blob name with timestamp
            timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
            blob_name = f"{session_id}/{timestamp}.json"
            
            # Get blob client
            blob_client = self.container_client.get_blob_client(blob_name)
            
            # Upload JSON data
            json_data = json.dumps(transcript, indent=2, ensure_ascii=False)
            blob_client.upload_blob(
                json_data,
                overwrite=True,
                content_settings={"content_type": "application/json"}
            )
            
            logger.info(f"Transcript uploaded: {blob_name}")
            return blob_name
            
        except Exception as e:
            logger.error(f"Failed to upload transcript: {e}")
            raise
    
    async def get_transcript(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Get transcript from blob storage"""
        if not self._initialized:
            await self.initialize()
        
        try:
            # List blobs for the session
            blobs = self.container_client.list_blobs(name_starts_with=f"{session_id}/")
            
            # Get the most recent transcript
            latest_blob = None
            latest_time = None
            
            for blob in blobs:
                if blob.name.endswith('.json'):
                    if latest_time is None or blob.last_modified > latest_time:
                        latest_blob = blob
                        latest_time = blob.last_modified
            
            if latest_blob:
                # Download and parse JSON
                blob_client = self.container_client.get_blob_client(latest_blob.name)
                blob_data = blob_client.download_blob()
                content = blob_data.readall().decode('utf-8')
                transcript = json.loads(content)
                
                logger.info(f"Retrieved transcript: {latest_blob.name}")
                return transcript
            else:
                logger.warning(f"No transcript found for session: {session_id}")
                return None
                
        except Exception as e:
            logger.error(f"Failed to get transcript: {e}")
            raise
    
    async def list_session_transcripts(self, session_id: str) -> list:
        """List all transcripts for a session"""
        if not self._initialized:
            await self.initialize()
        
        try:
            blobs = self.container_client.list_blobs(name_starts_with=f"{session_id}/")
            transcript_list = []
            
            for blob in blobs:
                if blob.name.endswith('.json'):
                    transcript_list.append({
                        "name": blob.name,
                        "size": blob.size,
                        "last_modified": blob.last_modified.isoformat(),
                        "url": f"{self.container_client.url}/{blob.name}"
                    })
            
            # Sort by last modified (newest first)
            transcript_list.sort(key=lambda x: x["last_modified"], reverse=True)
            
            logger.info(f"Found {len(transcript_list)} transcripts for session {session_id}")
            return transcript_list
            
        except Exception as e:
            logger.error(f"Failed to list transcripts: {e}")
            raise
    
    async def download_transcript(self, blob_name: str) -> Optional[Dict[str, Any]]:
        """Download a specific transcript by blob name"""
        if not self._initialized:
            await self.initialize()
        
        try:
            blob_client = self.container_client.get_blob_client(blob_name)
            
            # Check if blob exists
            try:
                blob_properties = blob_client.get_blob_properties()
            except Exception:
                logger.warning(f"Blob not found: {blob_name}")
                return None
            
            # Download and parse JSON
            blob_data = blob_client.download_blob()
            content = blob_data.readall().decode('utf-8')
            transcript = json.loads(content)
            
            logger.info(f"Downloaded transcript: {blob_name}")
            return transcript
            
        except Exception as e:
            logger.error(f"Failed to download transcript: {e}")
            raise