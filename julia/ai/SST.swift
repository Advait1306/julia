import Combine
import FluidAudio
import Foundation
import AVFoundation

@MainActor
protocol SpeechTranscribing: AnyObject {
    var isReady: Bool { get }
    func start() async throws
    func finish() async throws -> String
    func cancel() async
}

@MainActor
final class SST: ObservableObject, SpeechTranscribing {
    enum ModelState: Equatable {
        case checking
        case notDownloaded
        case downloading(Double)
        case preparing
        case ready
        case failed(String)
    }

    @Published private(set) var modelState: ModelState = .checking
    @Published private(set) var transcript = ""
    @Published private(set) var microphoneEnabled = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    var onCaptureFailure: ((Error) -> Void)?

    private let worker = ModelWorker()
    private var checkedCache = false
    private var operationID: UUID?
    private var sessionID: UUID?
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var pipe: CapturePipe?
    private var consumer: Task<String, Error>?
    private var captureObserver: NSObjectProtocol?
    private var captureWatchdog: Task<Void, Never>?

    var isReady: Bool { modelState == .ready && microphoneEnabled }

    func refreshMicrophonePermission() {
        microphoneEnabled = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func enableMicrophone() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        refreshMicrophonePermission()
    }

    func start() async throws {
        refreshMicrophonePermission()
        guard isReady else { throw SpeechError.notReady }
        guard sessionID == nil else { throw SpeechError.busy }
        let id = UUID()
        sessionID = id
        transcript = ""

        do {
            try await worker.reset()
            try Task.checkCancellation()
            guard sessionID == id else { throw CancellationError() }

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw SpeechError.noMicrophone
            }
            let (stream, continuation) = AsyncThrowingStream<AudioChunk, Error>.makeStream(
                bufferingPolicy: .bufferingOldest(64)
            )
            let pipe = CapturePipe(continuation: continuation)
            self.engine = engine
            self.pipe = pipe
            try input.installAudioTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
                pipe.push(buffer)
            }
            tapInstalled = true
            consumer = Task { [worker, weak self] in
                for try await chunk in stream {
                    try Task.checkCancellation()
                    let partial = try await worker.process(chunk)
                    if self?.sessionID == id { self?.transcript = partial }
                }
                try Task.checkCancellation()
                return try await worker.finish()
            }
            // Report consumer failures immediately, even while the key is held.
            if let consumer {
                Task { [weak self] in
                    do { _ = try await consumer.value }
                    catch {
                        guard self?.sessionID == id, self?.engine != nil else { return }
                        self?.onCaptureFailure?(error)
                    }
                }
            }
            captureObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard self?.sessionID == id, self?.engine != nil else { return }
                    self?.onCaptureFailure?(SpeechError.deviceChanged)
                }
            }
            engine.prepare()
            try engine.start()
            captureWatchdog = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard self?.sessionID == id, !pipe.receivedAudio else { return }
                self?.onCaptureFailure?(SpeechError.noAudio)
            }
        } catch {
            await cancel()
            throw error
        }
    }

    func finish() async throws -> String {
        guard let id = sessionID, let consumer else { throw SpeechError.notReady }
        stopCapture()
        // Finishing the stream drains every accepted buffer before the consumer
        // invokes FluidAudio.finish(), including its held-back right context.
        pipe?.finish()
        defer {
            if sessionID == id {
                sessionID = nil
                self.consumer = nil
                pipe = nil
            }
        }
        let final = try await consumer.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sessionID == id else { throw CancellationError() }
        transcript = final
        return final
    }

    func cancel() async {
        sessionID = nil
        stopCapture()
        pipe?.finish()
        let task = consumer
        consumer = nil
        pipe = nil
        task?.cancel()
        _ = try? await task?.value
        try? await worker.reset()
    }

    private func stopCapture() {
        captureWatchdog?.cancel()
        captureWatchdog = nil
        if let captureObserver { NotificationCenter.default.removeObserver(captureObserver) }
        captureObserver = nil
        if let engine {
            engine.stop()
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        }
        tapInstalled = false
        engine = nil
    }

    var isPreparingModel: Bool {
        switch modelState {
        case .checking, .downloading, .preparing: true
        default: false
        }
    }

    /// Restores a previously validated model without accessing the network.
    func restoreModelIfAvailable() async {
        guard !checkedCache else { return }
        checkedCache = true
        do {
            let restored = try await worker.restoreIfAvailable()
            modelState = restored ? .ready : .notDownloaded
        } catch {
            modelState = .failed(error.localizedDescription)
        }
    }

    func downloadModel() async {
        guard !isPreparingModel, modelState != .ready else { return }
        let id = UUID()
        operationID = id
        modelState = .downloading(0)

        do {
            try await worker.downloadAndLoad { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.updateProgress(progress, operationID: id)
                }
            }
            operationID = nil
            modelState = .ready
        } catch {
            operationID = nil
            modelState = .failed(error.localizedDescription)
        }
    }

    private func updateProgress(_ progress: DownloadProgress, operationID id: UUID) {
        guard operationID == id else { return }
        switch progress.phase {
        case .listing:
            modelState = .downloading(0)
        case .downloading:
            let fraction = min(1, max(0, progress.fractionCompleted))
            modelState = fraction >= 1 ? .preparing : .downloading(fraction)
        case .compiling:
            modelState = .preparing
        }
    }

    /// Keeps Core ML loading and inference off the UI actor. The prepared
    /// streaming manager is retained here for subsequent speech sessions.
    private actor ModelWorker {
        private static let revision = "d32e972dd4315f1dc3f6be28fb2aab0ab3e80358"
        private static let cacheIdentity = "\(revision)/70_7_1/int8"
        private let manager = StreamingUnifiedAsrManager(
            config: UnifiedConfig(leftFrames: 70, chunkFrames: 7, rightFrames: 1)
        )

        func reset() async throws { try await manager.reset() }

        func process(_ chunk: AudioChunk) async throws -> String {
            try await manager.appendAudio(chunk.buffer)
            try await manager.processBufferedAudio()
            return await manager.getPartialTranscript()
        }

        func finish() async throws -> String { try await manager.finish() }

        private func modelsRoot() throws -> URL {
            try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Julia/Models", isDirectory: true)
        }

        private func modelDirectory(in root: URL) -> URL {
            root.appendingPathComponent(Repo.parakeetUnified.folderName, isDirectory: true)
        }

        private func readyMarker(in directory: URL) -> URL {
            directory.appendingPathComponent("julia-ready.txt")
        }

        func restoreIfAvailable() async throws -> Bool {
            let directory = modelDirectory(in: try modelsRoot())
            guard let identity = try? String(contentsOf: readyMarker(in: directory), encoding: .utf8),
                  identity == Self.cacheIdentity else { return false }

            try await manager.loadModels(from: directory)
            return true
        }

        func downloadAndLoad(progress: @escaping ProgressHandler) async throws {
            let root = try modelsRoot()
            // Pin weights as well as package code, so a mutable Hub branch
            // cannot change the assets used by an existing Julia build.
            ModelRegistry.revisionOverrides[Repo.parakeetUnified.remotePath] = Self.revision
            try await manager.loadModels(to: root, progressHandler: progress)
            try Task.checkCancellation()

            // Mark ready only after every model has loaded successfully.
            let marker = readyMarker(in: modelDirectory(in: root))
            try Data(Self.cacheIdentity.utf8).write(to: marker, options: .atomic)
        }
    }
}

