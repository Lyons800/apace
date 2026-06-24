import AppKit

enum SoundEffects {
    static func playStart() {
        NSSound(named: "Tink")?.play()
    }

    static func playStop() {
        NSSound(named: "Pop")?.play()
    }

    static func playError() {
        NSSound.beep()
    }
}
