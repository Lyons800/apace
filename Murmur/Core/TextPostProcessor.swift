import Foundation

struct TextPostProcessor {
    var autoCapitalize: Bool = true
    var convertPunctuation: Bool = true
    var removeFiller: Bool = false

    func process(_ text: String, context: AppContext = .other) -> String {
        // Terminal context: return raw text with no modifications
        if context == .terminal {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        if convertPunctuation {
            result = replacePunctuation(result)
        }

        if removeFiller {
            result = removeFillerWords(result)
        }

        // Context-aware capitalization
        let shouldCapitalize: Bool
        switch context {
        case .codeEditor:
            shouldCapitalize = false // Code editors: preserve case
        case .terminal:
            shouldCapitalize = false
        default:
            shouldCapitalize = autoCapitalize
        }

        if shouldCapitalize {
            result = capitalizeAfterSentenceEndings(result)
            result = result.prefix(1).uppercased() + result.dropFirst()
        }

        // Normalize whitespace
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Context-aware trailing punctuation
        switch context {
        case .chat:
            // Remove trailing period from single sentences in chat
            if !result.contains(". ") && !result.contains("? ") && !result.contains("! ") {
                if result.hasSuffix(".") {
                    result = String(result.dropLast())
                }
            }
        case .email, .document:
            // Ensure trailing period for email/document
            if !result.isEmpty && !result.hasSuffix(".") && !result.hasSuffix("!") && !result.hasSuffix("?") {
                result += "."
            }
        default:
            break
        }

        return result
    }

    // MARK: - Punctuation Conversion

    private static let punctuationMap: [(patterns: [String], replacement: String, spaceBefore: Bool, spaceAfter: Bool)] = [
        (["period", "full stop", "dot"], ".", false, true),
        (["comma", "karma", "carma", "kama"], ",", false, true),
        (["question mark"], "?", false, true),
        (["exclamation mark", "exclamation point", "bang"], "!", false, true),
        (["colon"], ":", false, true),
        (["semicolon", "semi colon"], ";", false, true),
        (["open parenthesis", "open paren", "left paren"], "(", true, false),
        (["close parenthesis", "close paren", "right paren"], ")", false, true),
        (["open quote", "open quotes", "begin quote"], "\"", true, false),
        (["close quote", "close quotes", "end quote", "unquote"], "\"", false, true),
        (["hyphen", "dash"], "-", false, false),
        (["new line", "newline", "new paragraph"], "\n", false, false),
        (["tab"], "\t", false, false),
    ]

    private func replacePunctuation(_ text: String) -> String {
        var result = text
        for entry in Self.punctuationMap {
            for pattern in entry.patterns {
                let regex = try? NSRegularExpression(
                    pattern: "\\s*\\b\(NSRegularExpression.escapedPattern(for: pattern))\\b\\s*",
                    options: .caseInsensitive
                )
                let before = entry.spaceBefore ? " " : ""
                let after = entry.spaceAfter ? " " : ""
                let replacement = "\(before)\(entry.replacement)\(after)"
                result = regex?.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: replacement
                ) ?? result
            }
        }
        return result
    }

    // MARK: - Filler Removal

    private static let fillerWords: Set<String> = ["um", "uh", "uhh", "umm", "er", "ah", "like", "you know", "basically", "literally", "actually", "so yeah"]

    private func removeFillerWords(_ text: String) -> String {
        var result = text
        for filler in Self.fillerWords {
            let regex = try? NSRegularExpression(
                pattern: "\\b\(NSRegularExpression.escapedPattern(for: filler))\\b\\s*",
                options: .caseInsensitive
            )
            result = regex?.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            ) ?? result
        }
        return result
    }

    // MARK: - Capitalization

    private func capitalizeAfterSentenceEndings(_ text: String) -> String {
        let pattern = "([.!?])\\s+(\\w)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        var result = text

        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        // Process in reverse to maintain valid ranges
        for match in matches.reversed() {
            let letterRange = match.range(at: 2)
            let letter = nsText.substring(with: letterRange).uppercased()
            result = (result as NSString).replacingCharacters(in: letterRange, with: letter)
        }

        return result
    }
}
