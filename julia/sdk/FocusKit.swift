import Combine
import Darwin
import Foundation

// NOTE: FocusKit in an unstable Kit made for testing the focus features of Julia.
// While it's API will remain stable, it's underlying implementation might change based on future discoveries.

/**
 A reusable interface to the current user's macOS Focus database.

 FocusKit owns the system details: JSON decoding, assertion writes, filesystem
 observation, and restarting donotdisturbd. The settings layer owns published
 UI state, sorting, and logging. The API and file-change notifications run on
 the main actor, so the settings layer can refresh its state directly.

 ```text
 UI / Jev
    |
    v
 settings/Focus                  Publishes modes, state, and isUpdating
    |
    | readModes(), readState(), switchMode(to:), disable(), changes
    v
 sdk/FocusKit
    |
    +--> ~/Library/DoNotDisturb/DB/ModeConfigurations.json
    |       Configured mode IDs, names, and visibility
    |
    +--> ~/Library/DoNotDisturb/DB/Assertions.json
    |       Active assertions, history, and database header
    |
    +--> donotdisturbd             Reloads the assertions after a write
 ```

 READING MODES AND STATE

 Initialization starts file observation; it does not read or cache a snapshot.
 Consumers subscribe to `changes` and perform their own initial reads. Each
 read decodes the current file and requires exactly one database store.
 `readModes()` returns modes whose visibility is 0. Sorting belongs to the
 consumer. `readState()` examines the distinct mode IDs in active assertions:

 ```text
 Distinct mode IDs     isActive     currentModeID
 -----------------    --------     -------------
 0                    false        nil             Focus is off
 1                    true         that mode ID    One identifiable mode
 More than 1          nil          nil             Selection is ambiguous
 ```

 Several assertions can refer to the same mode. Their order does not identify
 the selected mode when different IDs coexist, so we leave that state unknown.
 File access and decoding errors throw; the settings layer clears the affected
 published values and logs the error. An unreadable file is not treated as Off.

 OBSERVING CHANGES WITHOUT POLLING

 `changes` is an invalidation signal, not a stream of cached state. It has no
 initial or replayed value; subscribers call the read APIs to get a snapshot.

 ```text
 DB directory ----+                Catches atomic file replacements
 Modes file ------+                Catches in-place writes
 Assertions file -+
                  |
                  v
         DispatchSource filesystem event
                  |
                  v
         Main actor: cancel old watches and attach new ones
                  |                Replacements have new file descriptors
                  v
         changes emits ()
                  |
                  v
         Subscriber rereads modes and state
 ```

 Inaccessible paths are skipped rather than retried on a timer. Watchers are
 cancelled on teardown, and their cancellation handlers close the descriptors.

 SWITCHING OR TURNING FOCUS OFF

 Both actions use `setMode`: a mode ID means one new user-action assertion;
 nil means an empty active assertion list. These replace the entire active
 list, including assertions previously created by other clients. History and
 other database fields are preserved.

 ```text
 switchMode(to: id) / disable()
          |
          v
 Reject an overlapping change on this FocusKit instance
          |
          v
 Revalidate a requested ID against the visible configured modes
          |
          v
 Save original assertion bytes; require one store and header version 8
          |
          v
 Compare existing mode ID set with the requested set
          | equal -----------------> Return without writing or restarting
          |                          (preserve the existing assertion lifetime)
          | different
          v
 Replace active records; update header timestamp; preserve other fields
          |
          v
 Atomically write Assertions.json
          |
          v
 Restart donotdisturbd, then reread and compare the resulting mode ID set
          |
          +-- match ----------------> Return successfully
          |
          +-- reload / verify error
                    |
                    v
             Does the file still equal the bytes we wrote?
                    |
                    +-- yes --> Restore original bytes and restart again
                    +-- no ---> Leave the newer file alone
                    |
                    v
             Throw (a rollback failure can also propagate)
 ```

 Restarting finds the current user's daemon processes, sends SIGTERM, waits
 for process-exit events, then calls a regular launchctl kickstart. The exit
 wait has a single five-second timeout. There is no process polling, and we
 avoid kickstart -k because SIP blocks that operation on the target Mac.

 Verification checks the resulting database assertions; it does not query the
 daemon's live selection through a private framework. The rollback byte check
 avoids replacing a newer update that we observe after our write; it is not a
 lock against other processes changing the database.

 Julia needs Full Disk Access to use these protected files. The directory and
 reload implementation are internal, and the database format is private to
 macOS. Writes deliberately reject assertion header versions other than 8.
 */
