import Combine
import Foundation
import SystemConfiguration

nonisolated struct VPNConnection: Identifiable, Encodable, Sendable {
    enum State: String, Encodable, Sendable {
        case disconnected, connecting, connected, disconnecting, unknown

        init(_ status: SCNetworkConnectionStatus) {
            switch status {
            case .disconnected: self = .disconnected
            case .connecting: self = .connecting
            case .connected: self = .connected
            case .disconnecting: self = .disconnecting
            default: self = .unknown
            }
        }
    }

    let id: String
    let name: String
    let state: State
}

nonisolated struct VPNChange: Sendable {
    let id: String
    let isConnected: Bool
}

@MainActor
final class VPN: ObservableObject {
    @Published private(set) var connections: [VPNConnection] = []

    private let preferences = SCPreferencesCreate(nil, "Julia" as CFString, nil)
    private var handles: [String: SCNetworkConnection] = [:]
    private lazy var observer = Observer(self)

    init() {
        if let preferences {
            var context = SCPreferencesContext(
                version: 0, info: Unmanaged.passUnretained(observer).toOpaque(),
                retain: { UnsafeRawPointer(Unmanaged<Observer>.fromOpaque($0).retain().toOpaque()) },
                release: { Unmanaged<Observer>.fromOpaque($0).release() }, copyDescription: nil
            )
            let observing = SCPreferencesSetCallback(preferences, { _, _, info in
                guard let info else { return }
                MainActor.assumeIsolated {
                    Unmanaged<Observer>.fromOpaque(info).takeUnretainedValue().vpn?.refresh()
                }
            }, &context) && SCPreferencesSetDispatchQueue(preferences, .main)
            if !observing { print("VPN: Couldn't observe configuration changes.") }
        }
        refresh()
    }

    func apply(_ changes: [VPNChange]) throws {
        guard !changes.isEmpty else { return }

        // Validate the entire batch before changing any connection.
        var seen = Set<String>()
        let targets = try changes.map { change in
            guard seen.insert(change.id).inserted,
                  let vpn = connections.first(where: { $0.id == change.id }),
                  let connection = handles[change.id] else {
                throw Failure(message: "A selected VPN is unavailable or repeated. Try again.")
            }
            return (change: change, vpn: vpn, connection: connection)
        }

        var failures: [String] = []
        // A failure for one VPN must not skip the others.
        // Disconnect first so a requested replacement can connect without competing tunnels.
        for target in targets.sorted(by: { !$0.change.isConnected && $1.change.isConnected }) {
            let status = target.vpn.state
            let desired: VPNConnection.State = target.change.isConnected ? .connected : .disconnected
            if status == desired { continue }
            let accepted: Bool
            if target.change.isConnected {
                // Linger keeps the connection alive when this reference is released.
                accepted = status == .connecting || SCNetworkConnectionStart(target.connection, nil, true)
            } else {
                accepted = status == .disconnecting || SCNetworkConnectionStop(target.connection, true)
            }
            if !accepted {
                let reason = String(cString: SCErrorString(SCError()))
                failures.append("\(target.vpn.name): \(reason)")
            }
        }

        if !failures.isEmpty {
            throw Failure(message: "Couldn't change VPN connections. " + failures.joined(separator: "; "))
        }
    }

    private func refresh() {
        do {
            let configured = try services()
            stopObservingConnections()
            connections = try configured.map { service in
                guard let id = SCNetworkServiceGetServiceID(service) as String? else {
                    throw Failure(message: "Couldn't read a VPN service ID.")
                }

                var context = SCNetworkConnectionContext(
                    version: 0, info: Unmanaged.passUnretained(observer).toOpaque(),
                    retain: { UnsafeRawPointer(Unmanaged<Observer>.fromOpaque($0).retain().toOpaque()) },
                    release: { Unmanaged<Observer>.fromOpaque($0).release() }, copyDescription: nil
                )
                let connection = SCNetworkConnectionCreateWithServiceID(nil, id as CFString, { connection, status, info in
                    guard let info else { return }
                    MainActor.assumeIsolated {
                        Unmanaged<Observer>.fromOpaque(info).takeUnretainedValue().vpn?
                            .updateState(connection, status: status)
                    }
                }, &context)
                if let connection {
                    handles[id] = connection
                    if !SCNetworkConnectionSetDispatchQueue(connection, .main) {
                        print("VPN: Couldn't observe connection changes for \(id).")
                    }
                }
                return VPNConnection(
                    id: id, name: SCNetworkServiceGetName(service) as String? ?? id,
                    state: connection.map { .init(SCNetworkConnectionGetStatus($0)) } ?? .unknown
                )
            }.sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
        } catch {
            stopObservingConnections()
            connections = []
            print("VPN: \(error.localizedDescription)")
        }
    }

    private func updateState(_ connection: SCNetworkConnection, status: SCNetworkConnectionStatus) {
        guard let id = SCNetworkConnectionCopyServiceID(connection) as String?,
              handles[id] === connection,
              let index = connections.firstIndex(where: { $0.id == id }) else { return }
        let vpn = connections[index]
        connections[index] = VPNConnection(id: id, name: vpn.name, state: .init(status))
    }

    private func stopObservingConnections() {
        for connection in handles.values {
            SCNetworkConnectionSetDispatchQueue(connection, nil)
        }
        handles.removeAll()
    }

    private func services() throws -> [SCNetworkService] {
        guard let preferences else { throw Failure(message: "Couldn't read configured VPNs.") }
        // Discard the session's old snapshot after macOS reports a configuration change.
        SCPreferencesSynchronize(preferences)
        guard let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] else {
            throw Failure(message: "Couldn't read configured VPNs.")
        }

        return services.filter { service in
            guard let interface = SCNetworkServiceGetInterface(service),
                  let type = SCNetworkInterfaceGetInterfaceType(interface) as String? else { return false }

            if type == "VPN" || type == kSCNetworkInterfaceTypeIPSec as String { return true }

            // PPP also includes dial-up services; only its VPN subtypes belong here.
            guard type == kSCNetworkInterfaceTypePPP as String,
                  let underlying = SCNetworkInterfaceGetInterface(interface),
                  let subtype = SCNetworkInterfaceGetInterfaceType(underlying) as String? else { return false }

            return subtype == kSCNetworkInterfaceTypeL2TP as String || subtype == "PPTP"
        }
    }

    isolated deinit {
        for connection in handles.values {
            SCNetworkConnectionSetDispatchQueue(connection, nil)
        }
        if let preferences {
            SCPreferencesSetDispatchQueue(preferences, nil)
            SCPreferencesSetCallback(preferences, nil, nil)
        }
    }

    // Callback contexts retain this weak owner, so queued notifications are safe after teardown.
    private final class Observer {
        weak var vpn: VPN?
        init(_ vpn: VPN) { self.vpn = vpn }
    }

    nonisolated struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
