import AVFoundation
import Accelerate

final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private let bufferQueue = DispatchQueue(label: "app.sona.audiobuffer")
    private var levelCallback: ((Float) -> Void)?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var isWarmed = false

    private let sampleRate: Double = 16000
    private let channelCount: AVAudioChannelCount = 1

    var isRecording: Bool { audioEngine?.isRunning ?? false }

    /// Warm up the audio engine at app startup so recording starts instantly.
    /// Call this once after permissions are granted.
    func warmUp() throws {
        guard !isWarmed else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw AudioRecorderError.formatCreationFailed
        }

        guard let conv = AVAudioConverter(from: inputFormat, to: format) else {
            throw AudioRecorderError.converterCreationFailed
        }

        self.targetFormat = format
        self.converter = conv
        self.audioEngine = engine

        // Prepare the engine (allocates buffers, connects nodes) but don't start yet
        engine.prepare()
        isWarmed = true

        NSLog("[Sona] AudioRecorder: warmed up, input format=\(inputFormat), sampleRate=\(inputFormat.sampleRate)")
    }

    func startRecording(levelCallback: ((Float) -> Void)? = nil) throws {
        self.levelCallback = levelCallback
        bufferQueue.sync { audioBuffer = [] }

        // If not warmed up, do it now (first-time fallback)
        if !isWarmed {
            try warmUp()
        }

        guard let engine = audioEngine, let targetFormat, let converter else {
            throw AudioRecorderError.formatCreationFailed
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let localSampleRate = self.sampleRate

        let bufferSize: AVAudioFrameCount = 1024
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * localSampleRate / inputFormat.sampleRate
            )
            guard frameCount > 0 else { return }

            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil, let channelData = convertedBuffer.floatChannelData {
                let frames = Int(convertedBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frames))

                self.bufferQueue.async {
                    self.audioBuffer.append(contentsOf: samples)
                }

                // Calculate RMS for level metering
                var rms: Float = 0
                vDSP_measqv(channelData[0], 1, &rms, vDSP_Length(frames))
                rms = sqrtf(rms)

                DispatchQueue.main.async {
                    self.levelCallback?(rms)
                }
            }
        }

        // Re-prepare and start (fast since engine already exists from warmUp)
        engine.prepare()
        try engine.start()
    }

    func stopRecording() -> [Float] {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        levelCallback = nil

        return bufferQueue.sync { audioBuffer }
    }

    func getAudioSamples() -> [Float] {
        bufferQueue.sync { audioBuffer }
    }

    /// Fully shut down the audio engine (call on app quit).
    func shutdown() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        converter = nil
        targetFormat = nil
        isWarmed = false
    }
}

enum AudioRecorderError: LocalizedError {
    case formatCreationFailed
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed: return "Failed to create audio format"
        case .converterCreationFailed: return "Failed to create audio converter"
        }
    }
}
