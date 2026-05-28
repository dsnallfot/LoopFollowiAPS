//
//  RileyLinkHeartbeatBluetoothDevice.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-08.
//  Copyright © 2025 Jon Fawcett.
//

import Foundation
import CoreBluetooth

/// RileyLink Bluetooth Services and Characteristics
enum RileyLinkServiceUUID: String {
    case main = "0235733B-99C5-4197-B856-69219C2A3845"
    case battery = "180F" // Battery Service

    var cbUUID: CBUUID {
        return CBUUID(string: self.rawValue)
    }
}

enum BatteryServiceCharacteristicUUID: String {
    case batteryLevel = "2A19" // Battery Level Characteristic

    var cbUUID: CBUUID {
        return CBUUID(string: self.rawValue)
    }
}

class RileyLinkHeartbeatBluetoothDevice: BluetoothDevice {
    private let CBUUID_Service_RileyLink = RileyLinkServiceUUID.main.cbUUID
    private let CBUUID_Service_Battery = RileyLinkServiceUUID.battery.cbUUID
    private let CBUUID_ReceiveCharacteristic_TimerTick = CBUUID(string: "6E6C7910-B89E-43A5-78AF-50C5E2B86F7E")
    
    private var peripheralDevice: CBPeripheral? // Store peripheral reference
    private var timerTickCharacteristic: CBCharacteristic? // Store for notifications

    var batteryPercentage: Int?

    init(address: String, name: String?, bluetoothDeviceDelegate: BluetoothDeviceDelegate) {
        super.init(
            address: address,
            name: name,
            CBUUID_Advertisement: nil,
            servicesCBUUIDs: [CBUUID_Service_RileyLink, CBUUID_Service_Battery],
            CBUUID_ReceiveCharacteristic: CBUUID_ReceiveCharacteristic_TimerTick.uuidString,
            bluetoothDeviceDelegate: bluetoothDeviceDelegate
        )
    }

    /// Handle connection event
    override func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Trigger heartbeat before `super`, for consistency with Dexcom handling.
        // This keeps the heartbeat/task chain as early as possible while the app is
        // still awake from the BLE event.
        self.bluetoothDeviceDelegate?.heartBeat(source: "didConnect")

        super.centralManager(central, didConnect: peripheral)

        self.peripheralDevice = peripheral // Store reference
        LogManager.shared.log(category: .bluetooth, message: "✅ Connected to RileyLink, discovering services...", isDebug: true)

        peripheral.discoverServices([CBUUID_Service_RileyLink, CBUUID_Service_Battery])
    }

    /// Discover characteristics for each service
    override func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        for service in services {
            LogManager.shared.log(category: .bluetooth, message: "🛠️ Discovered Service: \(service.uuid.uuidString)", isDebug: true)
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    /// Detects the right characteristics and sets notifications if needed
    override func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            if characteristic.uuid == BatteryServiceCharacteristicUUID.batteryLevel.cbUUID {
                LogManager.shared.log(category: .bluetooth, message: "🔋 Found Battery Level Characteristic, reading value...", isDebug: true)
                peripheral.readValue(for: characteristic)

            } else if characteristic.uuid == CBUUID_ReceiveCharacteristic_TimerTick {
                self.timerTickCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    /// Handles incoming characteristic values
    override func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        super.peripheral(peripheral, didUpdateValueFor: characteristic, error: error)

        if characteristic.uuid == BatteryServiceCharacteristicUUID.batteryLevel.cbUUID, let data = characteristic.value, data.count > 0 {
            let batteryPercentage = Int(data[0]) // 0-100% battery level
            self.batteryPercentage = batteryPercentage

            LogManager.shared.log(category: .bluetooth, message: "🔋 Battery Level Updated: \(batteryPercentage)%", isDebug: true)
            
            // Ensure BLEManager gets this update
            BLEManager.shared.updateDeviceBattery(deviceID: self.deviceAddress, batteryLevel: batteryPercentage)
        }
        
        // Ensure `heartBeat()` always triggers, even if battery wasn't updated
        self.bluetoothDeviceDelegate?.heartBeat(source: "didUpdateValue")
    }

    /// Public method to manually request battery level (called by BLEManager)
    func requestBatteryLevel() {
        guard let peripheral = self.peripheralDevice else {
            LogManager.shared.log(category: .bluetooth, message: "❌ No peripheral available for battery request!", isDebug: true)
            return
        }
        requestBatteryLevel(for: peripheral)
    }

    /// Reads the battery level from the correct service
    private func requestBatteryLevel(for peripheral: CBPeripheral) {
        guard let characteristic = peripheral.getBatteryCharacteristic(.batteryLevel) else {
            LogManager.shared.log(category: .bluetooth, message: "❌ Battery characteristic not found!", isDebug: true)
            return
        }

        LogManager.shared.log(category: .bluetooth, message: "📡 Requesting battery level...", isDebug: true)
        peripheral.readValue(for: characteristic)
    }

    override func expectedHeartbeatInterval() -> TimeInterval? {
        return 60
    }
}

extension CBPeripheral {
    /// Helper function to get the battery characteristic
    func getBatteryCharacteristic(_ uuid: BatteryServiceCharacteristicUUID) -> CBCharacteristic? {
        guard let service = services?.first(where: { $0.uuid == RileyLinkServiceUUID.battery.cbUUID }) else {
            return nil
        }
        return service.characteristics?.first(where: { $0.uuid == uuid.cbUUID })
    }
}
