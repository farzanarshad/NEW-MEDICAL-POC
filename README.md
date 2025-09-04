# Azure Medical Transcription POC

A production-ready proof of concept for real-time medical transcription using Azure Speech Services, FastAPI, and WebSockets.

## Features

- **Real-time Transcription**: Live partial and final captions via WebSocket
- **Medical Speech Recognition**: Optimized for medical terminology
- **Secure Authentication**: Bearer token authentication
- **Cloud Storage**: Automatic transcript storage to Azure Blob Storage
- **Managed Identity**: Secure Azure resource access without secrets
- **Infrastructure as Code**: Complete Terraform deployment

## Architecture

```
┌─────────────┐    WebSocket    ┌─────────────┐    Azure Speech    ┌─────────────┐
│   Frontend  │ ──────────────► │   Backend   │ ──────────────► │   Azure     │
│ (HTML/JS)   │                 │ (FastAPI)   │                 │ Speech API  │
└─────────────┘                 └─────────────┘                 └─────────────┘
                                        │
                                        ▼
                                 ┌─────────────┐
                                 │ Azure Blob  │
                                 │  Storage    │
                                 └─────────────┘
```

## Quick Start

### 1. Deploy Infrastructure

```bash
cd infra
terraform init
terraform apply -auto-approve -var="project=medasr" -var="env=dev"
```

### 2. Configure Speech Service Key

After deployment, get the Speech service key and set it as an app setting:

```bash
# Get the resource group and speech account names from terraform output
az cognitiveservices account keys list -g <resource-group> -n <speech-account-name>
az webapp config appsettings set -g <resource-group> -n <webapp-name> --settings AZURE_SPEECH_KEY=<key>
```

### 3. Run Frontend

Open `frontend/index.html` in your browser and configure:
- WebSocket URL: `wss://<webapp-url>/ws`
- Bearer Token: (from terraform output)
- Language: `en-US`
- Medical Mode: `true`

### 4. Test Transcription

1. Click "Connect" to establish WebSocket connection
2. Click "Start" to begin recording
3. Speak into your microphone
4. View real-time partial and final captions
5. Click "Stop" to end session and save transcript

## Project Structure

```
azure-medical-transcribe/
├─ backend/                    # FastAPI backend
│  ├─ app.py                   # Main FastAPI app + WebSocket routes
│  ├─ asr.py                   # Azure Speech wrapper
│  ├─ storage.py               # Blob storage operations
│  ├─ models.py                # Pydantic schemas
│  ├─ deps.py                  # Dependencies, auth, CORS
│  ├─ requirements.txt         # Python dependencies
│  ├─ Dockerfile               # Container configuration
├─ frontend/                   # HTML/CSS/JS frontend
│  ├─ index.html               # Main UI
│  ├─ styles.css               # Styling
│  ├─ app.js                   # Main application logic
│  ├─ worklet/                 # Audio processing
│  │  └─ recorder-processor.js # AudioWorklet processor
├─ infra/                      # Terraform infrastructure
│  ├─ providers.tf             # Terraform providers
│  ├─ main.tf                  # Main resource definitions
│  ├─ variables.tf             # Input variables
│  ├─ outputs.tf               # Output values
│  ├─ terraform.tfvars.example # Example configuration
├─ .env.example                # Environment variables template
└─ README.md                   # This file
```

## Local Development

### Backend

```bash
cd backend
pip install -r requirements.txt
uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

### Frontend

Serve the frontend directory with any HTTP server:

```bash
cd frontend
python -m http.server 8000
# or
npx serve .
```

## WebSocket Protocol

### Client → Server

**Control Messages:**
```json
{
  "type": "start",
  "sampleRate": 16000,
  "format": "PCM16",
  "language": "en-US",
  "medical": true,
  "sessionId": "uuid"
}
```

```json
{
  "type": "stop"
}
```

**Audio Data:** Binary PCM16 frames (little-endian Int16 mono @ 16kHz)

### Server → Client

**Partial Results:**
```json
{
  "type": "partial",
  "text": "partial transcription...",
  "tsStart": 1.23,
  "tsEnd": 2.10
}
```

**Final Results:**
```json
{
  "type": "final",
  "text": "final transcription",
  "tsStart": 2.10,
  "tsEnd": 3.84
}
```

**Status/Error:**
```json
{
  "type": "status",
  "message": "recognition-started"
}
```

## API Endpoints

- `GET /healthz` - Health check
- `GET /readyz` - Readiness check
- `GET /sessions/{sessionId}` - Retrieve transcript
- `GET /download/{sessionId}` - Download transcript JSON
- `WS /ws` - WebSocket endpoint for real-time transcription

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AZURE_SPEECH_REGION` | Azure Speech region | From Speech account |
| `AZURE_SPEECH_KEY` | Speech service key | Required |
| `AZURE_BLOB_CONTAINER` | Blob container name | `transcripts` |
| `ASR_LANGUAGE` | Recognition language | `en-US` |
| `ASR_MEDICAL` | Medical mode | `true` |
| `API_BEARER_TOKEN` | Authentication token | Auto-generated |
| `ALLOWED_ORIGINS` | CORS origins | Localhost URLs |
| `SESSION_TIMEOUT_SEC` | WebSocket timeout | `300` |

## Security

- **Authentication**: Bearer token required for all endpoints
- **CORS**: Configurable allowed origins
- **Azure Access**: Managed Identity with least-privilege RBAC
- **No Secrets**: No storage keys or secrets in application code

## Cost Optimization

- **App Service**: B1 plan (minimal cost with WebSocket support)
- **Storage**: Standard LRS (lowest cost)
- **Speech**: S0 SKU (pay-as-you-go)
- **Auto-scaling**: Disabled for POC (enable for production)

## Troubleshooting

### Common Issues

1. **WebSocket Connection Failed**
   - Verify App Service has WebSockets enabled
   - Check CORS settings
   - Ensure bearer token is correct

2. **No Audio Recording**
   - Check browser permissions
   - Verify AudioWorklet support
   - Test microphone in browser settings

3. **Speech Recognition Errors**
   - Verify Azure Speech key is set
   - Check Speech service quota
   - Ensure correct region configuration

### Logs

View application logs:
```bash
az webapp log tail -g <resource-group> -n <webapp-name>
```

## Production Considerations

- Enable HTTPS only
- Configure proper CORS origins
- Set up monitoring and alerting
- Implement rate limiting
- Add input validation
- Configure backup strategies
- Set up CI/CD pipelines

## License

MIT License - see LICENSE file for details.