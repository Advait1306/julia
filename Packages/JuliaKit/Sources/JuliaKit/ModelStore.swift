import Foundation
import CryptoKit

public struct ModelProgress: Sendable {
    public let message: String
    public let fraction: Double?
    public init(_ message: String, fraction: Double? = nil) { self.message = message; self.fraction = fraction }
}

public actor ModelStore {
    public static let modelName = "qwen3.5:0.8b"
    private struct Layer: Codable { let mediaType: String; let digest: String; let size: Int64 }
    private struct Manifest: Codable { let config: Layer; let layers: [Layer] }
    private let directory: URL
    public init(directory: URL = JuliaPaths.modelDirectory) { self.directory = directory }

    public func prepare(progress: @escaping @Sendable (ModelProgress) -> Void) async throws -> URL {
        try JuliaPaths.create(directory)
        let file = directory.appendingPathComponent("model.gguf")
        let receipt = directory.appendingPathComponent("manifest.json")
        var manifest: Manifest
        if let data = try? Data(contentsOf: receipt), let saved = try? JSONDecoder().decode(Manifest.self, from: data) {
            manifest = saved
        } else {
            progress(.init("Finding Qwen 3.5 0.8B…"))
            let data = try await fetch("manifests/0.8b")
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
            // Save only after validating the layout below.
        }
        let models = manifest.layers.filter { $0.mediaType == "application/vnd.ollama.image.model" }
        guard models.count == 1, let model = models.first, model.size > 0, model.size < 2_000_000_000 else {
            throw JuliaError("This Qwen release has an unsupported model layout.")
        }
        try checkDigest(model.digest)
        progress(.init("Verifying model…"))
        if FileManager.default.fileExists(atPath: file.path) {
            if try await digest(file) == String(model.digest.dropFirst(7)) {
                try await saveMetadata(manifest, to: receipt)
                return file
            }
            try FileManager.default.removeItem(at: file)
        }
        progress(.init("Downloading Qwen 3.5 0.8B", fraction: 0))
        let delegate = DownloadProgress { written, expected in
            progress(.init("Downloading Qwen 3.5 0.8B", fraction: Double(written) / Double(max(expected, model.size))))
        }
        let request = URLRequest(url: try registryURL("blobs/\(model.digest)"), timeoutInterval: 3600)
        let (temporary, response) = try await URLSession.shared.download(for: request, delegate: delegate)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try validate(response)
        let attrs = try FileManager.default.attributesOfItem(atPath: temporary.path)
        guard (attrs[.size] as? NSNumber)?.int64Value == model.size else { throw JuliaError("The model download is incomplete. Retry to download again.") }
        progress(.init("Verifying model…"))
        guard try await digest(temporary) == String(model.digest.dropFirst(7)) else { throw JuliaError("Model checksum failed. Retry to download a verified copy.") }
        let h = try FileHandle(forReadingFrom: temporary); let magic = try h.read(upToCount: 4); try h.close()
        guard magic == Data("GGUF".utf8) else { throw JuliaError("The downloaded model is not GGUF.") }
        try Task.checkCancellation()
        // Copy via a same-directory staging file, then rename atomically.
        let staging = directory.appendingPathComponent("model.gguf.partial")
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.copyItem(at: temporary, to: staging)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
        try FileManager.default.moveItem(at: staging, to: file)
        try await saveMetadata(manifest, to: receipt)
        return file
    }
    private func saveMetadata(_ manifest: Manifest, to receipt: URL) async throws {
        // Offline launches use the verified receipt and never contact the registry.
        if FileManager.default.fileExists(atPath: receipt.path) { return }
        for layer in [manifest.config] + manifest.layers.filter({ $0.mediaType != "application/vnd.ollama.image.model" }) {
            try checkDigest(layer.digest)
            guard layer.size < 1_000_000 else { throw JuliaError("Unexpected model metadata size.") }
            let bytes = try await fetch("blobs/\(layer.digest)")
            guard SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == String(layer.digest.dropFirst(7)) else {
                throw JuliaError("Model metadata checksum failed.")
            }
            let name: String
            switch layer.mediaType {
            case "application/vnd.ollama.image.license": name = "LICENSE.txt"
            case "application/vnd.ollama.image.params": name = "parameters.json"
            case "application/vnd.ollama.image.template": name = "ollama-template.txt"
            default: name = "config.json"
            }
            try bytes.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
        try JSONEncoder().encode(manifest).write(to: receipt, options: .atomic)
    }
    private func fetch(_ path: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: registryURL(path))
        try validate(response); return data
    }
    private func registryURL(_ path: String) throws -> URL {
        guard let url = URL(string: "https://registry.ollama.ai/v2/library/qwen3.5/\(path)") else { throw JuliaError("Invalid registry URL.") }; return url
    }
    private func validate(_ response: URLResponse) throws {
        guard let h = response as? HTTPURLResponse, (200...299).contains(h.statusCode) else { throw JuliaError("Ollama registry download failed. Check your connection and retry.") }
    }
    private func checkDigest(_ value: String) throws {
        guard value.range(of: "^sha256:[0-9a-f]{64}$", options: .regularExpression) != nil else { throw JuliaError("Invalid registry digest.") }
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
