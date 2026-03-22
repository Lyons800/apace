import AppKit

enum VoiceCommand {
    case fixGrammar
    case makeProfessional
    case makeCasual
    case summarize
    case translate(language: String)
    case custom(SmartMode)

    var llmPrompt: String {
        switch self {
        case .fixGrammar:
            return "Fix the grammar and punctuation of the following text. Output ONLY the corrected text, nothing else."
        case .makeProfessional:
            return "Rewrite the following text in a professional, formal tone. Output ONLY the rewritten text, nothing else."
        case .makeCasual:
            return "Rewrite the following text in a casual, friendly tone. Output ONLY the rewritten text, nothing else."
        case .summarize:
            return "Summarize the following text concisely. Output ONLY the summary, nothing else."
        case .translate(let language):
            return "Translate the following text to \(language). Output ONLY the translation, nothing else."
        case .custom(let mode):
            return mode.systemPrompt
        }
    }
}

struct VoiceCommandParser {

    private static let commandPatterns: [(patterns: [String], command: VoiceCommand)] = [
        (["fix grammar", "fix this", "fix the grammar", "correct this", "correct grammar"], .fixGrammar),
        (["make professional", "make formal", "make it professional", "make it formal"], .makeProfessional),
        (["make casual", "make informal", "make it casual", "make it informal"], .makeCasual),
        (["summarize", "summarize this", "summarise", "summarise this"], .summarize),
    ]

    /// Parse transcribed text for a voice command. Checks user-defined Smart Modes first,
    /// then falls back to built-in command patterns.
    static func parse(_ text: String, smartModes: [SmartMode] = []) -> (command: VoiceCommand, remainingText: String)? {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check user-defined Smart Modes first (enabled ones only)
        for mode in smartModes where mode.isEnabled {
            let trigger = mode.triggerPhrase.lowercased()
            if !trigger.isEmpty && lowered.hasPrefix(trigger) {
                let remaining = String(text.dropFirst(trigger.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return (.custom(mode), remaining)
            }
        }

        // Check for translate command (special: target language follows the keyword)
        if let range = lowered.range(of: "translate to ") ?? lowered.range(of: "translate into ") {
            let language = String(lowered[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !language.isEmpty {
                return (.translate(language: language), "")
            }
        }

        // Check built-in command patterns
        for entry in commandPatterns {
            for pattern in entry.patterns {
                if lowered.hasPrefix(pattern) {
                    let remaining = String(text.dropFirst(pattern.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (entry.command, remaining)
                }
            }
        }

        return nil
    }

    /// Capture the currently selected text in the frontmost app by simulating Cmd+C.
    static func captureSelectedText() async -> String? {
        let pasteboard = NSPasteboard.general

        // Save current clipboard contents
        let savedTypes = pasteboard.types ?? []
        var savedData: [(NSPasteboard.PasteboardType, Data)] = []
        for type in savedTypes {
            if let data = pasteboard.data(forType: type) {
                savedData.append((type, data))
            }
        }

        // Guarantee clipboard restore on all exit paths (crash-safety)
        defer {
            pasteboard.clearContents()
            for (type, data) in savedData {
                pasteboard.setData(data, forType: type)
            }
        }

        // Clear and simulate Cmd+C
        pasteboard.clearContents()

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = 8

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)

        // Wait for clipboard to update
        try? await Task.sleep(for: .milliseconds(150))

        return pasteboard.string(forType: .string)
    }
}
