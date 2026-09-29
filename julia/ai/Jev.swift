//
//  Jev.swift
//  julia
//
//  Created by Advait on 9/28/26.
//

import Alamofire

nonisolated struct SettingsState: Encodable, Sendable {
    var wifi: Bool
    var bluetooth: Bool
}

final class Jev {
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func evaluate(prompt: String, state: SettingsState) async throws -> SettingsState {
        let parameters = EvaluationRequest(
            state: .init(prompt: prompt, settings: state),
            questions: [
                "wifi": Question(setting: "Wi-Fi", key: "wifi"),
                "bluetooth": Question(setting: "Bluetooth", key: "bluetooth")
            ]
        )

        let response = try await AF.request(
            "https://api.typesafe.ai/v1/systemone",
            method: .post,
            parameters: parameters,
            encoder: JSONParameterEncoder.default,
            headers: [.authorization(bearerToken: apiKey)]
        )
        .validate()
        .serializingDecodable(EvaluationResponse.self)
        .value

        return SettingsState(
            wifi: response.answers.wifi.choice == .on,
            bluetooth: response.answers.bluetooth.choice == .on
        )
    }
}

private nonisolated struct EvaluationRequest: Encodable, Sendable {
    struct State: Encodable, Sendable {
        let prompt: String
        let settings: SettingsState
    }

    let state: State
    let model = "jev-latest"
    let questions: [String: Question]
}

private nonisolated struct Question: Encodable, Sendable {
    let type = "choice"
    let instructions: String
    let criteria = ["on": "Enabled", "off": "Disabled"]

    init(setting: String, key: String) {
        instructions = """
            Should \(setting) be on or off after following the user's `prompt`?
            Its current state is `settings.\(key)`: true means on, false means off.
            If the prompt does not request a change to \(setting), preserve its current state.
            If asked to toggle \(setting), invert its current state.
            """
    }
}

private nonisolated struct EvaluationResponse: Decodable, Sendable {
    enum PowerState: String, Decodable, Sendable {
        case on, off
    }

    struct Answer: Decodable, Sendable {
        let choice: PowerState
    }

    struct Answers: Decodable, Sendable {
        let wifi: Answer
        let bluetooth: Answer
    }

    let answers: Answers
}
