import Foundation
import Carbon.HIToolbox

enum RecordingMode: String, CaseIterable, Codable {
    case hold = "Hold to Record"
    case toggle = "Toggle Recording"
}

struct MurmurConfig: Codable {
    var modelName: String = "base.en"
    var language: String = "en"
    var recordingMode: RecordingMode = .hold
    var hotkeyKeyCode: UInt16 = UInt16(kVK_RightOption)
    var hotkeyModifiers: UInt = 0
    var playSounds: Bool = true
    var autoCapitalize: Bool = true
    var convertPunctuation: Bool = true
    var removeFiller: Bool = false
    var clipboardRestoreDelay: TimeInterval = 0.2
    var useStreaming: Bool = true
    var llmEnabled: Bool = false
    var launchAtLogin: Bool = false
    var dictionaryEntries: [DictionaryEntry] = []
    var historyEnabled: Bool = true
    var smartModes: [SmartMode] = SmartMode.defaults
    var muteMediaDuringRecording: Bool = false

    static let `default` = MurmurConfig()

    private static let storageKey = "murmur_config"
    private static let legacyStorageKey = "whispr_config"

    static func load() -> MurmurConfig {
        // Try new key first, then fall back to legacy key for migration
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let config = try? JSONDecoder().decode(MurmurConfig.self, from: data) {
            return config
        }
        if let data = UserDefaults.standard.data(forKey: legacyStorageKey),
           let config = try? JSONDecoder().decode(MurmurConfig.self, from: data) {
            // Migrate: save under new key and remove old
            config.save()
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)
            return config
        }
        return .default
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: MurmurConfig.storageKey)
        }
    }
}

