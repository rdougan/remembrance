import CoreAudio
import Foundation

/// Name of the Mac's current sound output, shown so the operator can check the audio is going to
/// the PA and not the laptop speakers.
enum AudioOutput {
    static func defaultDeviceName() -> String {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        else { return "Unknown output" }

        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioObjectPropertyName
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name
        else { return "Unknown output" }
        return name.takeRetainedValue() as String
    }
}
