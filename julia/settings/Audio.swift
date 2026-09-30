import Combine
import CoreAudio
import Foundation

@MainActor
final class Audio: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var selectedDeviceID: AudioDeviceID?
    @Published private(set) var isMuted: Bool?

    private let system = AudioHardwareSystem(id: AudioObjectID(kAudioObjectSystemObject))
    private let systemProperties = [PropertyAddress(kAudioHardwarePropertyDevices),
                                    PropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)]
    private var observedDevices: [(AudioHardwareDevice, [AudioObjectPropertyAddress])] = []
    private lazy var observer = Observer(audio: self)

    init() {
        system.delegates = [observer]
        do {
            try system.addListener(forProperties: systemProperties, dispatchQueue: .main)
        } catch {
            print("Audio: \(error.localizedDescription)")
        }
        refreshDevices()
    }

    func mute() {
        isMuted = runScript("set volume output muted true\noutput muted of (get volume settings)")
    }

    func unmute() {
        isMuted = runScript("set volume output muted false\noutput muted of (get volume settings)")
    }

    func switchDevice(to id: AudioDeviceID) throws {
        try system.setDefaultOutputDevice(AudioHardwareDevice(id: id))
        refreshOutput()
    }

    private func refreshDevices() {
        do {
            let outputs = try system.devices.filter { try $0.canBeDefaultOutputDevice }
            devices = try outputs.map { AudioDevice(id: $0.id, name: try $0.name) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            stopObservingDevices()
            for device in outputs {
                var properties = [PropertyAddress(kAudioObjectPropertyName)]
                let mute = PropertyAddress(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
                if device.hasProperty(address: mute) { properties.append(mute) }
                device.delegates = [observer]
                observedDevices.append((device, properties))
                do {
                    try device.addListener(forProperties: properties, dispatchQueue: .main)
                } catch {
                    print("Audio: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Audio: \(error.localizedDescription)")
        }
        refreshOutput()
    }

    private func refreshOutput() {
        do {
            selectedDeviceID = try system.defaultOutputDevice?.id
            isMuted = selectedDeviceID == nil ? nil : runScript("output muted of (get volume settings)")
        } catch {
            selectedDeviceID = nil
            isMuted = nil
            print("Audio: \(error.localizedDescription)")
        }
    }

    private func runScript(_ source: String) -> Bool? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            print("Audio: \(error[NSAppleScript.errorMessage] ?? error)")
            return nil
        }
        return result.booleanValue
    }

    private func stopObservingDevices() {
        for (device, properties) in observedDevices {
            try? device.removeListener(forProperties: properties, dispatchQueue: .main)
            device.delegates = []
        }
        observedDevices.removeAll()
    }

    isolated deinit {
        try? system.removeListener(forProperties: systemProperties, dispatchQueue: .main)
        system.delegates = []
        stopObservingDevices()
    }

    private nonisolated struct Observer: PropertyListenerDelegate {
        weak var audio: Audio?

        func propertiesChanged(properties: [AudioObjectPropertyAddress]) {
            Task { @MainActor [weak audio] in
                if properties.contains(where: {
                    $0.mSelector == kAudioHardwarePropertyDevices || $0.mSelector == kAudioObjectPropertyName
                }) {
                    audio?.refreshDevices()
                } else {
                    audio?.refreshOutput()
                }
            }
        }
    }
}

nonisolated struct AudioDevice: Identifiable, Encodable, Equatable, Sendable {
    let id: AudioDeviceID
    let name: String
}
