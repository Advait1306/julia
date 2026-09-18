import Foundation

public enum JuliaPaths {
    public static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Julia")
    }
    public static var modelDirectory: URL { support.appendingPathComponent("Models/qwen3.5-0.8b-mlx-4bit") }
    public static var logs: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Julia")
    }
    public static func create(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }
}
