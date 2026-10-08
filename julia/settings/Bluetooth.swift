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
    @discardableResult
    func enable() -> Bool {
        let previousState = IOBluetoothPreferenceGetControllerPowerState()
        IOBluetoothPreferenceSetControllerPowerState(1)
        return previousState != 1 && IOBluetoothPreferenceGetControllerPowerState() == 1
    }
    
    @discardableResult
    func disable() -> Bool {
        let previousState = IOBluetoothPreferenceGetControllerPowerState()
        IOBluetoothPreferenceSetControllerPowerState(0)
        return previousState != 0 && IOBluetoothPreferenceGetControllerPowerState() == 0
    }
}
