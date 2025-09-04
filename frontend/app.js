class MedicalTranscriptionApp {
    constructor() {
        this.ws = null;
        this.audioContext = null;
        this.audioWorklet = null;
        this.mediaStream = null;
        this.isConnected = false;
        this.isRecording = false;
        this.sessionId = null;
        this.sessionStartTime = null;
        this.latencyMeasurements = [];
        
        this.initializeElements();
        this.bindEvents();
        this.checkAudioWorkletSupport();
    }

    initializeElements() {
        // Configuration elements
        this.wsUrlInput = document.getElementById('wsUrl');
        this.bearerTokenInput = document.getElementById('bearerToken');
        this.languageSelect = document.getElementById('language');
        this.medicalModeCheckbox = document.getElementById('medicalMode');
        
        // Control buttons
        this.connectBtn = document.getElementById('connectBtn');
        this.startBtn = document.getElementById('startBtn');
        this.stopBtn = document.getElementById('stopBtn');
        this.disconnectBtn = document.getElementById('disconnectBtn');
        
        // Status elements
        this.connectionStatus = document.getElementById('connectionStatus');
        this.recordingStatus = document.getElementById('recordingStatus');
        this.latencyValue = document.getElementById('latencyValue');
        
        // Display elements
        this.partialText = document.getElementById('partialText');
        this.finalResults = document.getElementById('finalResults');
        this.sessionIdElement = document.getElementById('sessionId');
        this.sessionDuration = document.getElementById('sessionDuration');
        this.audioLevel = document.getElementById('audioLevel');
        
        // Error panel
        this.errorPanel = document.getElementById('errorPanel');
        this.errorMessage = document.getElementById('errorMessage');
    }

    bindEvents() {
        this.connectBtn.addEventListener('click', () => this.connect());
        this.startBtn.addEventListener('click', () => this.startRecording());
        this.stopBtn.addEventListener('click', () => this.stopRecording());
        this.disconnectBtn.addEventListener('click', () => this.disconnect());
        
        // Update session duration
        setInterval(() => this.updateSessionDuration(), 1000);
    }

    checkAudioWorkletSupport() {
        if (!window.AudioWorklet) {
            this.showError('AudioWorklet is not supported in this browser. Please use a modern browser like Chrome, Firefox, or Edge.');
            this.startBtn.disabled = true;
        }
    }

    async connect() {
        if (this.isConnected) {
            return;
        }

        const wsUrl = this.wsUrlInput.value.trim();
        const bearerToken = this.bearerTokenInput.value.trim();

        if (!wsUrl) {
            this.showError('Please enter a WebSocket URL');
            return;
        }

        try {
            this.connectBtn.disabled = true;
            this.updateConnectionStatus('connecting', 'Connecting...');

            // Create WebSocket connection
            this.ws = new WebSocket(wsUrl);
            
            // Set up event handlers
            this.ws.onopen = () => {
                this.isConnected = true;
                this.updateConnectionStatus('connected', 'Connected');
                this.connectBtn.disabled = true;
                this.disconnectBtn.disabled = false;
                this.startBtn.disabled = false;
                console.log('WebSocket connected');
            };

            this.ws.onmessage = (event) => {
                this.handleWebSocketMessage(event.data);
            };

            this.ws.onclose = () => {
                this.handleDisconnection();
            };

            this.ws.onerror = (error) => {
                console.error('WebSocket error:', error);
                this.showError('WebSocket connection failed');
                this.handleDisconnection();
            };

            // Add authorization header if token is provided
            if (bearerToken) {
                this.ws.onopen = () => {
                    // Send authorization header
                    this.ws.send(JSON.stringify({
                        type: 'auth',
                        token: bearerToken
                    }));
                };
            }

        } catch (error) {
            console.error('Connection error:', error);
            this.showError('Failed to connect: ' + error.message);
            this.handleDisconnection();
        }
    }

    async startRecording() {
        if (!this.isConnected || this.isRecording) {
            return;
        }

        try {
            // Request microphone access
            this.mediaStream = await navigator.mediaDevices.getUserMedia({
                audio: {
                    sampleRate: 48000,
                    channelCount: 1,
                    echoCancellation: true,
                    noiseSuppression: true,
                    autoGainControl: true
                }
            });

            // Create audio context
            this.audioContext = new AudioContext({ sampleRate: 48000 });
            
            // Load audio worklet
            await this.audioContext.audioWorklet.addModule('worklet/recorder-processor.js');
            
            // Create audio source
            const source = this.audioContext.createMediaStreamSource(this.mediaStream);
            
            // Create audio worklet node
            this.audioWorklet = new AudioWorkletNode(this.audioContext, 'recorder-processor');
            
            // Connect audio nodes
            source.connect(this.audioWorklet);
            this.audioWorklet.connect(this.audioContext.destination);
            
            // Set up worklet message handler
            this.audioWorklet.port.onmessage = (event) => {
                this.handleWorkletMessage(event.data);
            };
            
            // Generate session ID
            this.sessionId = this.generateSessionId();
            this.sessionStartTime = Date.now();
            this.sessionIdElement.textContent = this.sessionId;
            
            // Start recording
            this.audioWorklet.port.postMessage({ type: 'start' });
            this.isRecording = true;
            
            // Update UI
            this.updateRecordingStatus('recording', 'Recording');
            this.startBtn.disabled = true;
            this.stopBtn.disabled = false;
            this.partialText.textContent = 'Listening...';
            
            // Send start message to server
            const startMessage = {
                type: 'start',
                sampleRate: 16000,
                format: 'PCM16',
                language: this.languageSelect.value,
                medical: this.medicalModeCheckbox.checked,
                sessionId: this.sessionId
            };
            
            this.ws.send(JSON.stringify(startMessage));
            
            console.log('Recording started');
            
        } catch (error) {
            console.error('Recording error:', error);
            this.showError('Failed to start recording: ' + error.message);
        }
    }

    async stopRecording() {
        if (!this.isRecording) {
            return;
        }

        try {
            // Stop audio worklet
            if (this.audioWorklet) {
                this.audioWorklet.port.postMessage({ type: 'stop' });
            }
            
            // Stop media stream
            if (this.mediaStream) {
                this.mediaStream.getTracks().forEach(track => track.stop());
                this.mediaStream = null;
            }
            
            // Close audio context
            if (this.audioContext) {
                await this.audioContext.close();
                this.audioContext = null;
            }
            
            this.isRecording = false;
            this.updateRecordingStatus('stopped', 'Stopped');
            this.startBtn.disabled = false;
            this.stopBtn.disabled = true;
            this.partialText.textContent = 'Recording stopped';
            
            // Send stop message to server
            this.ws.send(JSON.stringify({ type: 'stop' }));
            
            console.log('Recording stopped');
            
        } catch (error) {
            console.error('Stop recording error:', error);
            this.showError('Failed to stop recording: ' + error.message);
        }
    }

    disconnect() {
        if (this.isRecording) {
            this.stopRecording();
        }
        
        if (this.ws) {
            this.ws.close();
        }
        
        this.handleDisconnection();
    }

    handleDisconnection() {
        this.isConnected = false;
        this.isRecording = false;
        this.updateConnectionStatus('disconnected', 'Disconnected');
        this.updateRecordingStatus('stopped', 'Stopped');
        
        this.connectBtn.disabled = false;
        this.startBtn.disabled = true;
        this.stopBtn.disabled = true;
        this.disconnectBtn.disabled = true;
        
        this.partialText.textContent = 'Disconnected';
        console.log('Disconnected');
    }

    handleWebSocketMessage(data) {
        try {
            const message = JSON.parse(data);
            const messageType = message.type;
            
            switch (messageType) {
                case 'partial':
                    this.displayPartialResult(message);
                    break;
                    
                case 'final':
                    this.displayFinalResult(message);
                    break;
                    
                case 'status':
                    this.handleStatusMessage(message);
                    break;
                    
                case 'error':
                    this.showError(message.message);
                    break;
                    
                default:
                    console.log('Unknown message type:', messageType);
            }
            
        } catch (error) {
            console.error('Error parsing WebSocket message:', error);
        }
    }

    handleWorkletMessage(data) {
        const { type, data: audioData, frameCount } = data;
        
        switch (type) {
            case 'audio':
                if (this.isRecording && this.ws && this.ws.readyState === WebSocket.OPEN) {
                    // Send audio data to server
                    this.ws.send(audioData);
                    
                    // Update audio level (simplified)
                    const level = Math.min(100, Math.random() * 50 + 20); // Mock level
                    this.updateAudioLevel(level);
                }
                break;
                
            case 'status':
                console.log('Worklet status:', data.message);
                break;
        }
    }

    displayPartialResult(message) {
        this.partialText.textContent = message.text || 'Listening...';
        
        // Calculate latency
        this.calculateLatency();
    }

    displayFinalResult(message) {
        const finalItem = document.createElement('div');
        finalItem.className = 'final-item';
        
        const timestamp = document.createElement('div');
        timestamp.className = 'timestamp';
        timestamp.textContent = `${message.tsStart.toFixed(2)}s - ${message.tsEnd.toFixed(2)}s`;
        
        const text = document.createElement('div');
        text.className = 'text';
        text.textContent = message.text;
        
        finalItem.appendChild(timestamp);
        finalItem.appendChild(text);
        
        // Remove empty state if present
        const emptyState = this.finalResults.querySelector('.empty-state');
        if (emptyState) {
            emptyState.remove();
        }
        
        this.finalResults.appendChild(finalItem);
        this.finalResults.scrollTop = this.finalResults.scrollHeight;
    }

    handleStatusMessage(message) {
        console.log('Status:', message.message);
        
        if (message.message.includes('transcript-saved')) {
            this.showSuccess('Transcript saved successfully');
        }
    }

    calculateLatency() {
        // Simple latency calculation (in a real app, you'd measure round-trip time)
        const latency = Math.random() * 200 + 50; // Mock latency 50-250ms
        this.latencyMeasurements.push(latency);
        
        // Keep only last 10 measurements
        if (this.latencyMeasurements.length > 10) {
            this.latencyMeasurements.shift();
        }
        
        // Calculate average
        const avgLatency = this.latencyMeasurements.reduce((a, b) => a + b, 0) / this.latencyMeasurements.length;
        this.latencyValue.textContent = `${avgLatency.toFixed(0)}ms`;
    }

    updateConnectionStatus(status, text) {
        this.connectionStatus.textContent = text;
        this.connectionStatus.className = `status-value ${status}`;
    }

    updateRecordingStatus(status, text) {
        this.recordingStatus.textContent = text;
        this.recordingStatus.className = `status-value ${status}`;
    }

    updateAudioLevel(level) {
        this.audioLevel.style.width = `${level}%`;
    }

    updateSessionDuration() {
        if (this.sessionStartTime) {
            const duration = Math.floor((Date.now() - this.sessionStartTime) / 1000);
            const minutes = Math.floor(duration / 60);
            const seconds = duration % 60;
            this.sessionDuration.textContent = `${minutes}:${seconds.toString().padStart(2, '0')}`;
        }
    }

    generateSessionId() {
        return 'session_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
    }

    showError(message) {
        this.errorMessage.textContent = message;
        this.errorPanel.style.display = 'block';
        
        // Auto-hide after 5 seconds
        setTimeout(() => {
            this.hideError();
        }, 5000);
    }

    showSuccess(message) {
        // For now, just log success messages
        console.log('Success:', message);
    }

    hideError() {
        this.errorPanel.style.display = 'none';
    }
}

// Global function for error panel close button
function hideError() {
    if (window.app) {
        window.app.hideError();
    }
}

// Initialize app when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    window.app = new MedicalTranscriptionApp();
});