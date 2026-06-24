import Foundation

/// Everything the agent needs to reason about a spoken command.
struct AgentContext {
    let command: String
    let screenshotPNG: Data?
    let frontmostApp: String?
    let selection: String?
}

/// The pluggable "brain" of Command Mode. Three providers back it (see `BrainProvider`):
/// on-device, Apace Pro managed cloud, or the user's own API key.
protocol AgentBrain {
    func decide(_ context: AgentContext) async throws -> CommandDecision
}

/// Where the agent's reasoning runs. Selected in Settings.
enum BrainProvider: String, Codable, CaseIterable {
    case local    // on-device model — fully private, no key, weaker on vision/agentic
    case managed  // Apace Pro subscription — Apace supplies a capable cloud model
    case byok     // bring your own key (Anthropic)

    var label: String {
        switch self {
        case .local: return "On-device (private)"
        case .managed: return "Apace Pro (managed)"
        case .byok: return "Your own API key"
        }
    }
}

enum AgentError: LocalizedError, Equatable {
    case noAPIKey
    case notConfigured(String)
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Add your Anthropic API key in Settings to use Command Mode."
        case .notConfigured(let why): return why
        case .http(let code, let body): return "Agent error (\(code)): \(body.prefix(120))"
        case .badResponse: return "The agent returned an unexpected response."
        }
    }
}

enum AgentBrainFactory {
    static func make(provider: BrainProvider) -> AgentBrain {
        switch provider {
        case .byok:
            return ClaudeBrain(apiKey: Keychain.get(Keychain.anthropicKeyAccount) ?? "")
        case .managed:
            return ManagedBrain()
        case .local:
            return LocalBrain()
        }
    }
}

/// Apace Pro managed cloud — proxies to Apace's backend so the user needs no key.
/// Backend not built yet.
struct ManagedBrain: AgentBrain {
    func decide(_ context: AgentContext) async throws -> CommandDecision {
        throw AgentError.notConfigured("Apace Pro managed cloud isn't available yet — use your own API key for now.")
    }
}

/// On-device agent (needs an on-device vision/tool-use model). Not wired yet.
struct LocalBrain: AgentBrain {
    func decide(_ context: AgentContext) async throws -> CommandDecision {
        throw AgentError.notConfigured("The on-device agent isn't available yet — use your own API key for now.")
    }
}
