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
        let apaceDir = appSupport.appendingPathComponent("Apace", isDirectory: true)
        try? FileManager.default.createDirectory(at: apaceDir, withIntermediateDirectories: true)
        self.fileURL = apaceDir.appendingPathComponent("history.json")

        load()
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
            NSLog("[Apace] Failed to load history: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[Apace] Failed to save history: \(error.localizedDescription)")
        }
    }
}
