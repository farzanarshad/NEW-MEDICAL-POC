#!/usr/bin/env python3
"""
Utility script to list and download transcripts from Azure Blob Storage
"""

import os
import sys
import json
import argparse
from datetime import datetime
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient


def list_transcripts(storage_account, container_name="transcripts", session_id=None):
    """List transcripts in blob storage"""
    try:
        # Create blob service client
        credential = DefaultAzureCredential()
        account_url = f"https://{storage_account}.blob.core.windows.net"
        blob_service_client = BlobServiceClient(account_url=account_url, credential=credential)
        
        # Get container client
        container_client = blob_service_client.get_container_client(container_name)
        
        # List blobs
        if session_id:
            blobs = container_client.list_blobs(name_starts_with=f"{session_id}/")
        else:
            blobs = container_client.list_blobs()
        
        transcripts = []
        for blob in blobs:
            if blob.name.endswith('.json'):
                transcripts.append({
                    "name": blob.name,
                    "size": blob.size,
                    "last_modified": blob.last_modified.isoformat(),
                    "url": f"{account_url}/{container_name}/{blob.name}"
                })
        
        # Sort by last modified (newest first)
        transcripts.sort(key=lambda x: x["last_modified"], reverse=True)
        
        return transcripts
        
    except Exception as e:
        print(f"Error listing transcripts: {e}")
        return None


def download_transcript(storage_account, blob_name, container_name="transcripts", output_file=None):
    """Download a specific transcript"""
    try:
        # Create blob service client
        credential = DefaultAzureCredential()
        account_url = f"https://{storage_account}.blob.core.windows.net"
        blob_service_client = BlobServiceClient(account_url=account_url, credential=credential)
        
        # Get blob client
        blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_name)
        
        # Download blob
        blob_data = blob_client.download_blob()
        content = blob_data.readall().decode('utf-8')
        transcript = json.loads(content)
        
        # Save to file or print
        if output_file:
            with open(output_file, 'w') as f:
                json.dump(transcript, f, indent=2)
            print(f"Transcript saved to: {output_file}")
        else:
            print(json.dumps(transcript, indent=2))
        
        return transcript
        
    except Exception as e:
        print(f"Error downloading transcript: {e}")
        return None


def main():
    parser = argparse.ArgumentParser(description="List and download transcripts from Azure Blob Storage")
    parser.add_argument("--storage-account", required=True, help="Storage account name")
    parser.add_argument("--container", default="transcripts", help="Container name (default: transcripts)")
    parser.add_argument("--session-id", help="Filter by session ID")
    parser.add_argument("--download", help="Download specific blob by name")
    parser.add_argument("--output", help="Output file for download")
    parser.add_argument("--format", choices=["table", "json"], default="table", help="Output format")
    
    args = parser.parse_args()
    
    if args.download:
        # Download specific transcript
        download_transcript(args.storage_account, args.download, args.container, args.output)
    else:
        # List transcripts
        transcripts = list_transcripts(args.storage_account, args.container, args.session_id)
        
        if not transcripts:
            print("No transcripts found")
            return
        
        if args.format == "json":
            print(json.dumps(transcripts, indent=2))
        else:
            # Table format
            print(f"\nFound {len(transcripts)} transcript(s):")
            print("-" * 80)
            print(f"{'Session ID':<30} {'Timestamp':<20} {'Size':<10} {'Modified':<20}")
            print("-" * 80)
            
            for transcript in transcripts:
                # Extract session ID from blob name
                session_id = transcript["name"].split('/')[0]
                timestamp = transcript["name"].split('/')[-1].replace('.json', '')
                size_kb = transcript["size"] // 1024
                modified = datetime.fromisoformat(transcript["last_modified"].replace('Z', '+00:00')).strftime('%Y-%m-%d %H:%M:%S')
                
                print(f"{session_id:<30} {timestamp:<20} {size_kb:<10}KB {modified:<20}")
            
            print("-" * 80)
            print(f"\nTo download a transcript, use:")
            print(f"python {sys.argv[0]} --storage-account {args.storage_account} --download <blob_name> [--output <file>]")


if __name__ == "__main__":
    main()