//
//  Wifi.swift
//  julia
//
//  Created by Advait on 9/24/26.
//

import Foundation
import CoreWLAN
import Combine

@MainActor
final class Wifi: NSObject, ObservableObject, CWEventDelegate {
    private let client = CWWiFiClient.shared()
    @Published private(set) var isEnabled = false
    
    override init() {
        super.init()
        isEnabled = client.interface()?.powerOn() ?? false
        client.delegate = self
        try? client.startMonitoringEvent(with: .powerDidChange)
    }
    
    nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            guard let self, let wifi = self.client.interface(withName: interfaceName) else {return}
            self.isEnabled = wifi.powerOn()
        }
    }
    
    deinit {
        try? client.stopMonitoringEvent(with: .powerDidChange)
    }
    
    // MARK: Methods to control wifi
    
    func enable() throws {
        try? client.interface()?.setPower(true)
    }
    
    func disable() throws {
        try? client.interface()?.setPower(false)
    }
}
