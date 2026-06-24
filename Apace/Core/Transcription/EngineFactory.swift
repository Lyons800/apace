import Foundation
import FluidAudio

extension EngineSelector {
    /// Build a concrete engine for an EngineID. Falls back off Apple on macOS < 26.
    static func makeEngine(id: EngineID, modelName: String, localeID: String) -> TranscriptionEngineProtocol {
        switch id {
        case .whisperKit:
            return WhisperKitEngine(modelName: modelName)
        case .parakeet:
            return ParakeetEngine(version: .v3)
        case .appleSpeech:
            if #available(macOS 26.0, *) {
                return AppleSpeechEngine(localeID: localeID)
            } else {
                return ParakeetEngine(version: .v3)
            }
        }
    }
}
