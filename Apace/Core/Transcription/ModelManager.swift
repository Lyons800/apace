import Foundation

enum ModelManager {
    /// Which engines are usable on this OS major version (pure, testable).
    static func availability(osMajor: Int) -> [EngineID: Bool] {
        [
            .whisperKit: true,
            .parakeet: true,       // Apple Silicon checked at load time
            .appleSpeech: osMajor >= 26
        ]
    }

    static func displayName(_ id: EngineID) -> String {
        switch id {
        case .whisperKit: return "WhisperKit (99 languages)"
        case .parakeet: return "Parakeet — fastest, English/European"
        case .appleSpeech: return "Apple Dictation (macOS 26+)"
        }
    }
}