@MainActor
final class FocusKit {
    struct State {
        let isActive: Bool?
        let currentModeID: String?
    }

    var changes: AnyPublisher<Void, Never> { updates.eraseToAnyPublisher() }

    private let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    private let updates = PassthroughSubject<Void, Never>()
    private var observers: [DispatchSourceFileSystemObject] = []
    private var isUpdating = false

    init() {
        startObserving()
    }

    func readModes() throws -> [FocusMode] {
        let database = try read(Configurations.self, named: "ModeConfigurations.json")
        guard database.data.count == 1 else { throw Failure.unsupportedDatabase }
        return database.data[0].modeConfigurations.values.map(\.mode)
            .filter { $0.visibility == 0 }
            .map { FocusMode(id: $0.modeIdentifier, name: $0.name) }
    }

    func readState() throws -> State {
        let database = try read(Assertions.self, named: "Assertions.json")
        guard database.data.count == 1 else { throw Failure.unsupportedDatabase }
        let assertions = database.data[0].storeAssertionRecords ?? []
        let identifiers = Set(assertions.map { $0.assertionDetails.assertionDetailsModeIdentifier })
        // Multiple assertions can coexist (including assertions from other devices).
        // Their order does not reliably identify the currently selected Focus.
        return State(isActive: identifiers.count > 1 ? nil : !assertions.isEmpty,
                     currentModeID: identifiers.count == 1 ? identifiers.first : nil)
    }

    func switchMode(to id: String) async throws {
        try await setMode(id)
    }

    func disable() async throws {
        try await setMode(nil)
    }

    private func setMode(_ id: String?) async throws {
        guard !isUpdating else { throw Failure.updateInProgress }
        isUpdating = true
        defer { isUpdating = false }

        // Revalidate against the database at action time, since the caller's snapshot may be older.
        if let id {
            let configurations = try read(Configurations.self, named: "ModeConfigurations.json")
            guard configurations.data.count == 1,
                  configurations.data[0].modeConfigurations.values.contains(where: {
                      $0.mode.modeIdentifier == id && $0.mode.visibility == 0
                  }) else { throw Failure.unavailableMode }
        }

        let url = directory.appendingPathComponent("Assertions.json")
        let original = try Data(contentsOf: url)
        let current = try JSONDecoder().decode(Assertions.self, from: original)
        guard var database = try JSONSerialization.jsonObject(with: original) as? [String: Any],
              var stores = database["data"] as? [[String: Any]], stores.count == 1,
              current.data.count == 1,
              var header = database["header"] as? [String: Any],
              header["version"] as? Int == 8 else { throw Failure.unsupportedDatabase }

        let currentIdentifiers = Set((current.data[0].storeAssertionRecords ?? []).map {
            $0.assertionDetails.assertionDetailsModeIdentifier
        })
        let requestedIdentifiers = Set(id.map { [$0] } ?? [])
        guard currentIdentifiers != requestedIdentifiers else { return }

        let now = Date().timeIntervalSinceReferenceDate
        let client = Bundle.main.bundleIdentifier ?? "com.advait.julia"
        let assertions: [[String: Any]]
        if let id {
            assertions = [[
                "assertionUUID": UUID().uuidString,
                "assertionStartDateTimestamp": now,
                "assertionSource": ["assertionClientIdentifier": client],
                "assertionDetails": [
                    "assertionDetailsIdentifier": client,
                    "assertionDetailsModeIdentifier": id,
                    "assertionDetailsReason": "user-action"
                ]
            ]]
        } else {
            assertions = []
        }
        // Keep all other fields, including invalidation history and unknown future fields.
        stores[0]["storeAssertionRecords"] = assertions
        database["data"] = stores
        header["timestamp"] = now
        database["header"] = header
        let updated = try JSONSerialization.data(withJSONObject: database, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: url, options: .atomic)
        do {
            try await Self.restartDaemon()
            // The daemon may rewrite the database on startup. Verify the resulting assertion.
            let result = try read(Assertions.self, named: "Assertions.json")
            guard result.data.count == 1 else { throw Failure.unsupportedDatabase }
            let identifiers = Set((result.data[0].storeAssertionRecords ?? []).map {
                $0.assertionDetails.assertionDetailsModeIdentifier
            })
            guard identifiers == requestedIdentifiers else { throw Failure.modeNotApplied }
        } catch {
            // Roll back our write only if no newer system/user update has replaced it.
            if try Data(contentsOf: url) == updated {
                try original.write(to: url, options: .atomic)
                try await Self.restartDaemon()
            }
            throw error
        }
    }

