import Foundation
import Darwin

enum OsascriptLanguage { case appleScript, javaScript }
struct OsascriptResult {
    let status: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

/// Fixed scripts only. No shell invocation, GUI scripting, MCP, or model-generated code.
enum OsascriptRunner {
    static let defaultTimeout: TimeInterval = 30
    static func run(script: String, language: OsascriptLanguage = .appleScript,
                    timeout: TimeInterval = defaultTimeout, appName: String, timeoutHint: String? = nil) -> String? {
        guard let result = runRaw(script: script, language: language, timeout: timeout) else {
            JSONOutput.error("Could not start app automation for \(appName)."); return nil
        }
        if result.timedOut {
            JSONOutput.error("\(appName) operation timed out or was cancelled. Check the app before retrying a write. \(timeoutHint ?? "")")
            return nil
        }
        guard result.status == 0 else {
            if result.stderr.contains("-1743") {
                JSONOutput.error("Allow Julia to control \(appName) in System Settings → Privacy & Security → Automation.")
            } else { JSONOutput.error("\(appName): \(result.stderr)") }
            return nil
        }
        return result.stdout
    }
    static func runRaw(script: String, language: OsascriptLanguage = .appleScript,
                       timeout: TimeInterval = defaultTimeout) -> OsascriptResult? {
        let args = language == .javaScript ? ["-l", "JavaScript", "-e", script] : ["-e", script]
        return BoundedProcess.run(executable: "/usr/bin/osascript", arguments: args, timeout: timeout)
    }
}

enum BoundedProcess {
    static func run(executable: String, arguments: [String], timeout: TimeInterval = 20) -> OsascriptResult? {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("julia-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? fm.removeItem(at: dir) }
            let output = dir.appendingPathComponent("out"), error = dir.appendingPathComponent("err")
            fm.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
            fm.createFile(atPath: error.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let out = try FileHandle(forWritingTo: output), err = try FileHandle(forWritingTo: error)
            defer { try? out.close(); try? err.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = out; process.standardError = err
            try Task.checkCancellation()
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            var timedOut = false
            while process.isRunning {
                let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if Task.isCancelled || Date() > deadline || size > 8 * 1024 * 1024 {
                    timedOut = true
                    process.terminate()
                    // PID remains owned until this Process is reaped.
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    break
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
            process.waitUntilExit()
            func read(_ url: URL) -> String {
                guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
                defer { try? h.close() }
                return String(decoding: (try? h.read(upToCount: 8 * 1024 * 1024)) ?? Data(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return .init(status: process.terminationStatus, stdout: read(output), stderr: read(error), timedOut: timedOut)
        } catch { return nil }
    }
}
