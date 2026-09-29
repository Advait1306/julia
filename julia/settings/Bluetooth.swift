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
        manager = CBCentralManager(delegate: self, queue: .main)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.isEnabled = (central.state == .poweredOn)
    }
    
    // Methods
    func enable() {
        IOBluetoothPreferenceSetControllerPowerState(1)
    }
    
    func disable() {
        IOBluetoothPreferenceSetControllerPowerState(0)
    }
}
