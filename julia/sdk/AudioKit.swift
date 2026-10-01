import Combine
import CoreAudio
import Foundation

/**
 Reads, observes, and controls the current user's macOS audio output.

 All APIs and notifications run on the main actor. Initialization starts
 CoreAudio observation without requiring configuration.

 - `readDevices()` returns unsorted output devices with IDs and display names.
 - `readState()` reads the default output ID and the system output mute state.
   Both fields are nil when there is no default output device.
 - `switchDevice(to:)` sets the default output device.
 - `mute()` and `unmute()` return the resulting system output mute value.

 Reads and controls throw on failure; AudioKit does not log errors or substitute
 default values. Device IDs describe the current hardware and are not persistent
 identifiers. Mute uses AppleScript's system volume settings, matching macOS's
 output mute behavior rather than requiring a hardware mute control.

 `changes` emits invalidations for device additions/removals, output selection,
 device names, and supported output mute properties. It has no initial or
 replayed value. Subscribe before reading an initial snapshot, then reread when
 notified. Reads always query the system rather than returning cached state.

 `observationErrors` replays the current list of listener setup failures (empty
 when all listeners were attached). Observation is best effort: failed listeners
 do not prevent reads or controls, but their notifications cannot be guaranteed.
 Device listeners are rebuilt when the device list or a device name changes.
 Listeners are removed on teardown; AudioKit does not poll.
 */
@MainActor
final class AudioKit {
    struct State {
        let selectedDeviceID: AudioDeviceID?
        let isMuted: Bool?
    }

    var changes: AnyPublisher<Void, Never> { updates.eraseToAnyPublisher() }
    var observationErrors: AnyPublisher<[Error], Never> { listenerErrors.eraseToAnyPublisher() }

    private let system = AudioHardwareSystem(id: AudioObjectID(kAudioObjectSystemObject))
    private let systemProperties = [PropertyAddress(kAudioHardwarePropertyDevices),
                                    PropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)]
    private let updates = PassthroughSubject<Void, Never>()
    private let listenerErrors = CurrentValueSubject<[Error], Never>([])
    private var systemObservationErrors: [Error] = []
    private var observedDevices: [(AudioHardwareDevice, [AudioObjectPropertyAddress])] = []
    private lazy var observer = Observer(kit: self)

    init() {
        system.delegates = [observer]
        do {
            try system.addListener(forProperties: systemProperties, dispatchQueue: .main)
        } catch {
            systemObservationErrors = [error]
        }
        observeDevices()
    }

    func readDevices() throws -> [AudioDevice] {
        try outputDevices().map { AudioDevice(id: $0.id, name: try $0.name) }
    }

    func readState() throws -> State {
        let id = try system.defaultOutputDevice?.id
        return State(selectedDeviceID: id,
                     isMuted: id == nil ? nil : try runScript("output muted of (get volume settings)"))
    }

    @discardableResult
    func mute() throws -> Bool {
        try runScript("set volume output muted true\noutput muted of (get volume settings)")
    }

    @discardableResult
    func unmute() throws -> Bool {
        try runScript("set volume output muted false\noutput muted of (get volume settings)")
    }

    func switchDevice(to id: AudioDeviceID) throws {
        try system.setDefaultOutputDevice(AudioHardwareDevice(id: id))
    }

    private func outputDevices() throws -> [AudioHardwareDevice] {
        try system.devices.filter { try $0.canBeDefaultOutputDevice }
    }

    private func runScript(_ source: String) throws -> Bool {
        guard let script = NSAppleScript(source: source) else { throw Failure.invalidScript }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            throw Failure.scriptFailed(String(describing: error[NSAppleScript.errorMessage] ?? error))
        }
        return result.booleanValue
    }

    private func observeDevices() {
        var errors = systemObservationErrors
        do {
            let outputs = try outputDevices()
            stopObservingDevices()
            for device in outputs {
                var properties = [PropertyAddress(kAudioObjectPropertyName)]
                let mute = PropertyAddress(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
                if device.hasProperty(address: mute) { properties.append(mute) }
                device.delegates = [observer]
                // Retain the device even on partial setup failure so teardown removes its listeners.
                observedDevices.append((device, properties))
                do {
                    try device.addListener(forProperties: properties, dispatchQueue: .main)
                } catch {
                    errors.append(error)
                }
            }
        } catch {
            errors.append(error)
        }
        listenerErrors.send(errors)
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
        weak var kit: AudioKit?

        func propertiesChanged(properties: [AudioObjectPropertyAddress]) {
            Task { @MainActor [weak kit] in
                guard let kit else { return }
                if properties.contains(where: {
                    $0.mSelector == kAudioHardwarePropertyDevices || $0.mSelector == kAudioObjectPropertyName
                }) {
                    kit.observeDevices()
                }
                kit.updates.send(())
            }
        }
    }

    enum Failure: LocalizedError {
        case invalidScript
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidScript: return "Couldn't create the audio control script."
            case .scriptFailed(let message): return "Couldn't access system output mute: \(message)"
            }
        }
    }
}

nonisolated struct AudioDevice: Identifiable, Encodable, Equatable, Sendable {
    let id: AudioDeviceID
    let name: String
}
