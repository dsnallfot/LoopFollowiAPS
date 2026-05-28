//
//  BluetoothDeviceDelegate.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-04.

//

import Foundation
import CoreBluetooth

protocol BluetoothDeviceDelegate: AnyObject {
    func didConnectTo(bluetoothDevice: BluetoothDevice)

    func didDisconnectFrom(bluetoothDevice: BluetoothDevice)

    func heartBeat(source: String)
}

extension BluetoothDeviceDelegate {
    func heartBeat() {
        heartBeat(source: "unknown")
    }
}
