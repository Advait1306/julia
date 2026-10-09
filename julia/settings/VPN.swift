// NOTE: VPN interacts with older macOS C APIs, so some of this code may not look idiomatic in Swift.

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
    var state: State
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
            if !SCPreferencesSetCallback(preferences, { _, _, info in
                guard let info else { return }
                MainActor.assumeIsolated {
                    Unmanaged<Observer>.fromOpaque(info).takeUnretainedValue().vpn?.refresh()
                }
            }, &context) || !SCPreferencesSetDispatchQueue(preferences, .main) {
                print("VPN: Couldn't observe configuration changes: \(String(cString: SCErrorString(SCError())))")
            }
        } else {
            print("VPN: Couldn't open network preferences: \(String(cString: SCErrorString(SCError())))")
        }
        refresh()
    }

    func apply(_ changes: [VPNChange]) {
        for change in changes {
            guard let connection = handles[change.id] else {
                print("VPN: \(change.id) is no longer available.")
                continue
            }
            if change.isConnected {
                if !SCNetworkConnectionStart(connection, nil, true) {
                    print("VPN: Couldn't connect \(change.id): \(String(cString: SCErrorString(SCError())))")
                }
            } else if !SCNetworkConnectionStop(connection, true) {
                print("VPN: Couldn't disconnect \(change.id): \(String(cString: SCErrorString(SCError())))")
            }
        }
    }

    private func refresh() {
        guard let preferences else { return }
        SCPreferencesSynchronize(preferences)
        guard let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] else {
            print("VPN: Couldn't read configured VPNs: \(String(cString: SCErrorString(SCError())))")
            return
        }
        stopObservingConnections()
        connections = services.compactMap { service in
            guard isVPN(service), let id = SCNetworkServiceGetServiceID(service) as String? else { return nil }

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
                    print("VPN: Couldn't observe connection changes for \(id): \(String(cString: SCErrorString(SCError())))")
                }
            }
            return VPNConnection(
                id: id, name: SCNetworkServiceGetName(service) as String? ?? id,
                state: connection.map { .init(SCNetworkConnectionGetStatus($0)) } ?? .unknown
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func updateState(_ connection: SCNetworkConnection, status: SCNetworkConnectionStatus) {
        guard let id = SCNetworkConnectionCopyServiceID(connection) as String?,
              handles[id] === connection,
              let index = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[index].state = .init(status)
    }

    private func stopObservingConnections() {
        for connection in handles.values {
            SCNetworkConnectionSetDispatchQueue(connection, nil)
        }
        handles.removeAll()
    }

    private func isVPN(_ service: SCNetworkService) -> Bool {
        guard let interface = SCNetworkServiceGetInterface(service),
              let type = SCNetworkInterfaceGetInterfaceType(interface) as String? else { return false }
        switch type {
        case "VPN", "IPSec": return true
        case "PPP":
            // PPP also includes modems; only include its VPN subtypes.
            guard let underlying = SCNetworkInterfaceGetInterface(interface),
                  let subtype = SCNetworkInterfaceGetInterfaceType(underlying) as String? else { return false }
            return subtype == "L2TP" || subtype == "PPTP"
        default: return false
        }
    }

    isolated deinit {
        stopObservingConnections()
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
}
