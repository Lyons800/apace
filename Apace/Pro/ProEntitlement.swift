import Foundation

/// Gate for Apace Pro features (Command Mode, voice-edit, auto-vocabulary,
/// voice-to-action). v1 is a stub: real offline license validation (a key stored in
/// the Keychain) lands with the payment integration. Unlocked in DEBUG so Pro features
/// are testable during development.
final class ProEntitlement {
    static let shared = ProEntitlement()
    private init() {}

    /// Test-only override. Leave nil in production.
    var overrideForTesting: Bool?

    /// Whether Apace Pro is unlocked on this machine.
    var isActive: Bool {
        if let overrideForTesting { return overrideForTesting }
        #if DEBUG
        return true
        #else
        // TODO: validate the offline license key from the Keychain (payment integration).
        return UserDefaults.standard.bool(forKey: Self.unlockedKey)
        #endif
    }

    private static let unlockedKey = "apace_pro_unlocked"
}
