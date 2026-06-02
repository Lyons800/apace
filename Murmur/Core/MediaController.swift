import AudioToolbox
import CoreAudio
import Foundation

/// Mutes/unmutes system audio output during recording to avoid feedback and noise.
final class MediaController {
    private var previousVolume: Float32?
    private var mutedDeviceID: AudioObjectID?
    private var isMuted = false

    /// Mute system audio by setting output volume to 0.
    func muteSystemAudio() {
        guard !isMuted else { return }

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            NSLog("[Sona] MediaController: failed to get default output device")
            return
        }

        // Read current volume
        var volume: Float32 = 0
        size = UInt32(MemoryLayout<Float32>.size)
        address.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
        address.mScope = kAudioDevicePropertyScopeOutput

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard status == noErr else {
            NSLog("[Sona] MediaController: failed to read volume")
            return
        }

        previousVolume = volume
        mutedDeviceID = deviceID

        // Set volume to 0
        var muted: Float32 = 0
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &muted)

        isMuted = true
        NSLog("[Sona] MediaController: muted device \(deviceID) (was \(String(format: "%.2f", volume)))")
    }

    /// Restore system audio to previous volume level on the original device.
    func restoreSystemAudio() {
        guard isMuted, let previousVolume, let deviceID = mutedDeviceID else { return }

        var volume = previousVolume
        let size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &volume)

        isMuted = false
        self.previousVolume = nil
        self.mutedDeviceID = nil
        NSLog("[Sona] MediaController: restored device \(deviceID) volume to \(String(format: "%.2f", volume))")
    }
}
