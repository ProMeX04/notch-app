import CoreAudio
import Foundation

enum SystemAudioOutputError: LocalizedError {
    case noDefaultOutputDevice
    case propertyUnavailable(String)
    case propertyNotSettable(String)
    case coreAudioFailure(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .noDefaultOutputDevice:
            return "No default output audio device is available."
        case let .propertyUnavailable(name):
            return "Audio device does not expose \(name)."
        case let .propertyNotSettable(name):
            return "Audio device does not allow changing \(name)."
        case let .coreAudioFailure(operation, status):
            return "CoreAudio \(operation) failed with status \(status)."
        }
    }
}

enum SystemAudioOutput {
    static func currentVolume() throws -> Double {
        let deviceID = try defaultOutputDeviceID()
        if let main = try? scalarVolume(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return Double(main)
        }

        let channels = try availableVolumeChannels(deviceID: deviceID)
        guard !channels.isEmpty else { throw SystemAudioOutputError.propertyUnavailable("output volume") }
        let values = try channels.map { try scalarVolume(deviceID: deviceID, element: $0) }
        return Double(values.reduce(0, +) / Float32(values.count))
    }

    static func setVolume(_ level: Double) throws {
        let clamped = Float32(min(max(level, 0), 1))
        let deviceID = try defaultOutputDeviceID()
        if isScalarVolumeSettable(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            try setScalarVolume(deviceID: deviceID, element: kAudioObjectPropertyElementMain, value: clamped)
            return
        }

        let channels = try availableVolumeChannels(deviceID: deviceID)
        let writableChannels = channels.filter { isScalarVolumeSettable(deviceID: deviceID, element: $0) }
        guard !writableChannels.isEmpty else { throw SystemAudioOutputError.propertyNotSettable("output volume") }
        for channel in writableChannels {
            try setScalarVolume(deviceID: deviceID, element: channel, value: clamped)
        }
    }

    static func isMuted() throws -> Bool? {
        let deviceID = try defaultOutputDeviceID()
        var address = muteAddress(element: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        guard status == noErr else { throw SystemAudioOutputError.coreAudioFailure("read mute", status) }
        return muted != 0
    }

    @discardableResult
    static func setMuted(_ muted: Bool) throws -> Bool {
        let deviceID = try defaultOutputDeviceID()
        var address = muteAddress(element: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var settable = DarwinBoolean(false)
        let settableStatus = AudioObjectIsPropertySettable(deviceID, &address, &settable)
        guard settableStatus == noErr else { throw SystemAudioOutputError.coreAudioFailure("check mute settable", settableStatus) }
        guard settable.boolValue else { return false }

        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else { throw SystemAudioOutputError.coreAudioFailure("set mute", status) }
        return true
    }

    static func supportsVolumeControl() -> Bool {
        guard let deviceID = try? defaultOutputDeviceID() else { return false }
        if isScalarVolumeSettable(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return true
        }
        guard let channels = try? availableVolumeChannels(deviceID: deviceID) else { return false }
        return channels.contains { isScalarVolumeSettable(deviceID: deviceID, element: $0) }
    }

    private static func defaultOutputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr else { throw SystemAudioOutputError.coreAudioFailure("read default output device", status) }
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { throw SystemAudioOutputError.noDefaultOutputDevice }
        return deviceID
    }

    private static func scalarVolume(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) throws -> Float32 {
        var address = volumeAddress(element: element)
        guard AudioObjectHasProperty(deviceID, &address) else { throw SystemAudioOutputError.propertyUnavailable("output volume") }

        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard status == noErr else { throw SystemAudioOutputError.coreAudioFailure("read output volume", status) }
        return volume
    }

    private static func setScalarVolume(deviceID: AudioDeviceID, element: AudioObjectPropertyElement, value: Float32) throws {
        var address = volumeAddress(element: element)
        guard AudioObjectHasProperty(deviceID, &address) else { throw SystemAudioOutputError.propertyUnavailable("output volume") }

        var settable = DarwinBoolean(false)
        let settableStatus = AudioObjectIsPropertySettable(deviceID, &address, &settable)
        guard settableStatus == noErr else { throw SystemAudioOutputError.coreAudioFailure("check output volume settable", settableStatus) }
        guard settable.boolValue else { throw SystemAudioOutputError.propertyNotSettable("output volume") }

        var mutableValue = value
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &mutableValue)
        guard status == noErr else { throw SystemAudioOutputError.coreAudioFailure("set output volume", status) }
    }

    private static func isScalarVolumeSettable(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
        var address = volumeAddress(element: element)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr && settable.boolValue
    }

    private static func availableVolumeChannels(deviceID: AudioDeviceID) throws -> [AudioObjectPropertyElement] {
        let channels = try outputChannelCount(deviceID: deviceID)
        return (1...max(channels, 2)).compactMap { channel in
            let element = AudioObjectPropertyElement(channel)
            var address = volumeAddress(element: element)
            return AudioObjectHasProperty(deviceID, &address) ? element : nil
        }
    }

    private static func outputChannelCount(deviceID: AudioDeviceID) throws -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard sizeStatus == noErr else { return 2 }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        let bufferList = rawPointer.assumingMemoryBound(to: AudioBufferList.self)
        let dataStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList)
        guard dataStatus == noErr else { return 2 }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func volumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private static func muteAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }
}
