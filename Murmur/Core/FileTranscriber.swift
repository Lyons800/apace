import AVFoundation
import Foundation

struct FileTranscriptionSegment: Identifiable {
    let id = UUID()
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

struct FileTranscriptionResult {
    let segments: [FileTranscriptionSegment]
    let fullText: String
    let duration: TimeInterval
}

final class FileTranscriber {
    private let transcriptionEngine: TranscriptionEngineProtocol

    /// Supported audio/video file extensions
    static let supportedExtensions: Set<String> = ["mp3", "wav", "m4a", "aac", "flac", "mp4", "mov", "mkv", "webm"]

    init(transcriptionEngine: TranscriptionEngineProtocol) {
        self.transcriptionEngine = transcriptionEngine
    }

    /// Transcribe an audio or video file, returning timestamped segments.
    /// Extracts audio via AVAsset, resamples to 16kHz mono, and feeds 30s chunks to WhisperKit.
    func transcribe(
        fileURL: URL,
        language: String = "en",
        progressCallback: @escaping (Double) -> Void
    ) async throws -> FileTranscriptionResult {
        let samples = try await extractAudio(from: fileURL)
        let sampleRate: Double = 16000
        let totalDuration = Double(samples.count) / sampleRate

        // Process in 30-second chunks with 1-second overlap for context
        let chunkSize = Int(30 * sampleRate)
        let overlapSize = Int(1 * sampleRate)
        var allSegments: [FileTranscriptionSegment] = []
        var offset = 0

        while offset < samples.count {
            let end = min(offset + chunkSize, samples.count)
            let chunk = Array(samples[offset..<end])
            let chunkStartTime = Double(offset) / sampleRate

            progressCallback(Double(offset) / Double(samples.count))

            guard chunk.count > Int(0.5 * sampleRate) else { break } // Skip chunks < 0.5s

            let result = try await transcriptionEngine.transcribe(
                audioSamples: chunk,
                language: language,
                promptText: nil
            )

            if result.segments.isEmpty {
                // Engines like Parakeet / AppleSpeech return only `.text` with no
                // segments. Synthesize a single segment spanning this chunk so the
                // file transcript isn't empty.
                let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    allSegments.append(FileTranscriptionSegment(
                        text: trimmed,
                        startTime: chunkStartTime,
                        endTime: chunkStartTime + Double(chunk.count) / sampleRate
                    ))
                }
            } else {
                for segment in result.segments {
                    allSegments.append(FileTranscriptionSegment(
                        text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        startTime: chunkStartTime + segment.start,
                        endTime: chunkStartTime + segment.end
                    ))
                }
            }

            // Advance past the chunk, minus overlap for context continuity
            offset = end - (end < samples.count ? overlapSize : 0)
        }

        progressCallback(1.0)

        let fullText = allSegments.map(\.text).joined(separator: " ")
        return FileTranscriptionResult(
            segments: allSegments,
            fullText: fullText,
            duration: totalDuration
        )
    }

    /// Extract audio samples from an audio/video file as 16kHz mono Float32.
    private func extractAudio(from url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw FileTranscriberError.noAudioTrack
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var samples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            if let dataPointer {
                let floatCount = length / MemoryLayout<Float>.size
                let floatPointer = UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: floatCount)
                samples.append(contentsOf: UnsafeBufferPointer(start: floatPointer, count: floatCount))
            }
        }

        guard reader.status == .completed else {
            throw FileTranscriberError.readFailed(reader.error?.localizedDescription ?? "Unknown error")
        }

        return samples
    }
}

enum FileTranscriberError: LocalizedError {
    case noAudioTrack
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "No audio track found in file"
        case .readFailed(let msg): return "Failed to read audio: \(msg)"
        }
    }
}
