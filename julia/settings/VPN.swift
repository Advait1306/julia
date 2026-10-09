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
final class VPN {
    func readConnections() throws -> [VPNConnection] {
        try services().map { service in
            guard let id = SCNetworkServiceGetServiceID(service) as String? else {
                throw Failure(message: "Couldn't read a VPN service ID.")
            }
            let connection = SCNetworkConnectionCreateWithServiceID(nil, id as CFString, nil, nil)
            return VPNConnection(
                id: id, name: SCNetworkServiceGetName(service) as String? ?? id,
                state: connection.map { .init(SCNetworkConnectionGetStatus($0)) } ?? .unknown
            )
        }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    func apply(_ changes: [VPNChange]) throws {
        guard !changes.isEmpty else { return }
        let available = try readConnections()
        // Validate the entire batch before changing any connection.
        var seen = Set<String>()
        let targets = try changes.map { change in
            guard seen.insert(change.id).inserted,
                  let vpn = available.first(where: { $0.id == change.id }),
                  let connection = SCNetworkConnectionCreateWithServiceID(nil, change.id as CFString, nil, nil) else {
                throw Failure(message: "A selected VPN is unavailable or repeated. Try again.")
            }
            return (change: change, vpn: vpn, connection: connection)
        }

        var failures: [String] = []
        // A failure for one VPN must not skip the others.
        // Disconnect first so a requested replacement can connect without competing tunnels.
        for target in targets.sorted(by: { !$0.change.isConnected && $1.change.isConnected }) {
            let status = SCNetworkConnectionGetStatus(target.connection)
            let desired: SCNetworkConnectionStatus = target.change.isConnected ? .connected : .disconnected
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

    private func services() throws -> [SCNetworkService] {
        guard let preferences = SCPreferencesCreate(nil, "Julia VPN" as CFString, nil),
              let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] else {
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

    nonisolated struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
