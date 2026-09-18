import Foundation
import OSLog

public struct TraceEvent: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let sessionID: UUID
    public let turnID: UUID?
    public let step: Int?
    public let kind: String
    public let payload: JSONValue
}

/// Full local JSONL traces. OSLog receives metadata only; file payloads include exact model I/O.
public final class TraceLog: @unchecked Sendable {
    public let sessionID = UUID()
    public let fileURL: URL
    private let lock = NSLock()
    private var handle: FileHandle?
    private let logger = Logger(subsystem: "dev.advait.julia", category: "Harness")
    public var onEvent: (@Sendable (TraceEvent) -> Void)?

    public init(directory: URL = JuliaPaths.logs) throws {
        try JuliaPaths.create(directory)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        fileURL = directory.appendingPathComponent("\(stamp)-\(sessionID.uuidString.prefix(8)).jsonl")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        handle = try FileHandle(forWritingTo: fileURL)
        // Bounded retention across sessions. Current session is never pruned.
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "jsonl" && $0 != fileURL }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in files.dropFirst(19) { try? FileManager.default.removeItem(at: file) }
    }
    deinit { try? handle?.close() }

    public func record(_ kind: String, turn: UUID? = nil, step: Int? = nil, _ payload: JSONValue = .object([:])) {
        let event = TraceEvent(id: UUID(), timestamp: Date(), sessionID: sessionID,
                               turnID: turn, step: step, kind: kind, payload: payload)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            var bytes = try encoder.encode(event); bytes.append(0x0a)
            lock.lock()
            defer { lock.unlock() }
            try handle?.write(contentsOf: bytes)
        } catch {
            logger.error("Trace write failed: \(error.localizedDescription, privacy: .public)")
        }
        logger.info("\(kind, privacy: .public) turn=\(turn?.uuidString ?? "-", privacy: .public) step=\(step ?? -1)")
        onEvent?(event)
    }
}
