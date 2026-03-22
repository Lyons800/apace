import Foundation

struct DictionaryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var spoken: String
    var replacement: String
}

struct CustomDictionary {
    /// Apply dictionary replacements using case-insensitive word boundary matching.
    static func apply(entries: [DictionaryEntry], to text: String) -> String {
        guard !entries.isEmpty else { return text }
        var result = text
        for entry in entries where !entry.spoken.isEmpty && !entry.replacement.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: entry.spoken)
            guard let regex = try? NSRegularExpression(
                pattern: "\\b\(escaped)\\b",
                options: .caseInsensitive
            ) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: entry.replacement
            )
        }
        return result
    }

    /// Build a WhisperKit prompt hint string from dictionary entries.
    /// This helps the model recognize proper nouns and technical terms.
    static func promptHint(from entries: [DictionaryEntry]) -> String? {
        let terms = entries
            .filter { !$0.replacement.isEmpty }
            .map(\.replacement)
        guard !terms.isEmpty else { return nil }
        return terms.joined(separator: ", ")
    }
}
