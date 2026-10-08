import Combine
import Dispatch
import Foundation

@MainActor
final class Playback: ObservableObject {
    @discardableResult
    func play() async -> Bool {
        await send(.play)
    }

    @discardableResult
    func pause() async -> Bool {
        await send(.pause)
    }

    private func send(_ command: Command) async -> Bool {
        let targetIsPlaying = command == .play
        guard await isPlaying() != targetIsPlaying else { return false }
        guard MRMediaRemoteSendCommand(command.rawValue, nil) else {
            print("Playback: Couldn't send the playback command to the current media app.")
            return false
        }
        // Media apps apply commands asynchronously; only report a confirmed change.
        for _ in 0..<10 {
            if await isPlaying() == targetIsPlaying { return true }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return false }
        }
        return false
    }

    private func isPlaying() async -> Bool {
        await withCheckedContinuation { continuation in
            MRMediaRemoteGetNowPlayingApplicationIsPlaying(DispatchQueue.main) { playing in
                continuation.resume(returning: playing)
            }
        }
    }

    private enum Command: Int32 {
        case play = 0
        case pause = 1
    }
}
