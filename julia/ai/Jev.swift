//
//  Jev.swift
//  julia
//
//  Created by Advait on 9/28/26.
//

import Alamofire
import Foundation

nonisolated struct SettingsState: Encodable, Sendable {
    var wifi: Bool
    var bluetooth: Bool
    var audio: AudioState
    var focus: FocusState
    var apps: [InstalledApp]

    struct AudioState: Encodable, Sendable {
        let devices: [AudioDevice]
        let selectedDeviceID: UInt32?
        let isMuted: Bool?
    }

    struct FocusState: Encodable, Sendable {
        let modes: [FocusMode]?
        let isActive: Bool?
        let currentModeID: String?
    }
}

nonisolated struct SettingsDecision: Sendable {
    enum MuteAction: String, Decodable, Sendable {
        case unchanged, mute, unmute
    }

    enum PlaybackAction: String, Decodable, Sendable {
        case unchanged, play, pause
    }

    enum FocusChoice: Sendable {
        case unchanged, off, mode(String)
    }

    let wifi: Bool
    let bluetooth: Bool
    let audioMute: MuteAction
    let audioDeviceID: UInt32?
    let playback: PlaybackAction
    let focus: FocusChoice
    let appID: String?
}

final class Jev {
    private let apiKey: String?
    private let session: Session

    init(apiKey: String? = nil, session: Session = .default) {
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["JEV_API_KEY"]
        self.session = session
    }

    func evaluate(prompt: String, state: SettingsState) async throws -> SettingsDecision {
        guard let apiKey, !apiKey.isEmpty else {
            throw NSError(domain: "Jev", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "JEV_API_KEY is missing. Launch Julia with its configured Xcode scheme."
            ])
        }
        var deviceChoices = ["unchanged": "Keep the current audio output"]
        for device in state.audio.devices {
            deviceChoices[String(device.id)] = device.name
        }

        var focusChoices = ["unchanged": "Keep the current Focus", "off": "No Focus"]
        for mode in state.focus.modes ?? [] {
            focusChoices[mode.id] = mode.name
        }

        var appChoices = ["unchanged": "Don't open or switch apps"]
        for app in state.apps {
            if let identifier = app.bundleIdentifier {
                appChoices[app.id] = "\(app.name) (bundle ID: \(identifier))"
            } else {
                appChoices[app.id] = app.name
            }
        }

        let parameters = EvaluationRequest(
            state: .init(prompt: prompt, settings: state),
            questions: [
                "wifi": Question(setting: "Wi-Fi", key: "wifi"),
                "bluetooth": Question(setting: "Bluetooth", key: "bluetooth"),
                "openApp": Question(
                    instructions: """
                        Which installed app does the user's `prompt` request opening, launching,
                        or switching to? Available apps are in `settings.apps`; each ID is its
                        exact installed path. Match the requested product using its name,
                        filename, and bundleIdentifier. Display names and filenames can be
                        outdated after an app is renamed; the bundle identifier can identify
                        the product. Prefer an exact product match over a similar app name.
                        Choose a listed ID only when the prompt explicitly
                        requests opening or switching to one app and identifies it unambiguously.
                        Opening also brings an already running app to the foreground.
                        Choose unchanged for unrelated requests, merely mentioning an app,
                        unavailable apps, ambiguous names, or requests to open multiple apps.
                        Never substitute a different app just because its name is similar.
                        Never invent an app ID or a command.
                        """,
                    criteria: appChoices
                ),
                "focusMode": Question(
                    instructions: """
                        Which Focus mode does the user's `prompt` request?
                        Available modes are in `settings.focus.modes`; the current mode ID is
                        `settings.focus.currentModeID`. `settings.focus.isActive` is true when
                        Focus is active and false when off. Absent fields mean unavailable;
                        an absent currentModeID does not mean off. Never infer a current mode.
                        Choose unchanged unless the prompt requests a Focus change.
                        Choose off to disable Focus, or a listed mode ID only when the prompt
                        identifies an available mode unambiguously. Never invent a mode ID.
                        For a toggle, use the known current state; otherwise choose unchanged.
                        """,
                    criteria: focusChoices
                ),
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
                "playback": Question(
                    instructions: """
                        Which playback action does the user's `prompt` request for the current
                        system Now Playing app? Choose unchanged unless the prompt explicitly
                        requests playing/resuming or pausing media playback.
                        Playing/pausing is separate from muting/unmuting audio.
                        Playback state is unknown: never infer it from audio mute state.
                        Use play for play/resume and pause for pause.
                        """,
                    criteria: [
                        "unchanged": "Leave playback unchanged",
                        "play": "Play or resume the current media",
                        "pause": "Pause the current media"
                    ]
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

        let response = try await session.request(
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

        let focusChoice: SettingsDecision.FocusChoice
        switch response.answers.focusMode.choice {
        case "unchanged": focusChoice = .unchanged
        case "off": focusChoice = .off
        case let id:
            guard state.focus.modes?.contains(where: { $0.id == id }) == true else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [], debugDescription: "Jev selected an unavailable Focus mode."
                ))
            }
            focusChoice = .mode(id)
        }

        let appChoice = response.answers.openApp.choice
        let appID: String?
        if appChoice == "unchanged" {
            appID = nil
        } else {
            guard state.apps.contains(where: { $0.id == appChoice }) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [], debugDescription: "Jev selected an unavailable app."
                ))
            }
            appID = appChoice
        }

        return SettingsDecision(
            wifi: response.answers.wifi.choice == .on,
            bluetooth: response.answers.bluetooth.choice == .on,
            audioMute: response.answers.audioMute.choice,
            audioDeviceID: deviceID,
            playback: response.answers.playback.choice,
            focus: focusChoice,
            appID: appID
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
        let playback: Answer<SettingsDecision.PlaybackAction>
        let focusMode: Answer<String>
        let openApp: Answer<String>
    }

    let answers: Answers
}
