import Foundation

/// Reads the user's current text selection (frontmost app's focused element).
protocol SelectionReading: AnyObject {
    func currentSelectedText() -> String?
}

/// Applies a free-form instruction to a passage of text.
protocol TextRewriting: AnyObject {
    func rewrite(_ text: String, instruction: String) async -> String
}

struct VoiceEdit: Equatable {
    let before: String
    let after: String
}

enum VoiceEditError: LocalizedError, Equatable {
    case proRequired
    case noSelection
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .proRequired: return "Voice editing is a Apace Pro feature."
        case .noSelection: return "Select some text first, then hold the command key and speak."
        case .emptyResult: return "Couldn't apply that edit."
        }
    }
}

/// Orchestrates voice-edit (a Apace Pro feature): read the current selection, apply a
/// spoken instruction via the on-device LLM, and return the before/after. The caller
/// replaces the selection with `.after` and surfaces it in the Island (with Undo).
final class VoiceEditService {
    private let selection: SelectionReading
    private let rewriter: TextRewriting
    private let isProActive: () -> Bool

    init(selection: SelectionReading,
         rewriter: TextRewriting,
         isProActive: @escaping () -> Bool = { ProEntitlement.shared.isActive }) {
        self.selection = selection
        self.rewriter = rewriter
        self.isProActive = isProActive
    }

    func prepareEdit(instruction: String) async throws -> VoiceEdit {
        guard isProActive() else { throw VoiceEditError.proRequired }

        guard let raw = selection.currentSelectedText() else { throw VoiceEditError.noSelection }
        let before = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !before.isEmpty else { throw VoiceEditError.noSelection }

        let after = (await rewriter.rewrite(before, instruction: instruction))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !after.isEmpty else { throw VoiceEditError.emptyResult }

        return VoiceEdit(before: before, after: after)
    }
}

// MARK: - Real conformances

extension TextInserter: SelectionReading {
    func currentSelectedText() -> String? { readSelectedText() }
}

extension LLMProcessor: TextRewriting {}
