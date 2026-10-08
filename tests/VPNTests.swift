import Alamofire
import Foundation
import SystemConfiguration

// Compile with the production sources; intercept HTTP so no API key or network is needed.
nonisolated final class EvaluationFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var reply = Data()
    private var body = Data()

    func prepare(_ answers: [String: String]) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "answers": answers.mapValues { ["choice": $0] }
        ])
        lock.withLock { reply = data; body = Data() }
    }

    func respond(to request: URLRequest) -> Data {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return lock.withLock { body = data; return reply }
    }

    func requestJSON() throws -> [String: Any] {
        let data = lock.withLock { body }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}

nonisolated final class MockEvaluation: URLProtocol, @unchecked Sendable {
    static let fixture = EvaluationFixture()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = Self.fixture.respond(to: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct VPNTests {
    @MainActor
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockEvaluation.self]
        let jev = Jev(apiKey: "fixture", session: Session(configuration: configuration))
        var state = SettingsState(
            wifi: true, bluetooth: true, darkMode: false,
            audio: .init(devices: [], selectedDeviceID: nil, isMuted: nil),
            focus: .init(modes: [], isActive: false, currentModeID: nil), apps: [],
            vpns: [
                .init(id: "tailscale", name: "Tailscale", state: .connected),
                .init(id: "proton", name: "ProtonVPN", state: .connecting),
                .init(id: "work", name: "Work VPN", state: .disconnected),
                .init(id: "other", name: "Other VPN", state: .disconnecting),
                .init(id: "unknown", name: "Unknown VPN", state: .unknown)
            ]
        )
        let base = ["wifi": "on", "bluetooth": "on", "darkMode": "off",
                    "audioMute": "unchanged", "audioDevice": "unchanged", "playback": "unchanged",
                    "focusMode": "unchanged", "openApp": "unchanged"]
        var answers = base
        for vpn in state.vpns { answers["vpn_\(vpn.id)"] = "unchanged" }
        answers["vpn_proton"] = "disable"
        answers["vpn_work"] = "disable"
        answers["vpn_other"] = "disable"
        try MockEvaluation.fixture.prepare(answers)
        let except = try await jev.evaluate(prompt: "disable all VPNs except tailscale", state: state)
        precondition(except.vpnChanges.map(\.id) == ["proton", "work", "other"])
        precondition(except.vpnChanges.allSatisfy { !$0.isConnected })
        let request = try MockEvaluation.fixture.requestJSON()
        let settings = (request["state"] as! [String: Any])["settings"] as! [String: Any]
        let vpns = settings["vpns"] as! [[String: String]]
        precondition(vpns.map { $0["state"]! } == ["connected", "connecting", "disconnected", "disconnecting", "unknown"])
        precondition(vpns.map { $0["name"]! } == state.vpns.map(\.name))
        let questions = request["questions"] as! [String: [String: Any]]
        precondition(questions.keys.filter { $0.hasPrefix("vpn_") }.count == state.vpns.count)
        for vpn in state.vpns {
            let question = questions["vpn_\(vpn.id)"]!
            precondition(Set((question["criteria"] as! [String: String]).keys) == ["unchanged", "enable", "disable"])
        }
        print("PASS: VPN names and every connection state are sent; bulk disables preserve Tailscale")

        answers["vpn_tailscale"] = "enable"
        answers["vpn_work"] = "enable"
        try MockEvaluation.fixture.prepare(answers)
        let mixed = try await jev.evaluate(prompt: "connect Tailscale and Work, disconnect Proton and Other", state: state)
        precondition(mixed.vpnChanges.filter(\.isConnected).map(\.id) == ["tailscale", "work"])
        precondition(mixed.vpnChanges.filter { !$0.isConnected }.map(\.id) == ["proton", "other"])
        print("PASS: one response can enable and disable multiple VPNs")

        for vpn in state.vpns { answers["vpn_\(vpn.id)"] = "unchanged" }
        try MockEvaluation.fixture.prepare(answers)
        let unrelated = try await jev.evaluate(prompt: "turn on wifi", state: state)
        precondition(unrelated.vpnChanges.isEmpty)
        print("PASS: unchanged VPNs produce no actions")

        for scenario in ["missing", "unavailable", "invalid"] {
            var malformed = answers
            switch scenario {
            case "missing": malformed.removeValue(forKey: "vpn_work")
            case "unavailable": malformed["vpn_invented"] = "enable"
            default: malformed["vpn_work"] = "toggle"
            }
            try MockEvaluation.fixture.prepare(malformed)
            do {
                _ = try await jev.evaluate(prompt: "connect VPNs", state: state)
                fatalError("Accepted \(scenario) VPN answer")
            } catch is DecodingError {
            } catch AFError.responseSerializationFailed(reason: .decodingFailed(error: _)) {
            }
        }
        print("PASS: missing, unavailable, and invalid VPN answers are rejected")

        state.vpns = []
        try MockEvaluation.fixture.prepare(base)
        let empty = try await jev.evaluate(prompt: "disable all VPNs", state: state)
        precondition(empty.vpnChanges.isEmpty)
        let emptyQuestions = try MockEvaluation.fixture.requestJSON()["questions"] as! [String: Any]
        precondition(!emptyQuestions.keys.contains { $0.hasPrefix("vpn_") })
        print("PASS: no configured VPNs requires no VPN answers")

        precondition(VPNConnection.State(.invalid) == .unknown)
        let manager = VPN()
        let configured = try manager.readConnections()
        try await manager.apply([])
        // A bad ID later in the batch must reject the entire batch before any mutation.
        if let first = configured.first {
            do {
                try await manager.apply([
                    .init(id: first.id, isConnected: first.state != .connected),
                    .init(id: "unavailable-test-service", isConnected: true)
                ])
                fatalError("Accepted an unavailable VPN in a batch")
            } catch is VPN.Failure {}
            do {
                try await manager.apply([
                    .init(id: first.id, isConnected: true), .init(id: first.id, isConnected: false)
                ])
                fatalError("Accepted a duplicated VPN in a batch")
            } catch is VPN.Failure {}
        }
        print("PASS: native discovery (\(configured.count) VPNs); invalid batches rejected before changes")
    }
}
