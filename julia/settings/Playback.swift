import Combine
import Foundation

@MainActor
final class Playback: ObservableObject {
    func play() {
        send(.play)
    }

    func pause() {
        send(.pause)
    }

    private func send(_ command: Command) {
        guard MRMediaRemoteSendCommand(command.rawValue, nil) else {
            print("Playback: Couldn't send the playback command to the current media app.")
            return
        }
    }

    private enum Command: Int32 {
        case play = 0
        case pause = 1
    }
}
