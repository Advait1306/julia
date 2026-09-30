import Alamofire
import Foundation

private nonisolated final class JevMock: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var captured: [String: Any]?
    nonisolated(unsafe) static var choice = "work"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.captured = try! JSONSerialization.jsonObject(with: body) as? [String: Any]
        let answers: [String: Any] = ["wifi": ["choice": "on"], "bluetooth": ["choice": "off"],
            "audioMute": ["choice": "unchanged"], "audioDevice": ["choice": "unchanged"],
            "playback": ["choice": "unchanged"], "focusMode": ["choice": Self.choice]]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: ["answers": answers]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct JevFocusTests {
    @MainActor static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JevMock.self]
        let jev = Jev(apiKey: "test-key", session: Session(configuration: configuration))
        let state = SettingsState(wifi: true, bluetooth: false,
                                  audio: .init(devices: [], selectedDeviceID: nil, isMuted: nil),
                                  focus: .init(modes: [FocusMode(id: "work", name: "Work")],
                                               isActive: false, currentModeID: nil))
        let response = try await jev.evaluate(prompt: "Enable Work Focus", state: state)
        guard case .mode("work") = response.focus else { preconditionFailure("Expected Work choice") }
        let questions = JevMock.captured!["questions"] as! [String: [String: Any]]
        let criteria = questions["focusMode"]!["criteria"] as! [String: String]
        precondition(criteria == ["work": "Work", "off": "No Focus", "unchanged": "Keep the current Focus"])
        let settings = (JevMock.captured!["state"] as! [String: Any])["settings"] as! [String: Any]
        let focus = settings["focus"] as! [String: Any]
        precondition(focus["isActive"] as! Bool == false && focus["currentModeID"] == nil)
        JevMock.choice = "invented"
        do {
            _ = try await jev.evaluate(prompt: "Enable invented Focus", state: state)
            preconditionFailure("Unavailable mode must be rejected")
        } catch is DecodingError {}
        JevMock.choice = "off"
        guard case .off = try await jev.evaluate(prompt: "Disable Focus", state: state).focus else {
            preconditionFailure("Expected Off choice")
        }
        print("Jev mock checks passed: encoded Focus state, dynamic choices, selected mode, Off and rejection of unavailable modes.")
    }
}
