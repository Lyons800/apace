import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private var animationTimer: Timer?
    private var animationFrame = 0
    private weak var appState: AppState?

    private var onSettingsClicked: (() -> Void)?
    private var onQuitClicked: (() -> Void)?

    func setup(appState: AppState, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.appState = appState
        self.onSettingsClicked = onSettings
        self.onQuitClicked = onQuit

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Sona")
        item.button?.image?.size = NSSize(width: 18, height: 18)
        item.menu = buildMenu()
        statusItem = item
    }

    func updateState(_ state: TranscriptionState) {
        switch state {
        case .recording:
            startRecordingAnimation()
        case .transcribing:
            startTranscribingAnimation()
        case .ready:
            stopAnimation()
            setIcon("waveform")
        case .error:
            stopAnimation()
            setIcon("exclamationmark.triangle")
        case .loading:
            setIcon("arrow.down.circle")
        default:
            stopAnimation()
            setIcon("waveform")
        }

        statusItem?.menu = buildMenu()
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Status
        let statusItem = NSMenuItem(title: appState?.state.statusText ?? "Unknown", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        // Last transcription
        if let last = appState?.lastTranscription, !last.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let preview = String(last.prefix(60)) + (last.count > 60 ? "..." : "")
            let lastItem = NSMenuItem(title: "Last: \(preview)", action: nil, keyEquivalent: "")
            lastItem.isEnabled = false
            menu.addItem(lastItem)
        }

        // Hotkey info
        menu.addItem(NSMenuItem.separator())
        let config = MurmurConfig.load()
        let hotkeyName = KeyCodes.displayName(keyCode: config.hotkeyKeyCode, modifiers: config.hotkeyModifiers)
        let hotkeyItem = NSMenuItem(title: "Hotkey: \(hotkeyName) (\(config.recordingMode.rawValue))", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)

        // Model info
        let modelItem = NSMenuItem(title: "Model: \(config.modelName)", action: nil, keyEquivalent: "")
        modelItem.isEnabled = false
        menu.addItem(modelItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settings = NSMenuItem(title: "Settings...", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        // Quit
        let quit = NSMenuItem(title: "Quit Sona", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func settingsClicked() {
        onSettingsClicked?()
    }

    @objc private func quitClicked() {
        onQuitClicked?()
    }

    // MARK: - Icon

    private func setIcon(_ systemName: String) {
        statusItem?.button?.image = NSImage(systemSymbolName: systemName, accessibilityDescription: "Sona")
        statusItem?.button?.image?.size = NSSize(width: 18, height: 18)
    }

    // MARK: - Animations

    private func startRecordingAnimation() {
        stopAnimation()
        animationFrame = 0

        let symbols = ["waveform.circle", "waveform.circle.fill"]
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let symbol = symbols[self.animationFrame % symbols.count]
            self.setIcon(symbol)
            self.animationFrame += 1
        }
        setIcon(symbols[0])
    }

    private func startTranscribingAnimation() {
        stopAnimation()
        animationFrame = 0

        let symbols = ["ellipsis", "ellipsis.circle", "ellipsis.circle.fill"]
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            let symbol = symbols[self.animationFrame % symbols.count]
            self.setIcon(symbol)
            self.animationFrame += 1
        }
        setIcon(symbols[0])
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}
