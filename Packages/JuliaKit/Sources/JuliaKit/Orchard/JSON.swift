import Foundation

/// Orchard's output boundary adapted from stdout to a task-local, in-memory result.
enum JSONOutput {
    @TaskLocal static var sink: ResultSink?
    static func success(_ data: Any) {
        do { sink?.value = .object(["status": .string("ok"), "data": try JSONValue(any: data)]) }
        catch { self.error("Cannot encode tool result: \(error.localizedDescription)") }
    }
    static func error(_ message: String) { sink?.value = .object(["status": .string("error"), "error": .string(message)]) }
}

final class ResultSink: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: JSONValue?
    var value: JSONValue? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

func iso8601(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
