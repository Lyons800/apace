import AVFoundation
import ApplicationServices
import AppKit

enum Permissions {

    // MARK: - Microphone

    static func checkMicrophone() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophone() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        NSLog("[Apace] Mic permission status: \(status.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")

        switch status {
        case .authorized:
            return true

        case .notDetermined:
            // First time — this MUST show the system permission dialog
            NSLog("[Apace] Requesting mic permission (first time)...")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            NSLog("[Apace] Mic permission result: \(granted)")
            return granted

        case .denied, .restricted:
            // Previously denied — system won't re-prompt, user must toggle in Settings
            NSLog("[Apace] Mic previously denied — opening System Settings")
            openMicrophoneSettings()
            return false

        @unknown default:
            return false
        }
    }

    // MARK: - Accessibility

    static func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
