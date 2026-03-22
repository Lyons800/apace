import Foundation

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    let rawText: String
    let processedText: String
    let appContext: String
    let timestamp: Date
}

final class TranscriptionHistory {
    static let shared = TranscriptionHistory()

    private let maxEntries = 1000
    private let fileURL: URL

    private(set) var entries: [HistoryEntry] = []

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let murmurDir = appSupport.appendingPathComponent("Murmur", isDirectory: true)
        try? FileManager.default.createDirectory(at: murmurDir, withIntermediateDirectories: true)
        self.fileURL = murmurDir.appendingPathComponent("history.json")

        // One-time migration from old Whispr data
        Self.migrateFromWhispr(appSupport: appSupport, murmurDir: murmurDir)

        load()
    }

    /// Migrate data from ~/Library/Application Support/Whispr/ to Murmur/
    private static func migrateFromWhispr(appSupport: URL, murmurDir: URL) {
        let fm = FileManager.default
        let legacyDir = appSupport.appendingPathComponent("Whispr", isDirectory: true)
        guard fm.fileExists(atPath: legacyDir.path) else { return }

        // Migrate history.json
        let legacyHistory = legacyDir.appendingPathComponent("history.json")
        let newHistory = murmurDir.appendingPathComponent("history.json")
        if fm.fileExists(atPath: legacyHistory.path) && !fm.fileExists(atPath: newHistory.path) {
            try? fm.copyItem(at: legacyHistory, to: newHistory)
            NSLog("[Murmur] Migrated history from Whispr")
        }

        // Migrate Models directory
        let legacyModels = legacyDir.appendingPathComponent("Models", isDirectory: true)
        let newModels = murmurDir.appendingPathComponent("Models", isDirectory: true)
        if fm.fileExists(atPath: legacyModels.path) && !fm.fileExists(atPath: newModels.path) {
            try? fm.copyItem(at: legacyModels, to: newModels)
            NSLog("[Murmur] Migrated models from Whispr")
        }

        // Migrate UserDefaults keys
        let legacyKeys: [(old: String, new: String)] = [
            ("whispr_onboarding_complete", "murmur_onboarding_complete"),
            ("whispr_accessibility_prompted", "murmur_accessibility_prompted"),
        ]
        for key in legacyKeys {
            if UserDefaults.standard.object(forKey: key.old) != nil && UserDefaults.standard.object(forKey: key.new) == nil {
                UserDefaults.standard.set(UserDefaults.standard.bool(forKey: key.old), forKey: key.new)
                UserDefaults.standard.removeObject(forKey: key.old)
            }
        }
    }

    func add(rawText: String, processedText: String, appContext: AppContext) {
        let entry = HistoryEntry(
            rawText: rawText,
            processedText: processedText,
            appContext: appContext.rawValue,
            timestamp: Date()
        )
        entries.insert(entry, at: 0)

        // Cap at maxEntries (FIFO)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        save()
    }

    func clear() {
        entries = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
        } catch {
            NSLog("[Murmur] Failed to load history: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[Murmur] Failed to save history: \(error.localizedDescription)")
        }
    }
}
