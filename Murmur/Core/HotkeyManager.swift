import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var flagsMonitor: Any?
    private var isModifierKeyDown = false

    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?

    private var targetKeyCode: UInt16
    private var targetModifiers: UInt
    private var mode: RecordingMode
    private var isToggled = false

    /// Test hooks (internal; visible via @testable import). A modifier hotkey must
    /// install BOTH a global and a local monitor, or it dies when Murmur is frontmost.
    var hasLocalMonitorForTesting: Bool { localMonitor != nil }
    var hasFlagsMonitorForTesting: Bool { flagsMonitor != nil }

    init(keyCode: UInt16 = UInt16(kVK_RightOption), modifiers: UInt = 0, mode: RecordingMode = .hold) {
        self.targetKeyCode = keyCode
        self.targetModifiers = modifiers
        self.mode = mode
    }

    func start() {
        stop()

        // For modifier-only keys (Option, Command, Shift, Control), use flagsChanged
        let isModifierKey = isModifierOnlyKey(targetKeyCode)

        if isModifierKey {
            flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event)
            }
            // Global monitors do NOT fire while Murmur itself is the frontmost app
            // (Settings/onboarding/file-transcribe window open, or the menu bar was
            // just clicked). Without a LOCAL monitor too, the modifier hotkey silently
            // stops working whenever Murmur has focus — and a press/release missed in
            // that window leaves `isModifierKeyDown` desynced. The key-code branch below
            // already pairs global+local for exactly this reason; modifiers need it too.
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event)
                return event
            }
        } else {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                self?.handleKeyEvent(event)
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                self?.handleKeyEvent(event)
                return event
            }
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        globalMonitor = nil
        localMonitor = nil
        flagsMonitor = nil
        isModifierKeyDown = false
        isToggled = false
    }

    func updateHotkey(keyCode: UInt16, modifiers: UInt = 0, mode: RecordingMode) {
        self.targetKeyCode = keyCode
        self.targetModifiers = modifiers
        self.mode = mode
        start() // Restart monitors with new config
    }

    // MARK: - Event Handling

    private func handleKeyEvent(_ event: NSEvent) {
        guard event.keyCode == targetKeyCode else { return }

        // Check modifiers match (mask out device-dependent bits)
        let currentMods = event.modifierFlags.rawValue & 0x00FF0000
        guard currentMods == targetModifiers || targetModifiers == 0 else { return }

        switch mode {
        case .hold:
            if event.type == .keyDown && !event.isARepeat {
                onRecordingStart?()
            } else if event.type == .keyUp {
                onRecordingStop?()
            }
        case .toggle:
            if event.type == .keyDown && !event.isARepeat {
                isToggled.toggle()
                if isToggled {
                    onRecordingStart?()
                } else {
                    onRecordingStop?()
                }
            }
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let isPressed = isTargetModifierPressed(event)

        switch mode {
        case .hold:
            if isPressed && !isModifierKeyDown {
                isModifierKeyDown = true
                onRecordingStart?()
            } else if !isPressed && isModifierKeyDown {
                isModifierKeyDown = false
                onRecordingStop?()
            }
        case .toggle:
            if isPressed && !isModifierKeyDown {
                isModifierKeyDown = true
                isToggled.toggle()
                if isToggled {
                    onRecordingStart?()
                } else {
                    onRecordingStop?()
                }
            } else if !isPressed {
                isModifierKeyDown = false
            }
        }
    }

    // Device-specific modifier bit masks (from IOKit NX_* constants)
    private static let rightOptionMask:  UInt = 0x40
    private static let leftOptionMask:   UInt = 0x20
    private static let rightCommandMask: UInt = 0x10
    private static let leftCommandMask:  UInt = 0x08
    private static let rightShiftMask:   UInt = 0x04
    private static let leftShiftMask:    UInt = 0x02
    private static let rightControlMask: UInt = 0x2000
    private static let leftControlMask:  UInt = 0x01

    private func isTargetModifierPressed(_ event: NSEvent) -> Bool {
        let raw = event.modifierFlags.rawValue
        switch targetKeyCode {
        case UInt16(kVK_RightOption):
            return raw & Self.rightOptionMask != 0
        case UInt16(kVK_Option):
            return raw & Self.leftOptionMask != 0
        case UInt16(kVK_RightCommand):
            return raw & Self.rightCommandMask != 0
        case UInt16(kVK_Command):
            return raw & Self.leftCommandMask != 0
        case UInt16(kVK_RightShift):
            return raw & Self.rightShiftMask != 0
        case UInt16(kVK_Shift):
            return raw & Self.leftShiftMask != 0
        case UInt16(kVK_RightControl):
            return raw & Self.rightControlMask != 0
        case UInt16(kVK_Control):
            return raw & Self.leftControlMask != 0
        default:
            return false
        }
    }

    private func isModifierOnlyKey(_ keyCode: UInt16) -> Bool {
        let modifierKeys: Set<UInt16> = [
            UInt16(kVK_Option), UInt16(kVK_RightOption),
            UInt16(kVK_Command), UInt16(kVK_RightCommand),
            UInt16(kVK_Shift), UInt16(kVK_RightShift),
            UInt16(kVK_Control), UInt16(kVK_RightControl),
        ]
        return modifierKeys.contains(keyCode)
    }
}
