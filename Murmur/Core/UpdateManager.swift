import Foundation
import Sparkle

final class UpdateManager {
    private let updaterController: SPUStandardUpdaterController

    init() {
        // SPUStandardUpdaterController manages the update lifecycle.
        // Set startingUpdater to true to check for updates on launch.
        // The updater delegate is nil — Sparkle uses Info.plist keys (SUFeedURL, SUPublicEDKey).
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater {
        updaterController.updater
    }

    /// Call from a "Check for Updates..." menu item
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Whether the user can currently check for updates (not already checking)
    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }
}
