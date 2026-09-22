import CoreAudio
import Foundation

/// Read volume without executing AppleScript on every WebKit metadata update.
/// The short cache also coalesces bursts of play/pause and progress events.
final class SystemVolume {
    private var lastRead = Date.distantPast
    private var cachedPercent = 50

    func outputPercent() -> Int {
        guard Date().timeIntervalSince(lastRead) >= 1 else { return cachedPercent }
        lastRead = Date()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return cachedPercent }

        // Some output drivers expose a main control; others expose stereo
        // channel controls. Fixed-volume devices may expose neither.
        let scalar = volume(device, element: kAudioObjectPropertyElementMain)
            ?? [volume(device, element: 1), volume(device, element: 2)].compactMap { $0 }.max()
        if let scalar, scalar.isFinite {
            cachedPercent = Int((min(1, max(0, scalar)) * 100).rounded())
        }
        return cachedPercent
    }

    private func volume(_ device: AudioDeviceID, element: AudioObjectPropertyElement) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
