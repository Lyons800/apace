import Foundation
import FluidAudio

/// Parakeet TDT 0.6B via FluidAudio. 16 kHz mono float PCM. Apple Silicon only.
///
/// `promptText` is intentionally unused — Parakeet exposes no prompt/biasing API
/// in this integration. The `language` string is mapped to FluidAudio's `Language`
/// enum (raw values are ISO codes like "en"/"pt") and used only as a script hint
/// for the v3 multilingual model; it is silently ignored by the v2 model.
final class ParakeetEngine: TranscriptionEngineProtocol {
    let identifier: EngineID = .parakeet
    private var manager: AsrManager?
    private var models: AsrModels?
    private(set) var isModelLoaded = false
    private let version: AsrModelVersion

    init(version: AsrModelVersion = .v3) { self.version = version }

    func loadModel(progress: ((Double) -> Void)?) async throws {
        // FluidAudio's progressHandler is `@Sendable (DownloadProgress) -> Void`,
        // not `(Double) -> Void`, so we don't bridge incremental progress here.
        let loaded = try await AsrModels.downloadAndLoad(version: version)
        let mgr = AsrManager(config: .default)
        try await mgr.loadModels(loaded)
        self.models = loaded
        self.manager = mgr
        progress?(1.0)
        self.isModelLoaded = true
    }

    func transcribe(audioSamples: [Float], language: String, promptText: String?) async throws -> TranscriptionResult {
        guard let manager else { throw TranscriptionEngineError.modelNotLoaded }
        var state: TdtDecoderState
        do {
            state = try TdtDecoderState(decoderLayers: version.decoderLayers)
        } catch {
            throw TranscriptionEngineError.transcriptionFailed
        }
        let langHint = Language(rawValue: language)
        let start = Date()
        let result = try await manager.transcribe(audioSamples, decoderState: &state, language: langHint)
        let duration = Date().timeIntervalSince(start)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptionResult(text: text, duration: duration, language: language, segments: [])
    }

    func unload() {
        manager = nil
        models = nil
        isModelLoaded = false
    }
}
