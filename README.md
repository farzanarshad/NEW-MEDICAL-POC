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

### Option 1: VM-based Deployment (Recommended)
```bash
# Deploy using Azure Virtual Machine (no quota issues)
./deploy-vm.sh
```

### Option 2: Alternative Deployments
```bash
# Switch between different deployment options
./switch-deployment.sh

# Or use the alternative deployment script
./deploy-alternative.sh
```

### Option 3: Manual Deployment
```bash
# Navigate to infra directory
cd infra

# Initialize Terraform
terraform init

# Create terraform.tfvars (copy from example)
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Deploy infrastructure
terraform apply -auto-approve
```

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

## Deployment Options

This project supports multiple deployment options to handle different Azure quota scenarios:

### 🖥️ Virtual Machine (Recommended)
- **File**: `infra/main.tf` (VM configuration)
- **Script**: `./deploy-vm.sh`
- **Pros**: No quota issues, full control, production-ready
- **Cons**: Higher cost (~$15/month)
- **Best for**: Production POCs, when quotas are exhausted

### 🐳 Azure Container Instances
- **File**: `infra/main-aci.tf.backup`
- **Script**: `./deploy-alternative.sh` (option 2)
- **Pros**: No App Service Plan needed, containerized
- **Cons**: Limited scaling, higher cost than App Service
- **Best for**: When App Service quotas are exhausted

### ⚡ Azure Functions
- **File**: `infra/main-functions.tf.backup`
- **Script**: `./deploy-alternative.sh` (option 1)
- **Pros**: Consumption plan, pay-per-use
- **Cons**: Cold starts, limited WebSocket support
- **Best for**: Low-traffic scenarios

### 🌐 Azure App Service
- **File**: `infra/main-app-service.tf.backup`
- **Script**: `./deploy.sh`
- **Pros**: Managed service, easy scaling
- **Cons**: Quota limitations, higher cost
- **Best for**: Standard web applications

### 🔄 Switching Between Options
```bash
# Use the configuration switcher
./switch-deployment.sh

# Or manually switch files
cd infra
mv main.tf main-vm.tf.backup
mv main-app-service.tf.backup main.tf
```

## Security

- **Authentication**: Bearer token required for all endpoints
- **CORS**: Configurable allowed origins
- **Azure Access**: Managed Identity with least-privilege RBAC
- **No Secrets**: No storage keys or secrets in application code

## Cost Optimization

### VM Deployment
- **VM**: Standard_B1s (1 vCPU, 1 GB RAM) ~$15/month
- **Storage**: Standard LRS (lowest cost)
- **Speech**: S0 SKU (pay-as-you-go)

### App Service Deployment
- **App Service**: F1 plan (free tier with WebSocket support)
- **Storage**: Standard LRS (lowest cost)
- **Speech**: S0 SKU (pay-as-you-go)

### Container/Functions Deployment
- **Container**: Pay-per-use pricing
- **Functions**: Consumption plan (pay-per-use)
- **Storage**: Standard LRS (lowest cost)
- **Speech**: S0 SKU (pay-as-you-go)

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