    private static func restartDaemon() async throws {
        let output = try await run("/usr/bin/pgrep", ["-u", String(getuid()), "-x", "donotdisturbd"],
                                   allowedStatuses: [0, 1])
        let identifiers = output.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
        for pid in identifiers {
            try await terminate(pid)
        }
        // -k is blocked by SIP. A regular start after SIGTERM is permitted.
        _ = try await run("/bin/launchctl", ["kickstart", "gui/\(getuid())/com.apple.donotdisturbd"])
    }

    private static func terminate(_ pid: pid_t) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let observer = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
            let timeout = DispatchSource.makeTimerSource(queue: .main)
            observer.setEventHandler {
                observer.cancel()
                timeout.cancel()
                continuation.resume()
            }
            timeout.setEventHandler {
                observer.cancel()
                timeout.cancel()
                continuation.resume(throwing: Failure.restartTimedOut)
            }
            // Bound the shutdown wait if the daemon stalls.
            timeout.schedule(deadline: .now() + 5)
            observer.resume()
            timeout.resume()
            if kill(pid, SIGTERM) != 0 {
                observer.cancel()
                timeout.cancel()
                if errno == ESRCH {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM))
                }
            }
        }
    }

    private static func run(_ executable: String, _ arguments: [String],
                            allowedStatuses: Set<Int32> = [0]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            process.terminationHandler = { process in
                let message = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if allowedStatuses.contains(process.terminationStatus) {
                    continuation.resume(returning: message)
                } else {
                    continuation.resume(throwing: Failure.commandFailed(message))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func read<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: directory.appendingPathComponent(name)))
    }

    private func startObserving() {
        // Watch the directory for atomic replacements, and the files for in-place writes.
        // If the database is inaccessible, retain an unavailable state without polling.
        for url in [directory, directory.appendingPathComponent("ModeConfigurations.json"),
                    directory.appendingPathComponent("Assertions.json")] {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let observer = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .revoke], queue: .main
            )
            observer.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.stopObserving()
                    self.startObserving()
                    self.updates.send(())
                }
            }
            observer.setCancelHandler { close(descriptor) }
            observers.append(observer)
            observer.resume()
        }
    }

    private func stopObserving() {
        for observer in observers { observer.cancel() }
        observers.removeAll()
    }

    isolated deinit {
        stopObserving()
    }

    enum Failure: LocalizedError {
        case unsupportedDatabase, unavailableMode, modeNotApplied, updateInProgress, restartTimedOut
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedDatabase: return "The Focus database format is unsupported."
            case .unavailableMode: return "The requested Focus mode is no longer available."
            case .modeNotApplied: return "macOS did not retain the requested Focus mode."
            case .updateInProgress: return "A Focus change is already in progress."
            case .restartTimedOut: return "The Focus service did not finish restarting."
            case .commandFailed(let message): return "Couldn't restart the Focus service: \(message)"
            }
        }
    }

    private struct Configurations: Decodable {
        struct Store: Decodable {
            struct Configuration: Decodable {
                struct Mode: Decodable {
                    let modeIdentifier: String
                    let name: String
                    let visibility: Int
                }
                let mode: Mode
            }
            let modeConfigurations: [String: Configuration]
        }
        let data: [Store]
    }

    private struct Assertions: Decodable {
        struct Store: Decodable {
            struct Assertion: Decodable {
                struct Details: Decodable {
                    let assertionDetailsModeIdentifier: String
                }
                let assertionDetails: Details
            }
            let storeAssertionRecords: [Assertion]?
        }
        let data: [Store]
    }
}

nonisolated struct FocusMode: Identifiable, Encodable, Equatable, Sendable {
    let id: String
    let name: String
}
