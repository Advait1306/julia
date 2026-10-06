import Combine
import CoreServices
import Foundation

nonisolated struct InstalledApp: Identifiable, Encodable, Equatable, Sendable {
    // Use the exact path so different installations of the same app remain distinct.
    let id: String
    let name: String
    let bundleIdentifier: String?

    init?(url: URL) {
        guard url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url.resolvingSymlinksInPath()),
              let type = bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String,
              ["APPL", "FNDR"].contains(type),
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        id = url.standardizedFileURL.path
        bundleIdentifier = bundle.bundleIdentifier
        name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
    }
}

@MainActor
final class Apps: ObservableObject {
    @Published private(set) var installed: [InstalledApp] = []

    private let roots: [URL]
    private var stream: FSEventStreamRef?

    init(roots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)
    ]) {
        self.roots = roots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        startObserving()
        refresh()
    }

    private func refresh() {
        var apps: [String: InstalledApp] = [:]
        for root in roots {
            if root.pathExtension.lowercased() == "app" {
                if let app = InstalledApp(url: root) { apps[app.id] = app }
                continue
            }
            guard let files = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil,
                // Safari's /Applications symlink is hidden by Finder, but is launchable.
                options: [.skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in files {
                if url.lastPathComponent.hasPrefix(".") {
                    files.skipDescendants()
                    continue
                }
                if let app = InstalledApp(url: url) { apps[app.id] = app }
            }
        }
        installed = apps.values.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    func openApp(id: String) async throws {
        guard installed.contains(where: { $0.id == id }),
              InstalledApp(url: URL(fileURLWithPath: id)) != nil else {
            throw Failure.unavailableApp
        }
        // Pass arguments directly, without a shell. open also activates an existing instance.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", id]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: Failure.openFailed(process.terminationStatus))
                }
            }
            do { try process.run() }
            catch { continuation.resume(throwing: error) }
        }
    }

    private func startObserving() {
        // FSEvents watches subfolders too. Include parents so a missing ~/Applications
        // folder can be created later, or a watched root can be replaced.
        let paths = Set(roots.flatMap { [$0.path, $0.deletingLastPathComponent().path] })
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        guard let stream = FSEventStreamCreate(
            nil, { _, info, count, eventPaths, _, _ in
                guard let info else { return }
                let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
                let changedPaths = (0..<count).map { String(cString: paths[$0]) }
                MainActor.assumeIsolated {
                    let apps = Unmanaged<Apps>.fromOpaque(info).takeUnretainedValue()
                    // Watching parents also produces unrelated events; ignore those.
                    if apps.roots.contains(where: { root in
                        changedPaths.contains { path in
                            path == root.path || path.hasPrefix(root.path + "/")
                                || root.path.hasPrefix(path + "/")
                        }
                    }) {
                        apps.refresh()
                    }
                }
            }, &context, Array(paths) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
        ) else {
            print("Apps: Couldn't watch installed applications.")
            return
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            print("Apps: Couldn't start watching installed applications.")
            return
        }
        self.stream = stream
    }

    isolated deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    nonisolated enum Failure: LocalizedError {
        case unavailableApp, openFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .unavailableApp: "The selected app is no longer installed."
            case .openFailed(let status): "Couldn't open the app (open exited with status \(status))."
            }
        }
    }
}
