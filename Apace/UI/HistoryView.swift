import SwiftUI

struct HistoryView: View {
    @State private var entries: [HistoryEntry] = TranscriptionHistory.shared.entries
    @State private var searchText = ""
    @State private var copiedID: UUID?

    private var filteredEntries: [HistoryEntry] {
        if searchText.isEmpty { return entries }
        return entries.filter {
            $0.processedText.localizedCaseInsensitiveContains(searchText) ||
            $0.rawText.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcriptions...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.bar)

            Divider()

            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Transcriptions" : "No Results",
                    systemImage: searchText.isEmpty ? "text.bubble" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Your transcription history will appear here." : "Try a different search term.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(filteredEntries) { entry in
                    historyRow(entry)
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer
            HStack {
                Text("\(entries.count) transcription\(entries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") {
                    TranscriptionHistory.shared.clear()
                    entries = []
                }
                .font(.caption)
                .disabled(entries.isEmpty)
            }
            .padding(10)
            .background(.bar)
        }
        .frame(width: 500, height: 450)
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.processedText)
                .lineLimit(3)
                .font(.body)

            HStack(spacing: 8) {
                Label(entry.appContext, systemImage: contextIcon(entry.appContext))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.processedText, forType: .string)
                    copiedID = entry.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiedID == entry.id { copiedID = nil }
                    }
                } label: {
                    Image(systemName: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(copiedID == entry.id ? .green : .secondary)
                .help("Copy to clipboard")
            }
        }
        .padding(.vertical, 4)
    }

    private func contextIcon(_ context: String) -> String {
        switch context {
        case "codeEditor": return "chevron.left.forwardslash.chevron.right"
        case "email": return "envelope"
        case "chat": return "bubble.left"
        case "terminal": return "terminal"
        case "document": return "doc.text"
        case "browser": return "globe"
        default: return "app"
        }
    }
}
