import Foundation
import CryptoKit

public struct ModelProgress: Sendable {
    public let message: String
    public let fraction: Double?
    public init(_ message: String, fraction: Double? = nil) { self.message = message; self.fraction = fraction }
}

public actor ModelStore {
    public static let modelName = "mlx-community/Qwen3.5-0.8B-4bit"
    public static let displayName = "Qwen 3.5 0.8B · MLX"
    private static let revision = "da28692b5f139cb0ec58a356b437486b7dac7462"
    private struct Artifact: Codable {
        let name: String
        let size: Int64
        let sha256: String
    }
    private static let artifacts: [Artifact] = [
        .init(name: "config.json", size: 3112, sha256: "ba7770da23eae5ebd6827571f086e331956b33f4442a9e876fb4aa10969a6772"),
        .init(name: "model.safetensors", size: 625229487, sha256: "f5a0d9dd3efa73510542a8023d610ff26be2b4b020d181cfc4bedaa1fcc5dd9e"),
        .init(name: "model.safetensors.index.json", size: 71473, sha256: "6e48f2fa5d6f033a6d77bf833abfa9698ca24d1715ecea4c67447bcfaee44650"),
        .init(name: "tokenizer.json", size: 19989343, sha256: "87a7830d63fcf43bf241c3c5242e96e62dd3fdc29224ca26fed8ea333db72de4"),
        .init(name: "tokenizer_config.json", size: 1139, sha256: "e98f1901ac6f0adff67b1d540bfa0c36ac1a0cf59eb72ed78146ef89aafa1182"),
        .init(name: "chat_template.jinja", size: 7755, sha256: "273d8e0e683b885071fb17e08d71e5f2a5ddfb5309756181681de4f5a1822d80"),
    ]
    private let directory: URL
    public init(directory: URL = JuliaPaths.modelDirectory) { self.directory = directory }

    public func prepare(progress: @escaping @Sendable (ModelProgress) -> Void) async throws -> URL {
        try JuliaPaths.create(directory)
        for artifact in Self.artifacts {
            try Task.checkCancellation()
            let file = directory.appendingPathComponent(artifact.name)
            progress(.init("Verifying \(artifact.name)…"))
            if FileManager.default.fileExists(atPath: file.path) {
                if try await digest(file) == artifact.sha256 { continue }
                try FileManager.default.removeItem(at: file)
            }
            progress(.init("Downloading \(artifact.name)", fraction: 0))
            let delegate = DownloadProgress { written, expected in
                progress(.init("Downloading \(artifact.name)", fraction: Double(written) / Double(max(expected, artifact.size))))
            }
            let url = URL(string: "https://huggingface.co/\(Self.modelName)/resolve/\(Self.revision)/\(artifact.name)")!
            let request = URLRequest(url: url, timeoutInterval: 3600)
            let (temporary, response) = try await URLSession.shared.download(for: request, delegate: delegate)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
                throw JuliaError("Hugging Face download failed. Check your connection and retry.")
            }
            let attrs = try FileManager.default.attributesOfItem(atPath: temporary.path)
            guard (attrs[.size] as? NSNumber)?.int64Value == artifact.size,
                  try await digest(temporary) == artifact.sha256 else {
                throw JuliaError("Model checksum failed for \(artifact.name). Retry to download a verified copy.")
            }
            try Task.checkCancellation()
            let staging = directory.appendingPathComponent(artifact.name + ".partial")
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.copyItem(at: temporary, to: staging)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
            try FileManager.default.moveItem(at: staging, to: file)
        }
        let receipt = ["model": Self.modelName, "revision": Self.revision]
        try JSONEncoder().encode(receipt).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        return directory
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
