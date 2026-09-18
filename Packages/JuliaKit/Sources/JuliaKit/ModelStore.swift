import Foundation
import CryptoKit

public struct ModelProgress: Sendable {
    public let message: String
    public let fraction: Double?
    public init(_ message: String, fraction: Double? = nil) { self.message = message; self.fraction = fraction }
}

public actor ModelStore {
    public static let modelName = "LiquidAI/LFM2.5-350M-GGUF:Q8_0"
    public static let displayName = "LFM2.5 350M"
    // Pin both revision and checksum so cached/offline launches use the same weights.
    private static let revision = "9969000761ce34de907bf20017cbfc3d52d6eaf9"
    private static let filename = "LFM2.5-350M-Q8_0.gguf"
    private static let modelSize: Int64 = 379_217_632
    private static let modelSHA256 = "be036a757295e550098b85e13f6af2735d0fa73b41e1156a40c7d8e8e32a5766"
    private static let licenseSHA256 = "5188f2b355da20647257a3156db5834c794e5fb5e6d8dc4d4cdbb3180e75b85b"
    private let directory: URL
    public init(directory: URL = JuliaPaths.modelDirectory) { self.directory = directory }

    public func prepare(progress: @escaping @Sendable (ModelProgress) -> Void) async throws -> URL {
        try JuliaPaths.create(directory)
        let file = directory.appendingPathComponent("model.gguf")
        progress(.init("Verifying model…"))
        if FileManager.default.fileExists(atPath: file.path) {
            if try await digest(file) == Self.modelSHA256 {
                try await saveMetadata()
                return file
            }
            try FileManager.default.removeItem(at: file)
        }
        progress(.init("Downloading \(Self.displayName)", fraction: 0))
        let delegate = DownloadProgress { written, expected in
            progress(.init("Downloading \(Self.displayName)", fraction: Double(written) / Double(max(expected, Self.modelSize))))
        }
        let request = URLRequest(url: Self.downloadURL(Self.filename), timeoutInterval: 3600)
        let (temporary, response) = try await URLSession.shared.download(for: request, delegate: delegate)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try validate(response)
        let attrs = try FileManager.default.attributesOfItem(atPath: temporary.path)
        guard (attrs[.size] as? NSNumber)?.int64Value == Self.modelSize else { throw JuliaError("The model download is incomplete. Retry to download again.") }
        progress(.init("Verifying model…"))
        guard try await digest(temporary) == Self.modelSHA256 else { throw JuliaError("Model checksum failed. Retry to download a verified copy.") }
        let h = try FileHandle(forReadingFrom: temporary); let magic = try h.read(upToCount: 4); try h.close()
        guard magic == Data("GGUF".utf8) else { throw JuliaError("The downloaded model is not GGUF.") }
        try Task.checkCancellation()
        // Copy via a same-directory staging file, then rename atomically.
        let staging = directory.appendingPathComponent("model.gguf.partial")
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.copyItem(at: temporary, to: staging)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
        try FileManager.default.moveItem(at: staging, to: file)
        try await saveMetadata()
        return file
    }
    private func saveMetadata() async throws {
        let license = directory.appendingPathComponent("LICENSE.txt")
        if (try? await digest(license)) != Self.licenseSHA256 {
            let (bytes, response) = try await URLSession.shared.data(from: Self.downloadURL("LICENSE"))
            try validate(response)
            guard SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == Self.licenseSHA256 else {
                throw JuliaError("Model license checksum failed.")
            }
            try bytes.write(to: license, options: .atomic)
        }
        let receipt = ["model": Self.modelName, "revision": Self.revision,
                       "filename": Self.filename, "sha256": Self.modelSHA256]
        try JSONEncoder().encode(receipt).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }
    private static func downloadURL(_ filename: String) -> URL {
        URL(string: "https://huggingface.co/LiquidAI/LFM2.5-350M-GGUF/resolve/\(revision)/\(filename)")!
    }
    private func validate(_ response: URLResponse) throws {
        guard let h = response as? HTTPURLResponse, (200...299).contains(h.statusCode) else { throw JuliaError("Hugging Face download failed. Check your connection and retry.") }
    }
    private func digest(_ file: URL) async throws -> String {
        let task = Task.detached(priority: .utility) {
            let h = try FileHandle(forReadingFrom: file); defer { try? h.close() }
            var hash = SHA256()
            while let data = try h.read(upToCount: 1024 * 1024), !data.isEmpty {
                try Task.checkCancellation(); hash.update(data: data)
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let update: @Sendable (Int64, Int64) -> Void
    init(_ update: @escaping @Sendable (Int64, Int64) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) { update(totalBytesWritten, totalBytesExpectedToWrite) }
}
