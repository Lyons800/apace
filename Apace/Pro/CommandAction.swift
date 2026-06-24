import Foundation

/// How dangerous an agent action is. Drives the "auto-run safe, confirm risky" policy.
enum ActionRisk: String, Codable, Equatable {
    case safe
    case risky
}

/// A concrete action the Command Mode agent wants to take on the Mac: a piece of
/// AppleScript plus a plain-English summary (shown in the Island for confirmation).
struct CommandAction: Equatable {
    let appleScript: String
    let summary: String
    let risk: ActionRisk
}

/// What the agent decided to do with a spoken command.
enum CommandDecision: Equatable {
    case act(CommandAction)   // run something on the Mac
    case answer(String)       // just answer a question about the screen
    case nothing              // couldn't help
}

/// Belt-and-suspenders risk policy. We trust the model's self-assessed risk, but ALWAYS
/// escalate to `.risky` when the script contains obviously destructive/irreversible verbs,
/// so a model that under-rates a dangerous action still gets a confirmation gate.
enum CommandRisk {
    /// Substrings that force a confirmation regardless of the model's claim.
    static let dangerSignals: [String] = [
        "delete", "remove", "trash", "erase", "empty",
        "do shell script", "rm ", "sudo",
        "send", "send message", "send mail",
        "quit", "shut down", "restart", "log out", "logout", "sleep",
        "move to", "set the clipboard", "make new"
    ]

    static func resolve(modelRisk: ActionRisk, script: String) -> ActionRisk {
        if modelRisk == .risky { return .risky }
        let lower = script.lowercased()
        return dangerSignals.contains(where: { lower.contains($0) }) ? .risky : .safe
    }
}
