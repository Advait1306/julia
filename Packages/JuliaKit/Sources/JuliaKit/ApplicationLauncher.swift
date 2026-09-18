import AppKit
import Foundation

/// Launch Services opens or reactivates the app; no Apple Events or UI scripting.
@MainActor enum ApplicationLauncher {
    static func open(_ application: String) async throws -> JSONValue {
        let url = try resolve(application)
        try Task.checkCancellation()
        let workspace = NSWorkspace.shared
        let wasRunning = workspace.runningApplications.contains { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        let app = try await workspace.openApplication(at: url, configuration: configuration)
        return .object([
            "status": .string("opened"),
            "name": .string(app.localizedName ?? url.deletingPathExtension().lastPathComponent),
            "bundleID": .string(app.bundleIdentifier ?? Bundle(url: url)?.bundleIdentifier ?? ""),
            "path": .string(url.path),
            "processID": .number(Double(app.processIdentifier)),
            "wasRunning": .bool(wasRunning)
        ])
    }

    static func resolve(_ application: String) throws -> URL {
        let query = application.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 255,
              query.rangeOfCharacter(from: .controlCharacters) == nil,
              !query.contains("/"), !query.contains("\\"), !query.contains(":") else {
            throw JuliaError("Provide an application name such as Calendar or a bundle ID such as com.apple.iCal.")
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: query) { return url }

        var candidates = NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
        let roots = ["/Applications", "/System/Applications", "/System/Library/CoreServices/Applications",
                     NSHomeDirectory() + "/Applications"]
        for root in roots {
            guard let entries = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root, isDirectory: true),
                includingPropertiesForKeys: [.isDirectoryKey, .localizedNameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in entries where url.pathExtension.lowercased() == "app" {
                candidates.append(url)
                entries.skipDescendants()
            }
        }
        return try match(query, candidates: candidates)
    }

    /// Exact, case-insensitive names only. Ambiguous names must be resolved with a bundle ID.
    static func match(_ query: String, candidates: [URL]) throws -> URL {
        func normalized(_ value: String) -> String {
            let name = value.lowercased()
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
        let matches = Set(candidates.map { $0.resolvingSymlinksInPath().standardizedFileURL }).filter { url in
            guard let bundle = Bundle(url: url), bundle.bundleIdentifier != nil else { return false }
            let names = [url.lastPathComponent,
                         (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName,
                         bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                         bundle.object(forInfoDictionaryKey: "CFBundleName") as? String].compactMap { $0 }
            return names.contains { normalized($0) == normalized(query) }
        }.sorted { $0.path < $1.path }
        guard !matches.isEmpty else {
            throw JuliaError("Application '\(query)' was not found. Use its installed name or bundle ID.")
        }
        guard matches.count == 1 else {
            let options = matches.map { "\(Bundle(url: $0)?.bundleIdentifier ?? $0.lastPathComponent) (\($0.path))" }
            throw JuliaError("More than one application matches '\(query)'. Specify its bundle ID: \(options.joined(separator: ", ")).")
        }
        return matches[0]
    }
}
