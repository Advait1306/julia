//
//  Bluetooth.swift
//  julia
//
//  Created by Advait on 9/24/26.
//

import Foundation
import Combine
import CoreBluetooth

@MainActor
final class Bluetooth: NSObject, ObservableObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    @Published private(set) var isEnabled = false
    
    override init() {
        super.init()
        startIfAuthorized()
    }

    func startIfAuthorized() {
        guard CBManager.authorization == .allowedAlways else { return }
        requestAccess()
    }

    func requestAccess() {
        guard manager == nil else { return }
        manager = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.isEnabled = (central.state == .poweredOn)
    }
    
    // Methods
    func apply(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled { enable() } else { disable() }
    }

    func enable() {
        IOBluetoothPreferenceSetControllerPowerState(1)
    }
    
    func disable() {
        IOBluetoothPreferenceSetControllerPowerState(0)
    }
}
