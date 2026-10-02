import Combine
import CoreAudio
import Foundation

@MainActor
final class Audio: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var selectedDeviceID: AudioDeviceID?
    @Published private(set) var isMuted: Bool?

    private let kit = AudioKit()
    private var observations: Set<AnyCancellable> = []

    init() {
        kit.changes.sink { [weak self] in self?.refresh() }
            .store(in: &observations)
        kit.observationErrors.sink { errors in
            for error in errors {
                print("Audio: Couldn't observe audio changes: \(error.localizedDescription)")
            }
        }
        .store(in: &observations)
        refresh()
    }

    func mute() {
        setMuted(true)
    }

    func unmute() {
        setMuted(false)
    }

    func switchDevice(to id: AudioDeviceID) throws {
        defer { refreshOutput() }
        try kit.switchDevice(to: id)
    }

    private func setMuted(_ muted: Bool) {
        do {
            isMuted = try muted ? kit.mute() : kit.unmute()
        } catch {
            isMuted = nil
            print("Audio: Couldn't change output mute: \(error.localizedDescription)")
        }
    }

    private func refresh() {
        do {
            devices = try kit.readDevices()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            devices = []
            print("Audio: Couldn't read output devices: \(error.localizedDescription)")
        }
        refreshOutput()
    }

    private func refreshOutput() {
        do {
            let state = try kit.readState()
            selectedDeviceID = state.selectedDeviceID
            isMuted = state.isMuted
        } catch {
            selectedDeviceID = nil
            isMuted = nil
            print("Audio: Couldn't read output state: \(error.localizedDescription)")
        }
    }
}
