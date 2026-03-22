import Foundation

struct SmartMode: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var triggerPhrase: String
    var systemPrompt: String
    var isEnabled: Bool = true

    /// Default smart modes matching the built-in voice commands
    static let defaults: [SmartMode] = [
        SmartMode(
            name: "Fix Grammar",
            triggerPhrase: "fix grammar",
            systemPrompt: "Fix the grammar and punctuation of the following text. Output ONLY the corrected text, nothing else."
        ),
        SmartMode(
            name: "Make Professional",
            triggerPhrase: "make professional",
            systemPrompt: "Rewrite the following text in a professional, formal tone. Output ONLY the rewritten text, nothing else."
        ),
        SmartMode(
            name: "Make Casual",
            triggerPhrase: "make casual",
            systemPrompt: "Rewrite the following text in a casual, friendly tone. Output ONLY the rewritten text, nothing else."
        ),
        SmartMode(
            name: "Summarize",
            triggerPhrase: "summarize",
            systemPrompt: "Summarize the following text concisely. Output ONLY the summary, nothing else."
        ),
    ]
}
