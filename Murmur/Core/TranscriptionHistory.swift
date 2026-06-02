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
        let sonaDir = appSupport.appendingPathComponent("Sona", isDirectory: true)

        // One-time migration of the whole data directory from a previous app name.
        // A same-volume rename is atomic and instant, so the ~140MB+ of downloaded
        // models carry over without a copy or re-download.
        Self.migrateLegacyDataDirectory(appSupport: appSupport, sonaDir: sonaDir)

        try? FileManager.default.createDirectory(at: sonaDir, withIntermediateDirectories: true)
        self.fileURL = sonaDir.appendingPathComponent("history.json")

        load()
    }

    /// Rename ~/Library/Application Support/{Murmur,Whispr}/ → Sona/ on first launch
    /// under the new name. Newest legacy name wins; older ones are left untouched.
    private static func migrateLegacyDataDirectory(appSupport: URL, sonaDir: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: sonaDir.path) else { return }

        for legacyName in ["Murmur", "Whispr"] {
            let legacyDir = appSupport.appendingPathComponent(legacyName, isDirectory: true)
            guard fm.fileExists(atPath: legacyDir.path) else { continue }
            do {
                try fm.moveItem(at: legacyDir, to: sonaDir)
                NSLog("[Sona] Migrated data directory from \(legacyName)")
            } catch {
                NSLog("[Sona] Data migration from \(legacyName) failed: \(error.localizedDescription)")
            }
            break
        }

        // Carry over UserDefaults flags. (No-op if the bundle identifier also changed,
        // since that moves the defaults domain — acceptable, the user just re-onboards.)
        let keyMap: [(old: String, new: String)] = [
            ("murmur_onboarding_complete", "sona_onboarding_complete"),
            ("murmur_accessibility_prompted", "sona_accessibility_prompted"),
            ("whispr_onboarding_complete", "sona_onboarding_complete"),
            ("whispr_accessibility_prompted", "sona_accessibility_prompted"),
        ]
        for key in keyMap where UserDefaults.standard.object(forKey: key.old) != nil
            && UserDefaults.standard.object(forKey: key.new) == nil {
            UserDefaults.standard.set(UserDefaults.standard.bool(forKey: key.old), forKey: key.new)
            UserDefaults.standard.removeObject(forKey: key.old)
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
            NSLog("[Sona] Failed to load history: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[Sona] Failed to save history: \(error.localizedDescription)")
        }
    }
}
