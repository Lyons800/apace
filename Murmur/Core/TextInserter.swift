import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class TextInserter {
    private let restoreDelay: TimeInterval

    init(restoreDelay: TimeInterval = 0.2) {
        self.restoreDelay = restoreDelay
    }

    func insert(_ text: String) async {
        guard !text.isEmpty else { return }

        // Check accessibility permission
        let hasAccess = AXIsProcessTrusted()
        NSLog("[Sona] TextInserter: accessibility=\(hasAccess), inserting '\(text.prefix(50))...'")

        if !hasAccess {
            NSLog("[Sona] WARNING: Accessibility not granted — cannot simulate paste. Opening System Settings...")
            Permissions.openAccessibilitySettings()
            return
        }

        // Try direct accessibility insertion first (avoids clipboard clobber)
        if insertViaAccessibility(text) {
            NSLog("[Sona] TextInserter: inserted via accessibility API (clipboard preserved)")
            return
        }

        // Fall back to clipboard + Cmd+V
        NSLog("[Sona] TextInserter: accessibility insertion failed, falling back to clipboard paste")

        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let savedItems = savePasteboard(pasteboard)

        // Guarantee clipboard restore on all exit paths (crash-safety)
        defer {
            restorePasteboard(pasteboard, items: savedItems)
        }

        // Set our text
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        NSLog("[Sona] TextInserter: clipboard set=\(success)")

        // Small delay to ensure pasteboard is ready
        try? await Task.sleep(for: .milliseconds(50))

        // Simulate Cmd+V
        simulatePaste()

        // Wait for paste to complete before defer restores clipboard
        try? await Task.sleep(for: .milliseconds(Int(restoreDelay * 1000)))
    }

    // MARK: - Accessibility API Insertion

    /// Attempt to insert text directly via the Accessibility API.
    /// Returns true if successfully verified, false if the element doesn't support it.
    private func insertViaAccessibility(_ text: String) -> Bool {
        let systemElement = AXUIElementCreateSystemWide()

        // Get the focused element
        var focusedElementRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)
        guard focusResult == .success, let focusedElement = focusedElementRef else {
            return false
        }

        // Verify the CF type before casting — AXUIElement is not safely bridgeable with as?
        guard CFGetTypeID(focusedElement as CFTypeRef) == AXUIElementGetTypeID() else {
            return false
        }
        let axElement = focusedElement as! AXUIElement

        // Check if the element is writable (skip terminal views, read-only fields, etc.)
        var writableRef: DarwinBoolean = false
        let isSettable = AXUIElementIsAttributeSettable(axElement, kAXSelectedTextAttribute as CFString, &writableRef)
        guard isSettable == .success, writableRef.boolValue else {
            NSLog("[Sona] TextInserter: AX selected text not settable, skipping")
            return false
        }

        // Try to set selected text (inserts at cursor / replaces selection)
        let setResult = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        guard setResult == .success else {
            return false
        }

        // Verify the write actually took effect by reading back
        // Some apps (Terminal, iTerm2) report success but don't actually insert
        var readBackRef: CFTypeRef?
        let readResult = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &readBackRef)
        if readResult == .success, let readBack = readBackRef as? String {
            // After insertion, selected text should be empty (cursor moved past inserted text)
            // OR it should contain the text we just set (if still selected)
            // If it still has the old value, the write was a no-op
            if readBack == text || readBack.isEmpty {
                return true
            }
            NSLog("[Sona] TextInserter: AX write reported success but verification failed (got '\(readBack.prefix(30))'), falling back")
            return false
        }

        // Can't verify — trust the success result for apps that don't support reading back
        return true
    }

    // MARK: - Keyboard Simulation

    private func simulatePaste() {
        let vKeyCode = findVKeyCode()

        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func findVKeyCode() -> CGKeyCode {
        // Try to find the V key code for the current keyboard layout
        guard let currentKeyboard = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData) else {
            return CGKeyCode(kVK_ANSI_V) // Fallback to QWERTY
        }

        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data
        let keyboardLayout = layoutData.withUnsafeBytes { ptr in
            ptr.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
        }

        // Scan key codes 0-127 to find which produces 'v'
        for keyCode: UInt16 in 0..<128 {
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length: Int = 0

            UCKeyTranslate(
                keyboardLayout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0, // No modifiers
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                4,
                &length,
                &chars
            )

            if length > 0 && chars[0] == UniChar(Character("v").asciiValue!) {
                return CGKeyCode(keyCode)
            }
        }

        return CGKeyCode(kVK_ANSI_V)
    }

    // MARK: - Clipboard Save/Restore

    private struct PasteboardItem {
        let types: [NSPasteboard.PasteboardType]
        let data: [NSPasteboard.PasteboardType: Data]
    }

    private func savePasteboard(_ pasteboard: NSPasteboard) -> [PasteboardItem] {
        var items: [PasteboardItem] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            let types = item.types
            for type in types {
                if let d = item.data(forType: type) {
                    data[type] = d
                }
            }
            items.append(PasteboardItem(types: types, data: data))
        }
        return items
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, items: [PasteboardItem]) {
        pasteboard.clearContents()
        for item in items {
            let pbItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data[type] {
                    pbItem.setData(data, forType: type)
                }
            }
            pasteboard.writeObjects([pbItem])
        }
    }
}
