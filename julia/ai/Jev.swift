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
    var audio: AudioState

    struct AudioState: Encodable, Sendable {
        let devices: [AudioDevice]
        let selectedDeviceID: UInt32?
        let isMuted: Bool?
    }
}

nonisolated struct SettingsDecision: Sendable {
    enum MuteAction: String, Decodable, Sendable {
        case unchanged, mute, unmute
    }

    let wifi: Bool
    let bluetooth: Bool
    let audioMute: MuteAction
    let audioDeviceID: UInt32?
}

final class Jev {
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func evaluate(prompt: String, state: SettingsState) async throws -> SettingsDecision {
        var deviceChoices = ["unchanged": "Keep the current audio output"]
        for device in state.audio.devices {
            deviceChoices[String(device.id)] = device.name
        }

        let parameters = EvaluationRequest(
            state: .init(prompt: prompt, settings: state),
            questions: [
                "wifi": Question(setting: "Wi-Fi", key: "wifi"),
                "bluetooth": Question(setting: "Bluetooth", key: "bluetooth"),
                "audioMute": Question(
                    instructions: """
                        Should audio be muted or unmuted after following the user's `prompt`?
                        `settings.audio.isMuted` is the current output's mute state: true means muted,
                        false means unmuted. If absent, the state is unavailable.
                        Choose unchanged unless the prompt requests a mute change.
                        For a toggle, invert the known current state; otherwise choose unchanged.
                        The action applies after any requested output device switch.
                        """,
                    criteria: ["unchanged": "Leave mute unchanged", "mute": "Mute", "unmute": "Unmute"]
                ),
                "audioDevice": Question(
                    instructions: """
                        Which audio output should be selected after following the user's `prompt`?
                        Available outputs are in `settings.audio.devices`; the selected ID is
                        `settings.audio.selectedDeviceID`. Choose a device ID only when the prompt
                        requests switching outputs and identifies an available device unambiguously.
                        Otherwise choose unchanged. Never invent a device ID.
                        """,
                    criteria: deviceChoices
                )
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

        let deviceChoice = response.answers.audioDevice.choice
        let deviceID: UInt32?
        if deviceChoice == "unchanged" {
            deviceID = nil
        } else {
            guard let id = UInt32(deviceChoice), state.audio.devices.contains(where: { $0.id == id }) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [], debugDescription: "Jev selected an unavailable audio output."
                ))
            }
            deviceID = id
        }

        return SettingsDecision(
            wifi: response.answers.wifi.choice == .on,
            bluetooth: response.answers.bluetooth.choice == .on,
            audioMute: response.answers.audioMute.choice,
            audioDeviceID: deviceID
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
    let criteria: [String: String]

    init(instructions: String, criteria: [String: String]) {
        self.instructions = instructions
        self.criteria = criteria
    }

    init(setting: String, key: String) {
        criteria = ["on": "Enabled", "off": "Disabled"]
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

    struct Answer<Choice: Decodable & Sendable>: Decodable, Sendable {
        let choice: Choice
    }

    struct Answers: Decodable, Sendable {
        let wifi: Answer<PowerState>
        let bluetooth: Answer<PowerState>
        let audioMute: Answer<SettingsDecision.MuteAction>
        let audioDevice: Answer<String>
    }

    let answers: Answers
}