nonisolated enum SpeechError: LocalizedError {
    case notReady, busy, noMicrophone, noAudio, audioOverflow, deviceChanged

    var errorDescription: String? {
        switch self {
        case .notReady: "Download the speech model and enable the microphone first."
        case .busy: "A speech session is already active."
        case .noMicrophone: "No microphone is available."
        case .noAudio: "The microphone did not supply audio. Try another input device."
        case .audioOverflow: "Audio processing fell behind. Please try a shorter command."
        case .deviceChanged: "The microphone changed during recording. Please try again."
        }
    }
}

/// Each buffer is copied from the tap and then read only by the single consumer.
nonisolated struct AudioChunk: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// Serializes tap delivery and finish so accepted buffers cannot arrive after
/// the stream's end. A bounded stream reports overflow instead of dropping speech.
nonisolated final class CapturePipe: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation
    private var accepting = true
    private var hasAudio = false

    init(continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation) {
        self.continuation = continuation
    }

    var receivedAudio: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasAudio
    }

    func push(_ source: AVReadOnlyAudioPCMBuffer) {
        enqueue(AVAudioPCMBuffer(copying: source))
    }

    func push(_ source: AVAudioPCMBuffer) {
        enqueue(AVAudioPCMBuffer(copying: source))
    }

    private func enqueue(_ copy: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard accepting, copy.frameLength > 0 else { return }
        hasAudio = true
        if case .dropped = continuation.yield(AudioChunk(buffer: copy)) {
            accepting = false
            continuation.finish(throwing: SpeechError.audioOverflow)
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        accepting = false
        continuation.finish()
    }
}
