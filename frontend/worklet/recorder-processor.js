class RecorderProcessor extends AudioWorkletProcessor {
    constructor() {
        super();
        this.isRecording = false;
        this.sampleRate = 16000;
        this.buffer = [];
        this.bufferSize = 1024; // Process in chunks
        this.frameCount = 0;
    }

    process(inputs, outputs, parameters) {
        const input = inputs[0];
        if (!input || !input.length || !this.isRecording) {
            return true;
        }

        const inputChannel = input[0];
        if (!inputChannel) {
            return true;
        }

        // Resample from 48kHz to 16kHz (simple decimation)
        const downsampleFactor = 48000 / this.sampleRate;
        
        for (let i = 0; i < inputChannel.length; i += downsampleFactor) {
            const sample = inputChannel[Math.floor(i)];
            
            // Convert float32 to int16
            const int16Sample = Math.max(-32768, Math.min(32767, sample * 32768));
            
            // Store as little-endian bytes
            this.buffer.push(int16Sample & 0xFF);
            this.buffer.push((int16Sample >> 8) & 0xFF);
            
            this.frameCount++;
        }

        // Send buffer when it reaches the target size
        if (this.buffer.length >= this.bufferSize * 2) { // *2 because each sample is 2 bytes
            const audioData = new Uint8Array(this.buffer);
            this.port.postMessage({
                type: 'audio',
                data: audioData.buffer,
                frameCount: this.frameCount
            }, [audioData.buffer]);
            
            this.buffer = [];
            this.frameCount = 0;
        }

        return true;
    }

    // Handle messages from main thread
    port.onmessage = (event) => {
        const { type, data } = event.data;
        
        switch (type) {
            case 'start':
                this.isRecording = true;
                this.buffer = [];
                this.frameCount = 0;
                this.port.postMessage({ type: 'status', message: 'recording-started' });
                break;
                
            case 'stop':
                this.isRecording = false;
                // Send any remaining buffer
                if (this.buffer.length > 0) {
                    const audioData = new Uint8Array(this.buffer);
                    this.port.postMessage({
                        type: 'audio',
                        data: audioData.buffer,
                        frameCount: this.frameCount,
                        final: true
                    }, [audioData.buffer]);
                }
                this.port.postMessage({ type: 'status', message: 'recording-stopped' });
                break;
        }
    };
}

registerProcessor('recorder-processor', RecorderProcessor);