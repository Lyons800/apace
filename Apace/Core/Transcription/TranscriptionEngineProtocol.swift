import Foundation

/// Identifies which concrete transcription engine produced a result / is selected.
enum EngineID: String, Codable, Sendable, CaseIterable {
    case whisperKit
    case parakeet
    case appleSpeech
}

/// User-facing engine preference stored in config.
enum EnginePreference: String, Codable, Sendable, CaseIterable {
    case automatic
    case whisperKit
    case parakeet
    case appleSpeech
}

/// Errors common to all engines.
enum TranscriptionEngineError: LocalizedError {
    case modelNotLoaded
    case transcriptionFailed
    case unsupportedOnThisOS
    case unsupportedLanguage(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Transcription model not loaded"
        case .transcriptionFailed: return "Transcription failed"
        case .unsupportedOnThisOS: return "This engine is not available on this version of macOS"
        case .unsupportedLanguage(let l): return "This engine does not support language: \(l)"
        }
    }
}

/// Batch-shaped engine boundary. App-layer streaming re-calls `transcribe` on
/// accumulated audio, so a batch interface covers dictation streaming and files.
protocol TranscriptionEngineProtocol: AnyObject {
    var identifier: EngineID { get }
    var isModelLoaded: Bool { get }
    /// Load (downloading if needed) the model. `progress` is 0.0...1.0 when known.
    func loadModel(progress: ((Double) -> Void)?) async throws
    /// Transcribe 16 kHz mono float PCM. `promptText` is an optional biasing hint.
    func transcribe(audioSamples: [Float], language: String, promptText: String?) async throws -> TranscriptionResult
    /// Release the loaded model and free memory.
    func unload()
}
