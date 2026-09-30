import Combine
import Darwin
import Foundation

@MainActor
final class Focus: ObservableObject {
    @Published private(set) var modes: [FocusMode]?
    @Published private(set) var isActive: Bool?
    @Published private(set) var currentModeID: String?
    @Published private(set) var isUpdating = false

    private let directory: URL
    private let reloadSystem: @MainActor () async throws -> Void
    private var observers: [DispatchSourceFileSystemObject] = []

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true),
         reloadSystem: (@MainActor () async throws -> Void)? = nil) {
        self.directory = directory
        self.reloadSystem = reloadSystem ?? Self.restartDaemon
        startObserving()
        refresh()
    }

    func switchMode(to id: String) async throws {
        try await setMode(id)
    }

    func disable() async throws {
        try await setMode(nil)
    }

    private func setMode(_ id: String?) async throws {
        guard !isUpdating else { throw FocusError.updateInProgress }
        isUpdating = true
        defer {
            isUpdating = false
            refresh()
        }

        // Revalidate against the database at action time, since Jev's snapshot may be older.
        if let id {
            let configurations = try read(Configurations.self, named: "ModeConfigurations.json")
            guard configurations.data.count == 1,
                  configurations.data[0].modeConfigurations.values.contains(where: {
                      $0.mode.modeIdentifier == id && $0.mode.visibility == 0
                  }) else { throw FocusError.unavailableMode }
        }

        let url = directory.appendingPathComponent("Assertions.json")
        let original = try Data(contentsOf: url)
        let current = try JSONDecoder().decode(Assertions.self, from: original)
        guard var database = try JSONSerialization.jsonObject(with: original) as? [String: Any],
              var stores = database["data"] as? [[String: Any]], stores.count == 1,
              current.data.count == 1,
              var header = database["header"] as? [String: Any],
              header["version"] as? Int == 8 else { throw FocusError.unsupportedDatabase }

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
            try await reloadSystem()
            // The daemon may rewrite the database on startup. Verify the resulting assertion.
            let result = try read(Assertions.self, named: "Assertions.json")
            guard result.data.count == 1 else { throw FocusError.unsupportedDatabase }
            let identifiers = Set((result.data[0].storeAssertionRecords ?? []).map {
                $0.assertionDetails.assertionDetailsModeIdentifier
            })
            guard identifiers == requestedIdentifiers else { throw FocusError.modeNotApplied }
        } catch {
            // Roll back our write only if no newer system/user update has replaced it.
            if try Data(contentsOf: url) == updated {
                try original.write(to: url, options: .atomic)
                try await reloadSystem()
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
                continuation.resume(throwing: FocusError.restartTimedOut)
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
                    continuation.resume(throwing: FocusError.commandFailed(message))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func refresh() {
        do {
            let database = try read(Configurations.self, named: "ModeConfigurations.json")
            guard database.data.count == 1 else { throw FocusError.unsupportedDatabase }
            modes = database.data[0].modeConfigurations.values.map(\.mode)
                .filter { $0.visibility == 0 }
                .map { FocusMode(id: $0.modeIdentifier, name: $0.name) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            modes = nil
            print("Focus: Couldn't read configured modes: \(error.localizedDescription)")
        }

        do {
            let database = try read(Assertions.self, named: "Assertions.json")
            guard database.data.count == 1 else { throw FocusError.unsupportedDatabase }
            let assertions = database.data[0].storeAssertionRecords ?? []
            let identifiers = Set(assertions.map { $0.assertionDetails.assertionDetailsModeIdentifier })
            // Multiple assertions can coexist (including assertions from other devices).
            // Their order does not reliably identify the currently selected Focus.
            isActive = identifiers.count > 1 ? nil : !assertions.isEmpty
            currentModeID = identifiers.count == 1 ? identifiers.first : nil
        } catch {
            isActive = nil
            currentModeID = nil
            print("Focus: Couldn't read current mode: \(error.localizedDescription)")
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
                    self.refresh()
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

    private enum FocusError: LocalizedError {
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
