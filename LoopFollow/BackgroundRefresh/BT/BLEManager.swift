//
//  BLEManager.swift
//  LoopFollow
//

import Foundation
import CoreBluetooth
import Combine

class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()

    @Published private(set) var devices: [BLEDevice] = []

    private var centralManager: CBCentralManager!
    internal var activeDevice: BluetoothDevice?
    
    var firstHeartbeat: Bool = false
    var firstHeartbeatTime: Date?

    private override init() {
        super.init()

        centralManager = CBCentralManager(delegate: self, queue: .main)

        if let device = Storage.shared.selectedBLEDevice.value {
            devices.append(device)
            findAndUpdateDevice(with: device.id.uuidString) { device in
                device.rssi = 0
            }
            connect(device: device)
        }
    }
    
    func updateDeviceBattery(deviceID: String, batteryLevel: Int?) {
        findAndUpdateDevice(with: deviceID) { device in
            LogManager.shared.log(category: .bluetooth, message: "📡 Updating battery level for \(device.name ?? "Unknown Device") to \(batteryLevel ?? 0)%", isDebug: true)
            device.batteryLevel = batteryLevel
        }
    }

    func getSelectedDevice() -> BLEDevice? {
        return devices.first { $0.id == Storage.shared.selectedBLEDevice.value?.id }
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            LogManager.shared.log(category: .bluetooth, message: "Not powered on, cannot start scan.")
            return
        }
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        cleanupOldDevices()
    }

    func disconnect() {
        if let device = activeDevice {
            device.disconnect()
            activeDevice = nil
            device.lastHeartbeatTime = nil
        }
        Storage.shared.selectedBLEDevice.value = nil
    }

    func connect(device: BLEDevice) {
        disconnect()

        if let matchedType = BackgroundRefreshType.allCases.first(where: { $0.matches(device) }) {
            Storage.shared.backgroundRefreshType.value = matchedType
            Storage.shared.selectedBLEDevice.value = device

            findAndUpdateDevice(with: device.id.uuidString) { device in
                device.isConnected = false
                device.lastConnected = nil
            }

            switch matchedType {
            case .dexcom:
                activeDevice = DexcomHeartbeatBluetoothDevice(
                    address: device.id.uuidString,
                    name: device.name,
                    bluetoothDeviceDelegate: self
                )
                activeDevice?.connect()
            case .rileyLink:
                activeDevice = RileyLinkHeartbeatBluetoothDevice(
                    address: device.id.uuidString,
                    name: device.name,
                    bluetoothDeviceDelegate: self
                )
                activeDevice?.connect()
            case .silentTune, .none:
                return
            }
        } else {
            LogManager.shared.log(category: .bluetooth, message: "No matching BackgroundRefreshType found for this device.")
        }
    }

    func stopScanning() {
        centralManager.stopScan()
    }

    func expectedHeartbeatInterval() -> TimeInterval? {
        return activeDevice?.expectedHeartbeatInterval()
    }

    /// Updates or adds a BLEDevice in the list
    private func addOrUpdateDevice(_ device: BLEDevice) {
        if let idx = devices.firstIndex(where: { $0.id == device.id }) {
            var updatedDevice = devices[idx]
            updatedDevice.rssi = device.rssi
            updatedDevice.lastSeen = Date()
            updatedDevice.batteryLevel = device.batteryLevel
            devices[idx] = updatedDevice
        } else {
            var newDevice = device
            newDevice.lastSeen = Date()
            devices.append(newDevice)
        }
        devices = devices
    }

    private func cleanupOldDevices() {
        let expirationDate = Date().addingTimeInterval(-600) // 10 minutes ago

        // Get the selected device's ID (if any)
        let selectedDeviceID = Storage.shared.selectedBLEDevice.value?.id

        // Filter devices, keeping those seen within the last 10 minutes or the selected device
        devices = devices.filter { $0.lastSeen > expirationDate || $0.id == selectedDeviceID }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            LogManager.shared.log(category: .bluetooth, message: "Central poweredOn", isDebug: true)
        default:
            LogManager.shared.log(category: .bluetooth, message: "Central state = \(central.state.rawValue), not powered on.", isDebug: true)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let uuid = peripheral.identifier
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map { $0.uuidString }

        let device = BLEDevice(
            id: uuid,
            name: peripheral.name,
            rssi: RSSI.intValue,
            advertisedServices: services,
            lastSeen: Date()
        )

        addOrUpdateDevice(device)
    }

    func findAndUpdateDevice(with deviceAddress: String, update: (inout BLEDevice) -> Void) {
        if let idx = devices.firstIndex(where: { $0.id.uuidString == deviceAddress }) {
            var device = devices[idx]
            update(&device)
            devices[idx] = device
            devices = devices
        } else {
            LogManager.shared.log(category: .bluetooth, message: "Device not found in devices array for update")
        }
    }
}

extension BLEManager: BluetoothDeviceDelegate {
    func didConnectTo(bluetoothDevice: BluetoothDevice) {
        LogManager.shared.log(category: .bluetooth, message: "Connected to: \(bluetoothDevice.deviceName ?? "Unknown")", isDebug: true)

        findAndUpdateDevice(with: bluetoothDevice.deviceAddress) { device in
            device.isConnected = true
            device.lastConnected = Date()
        }
        
        if let rlDevice = bluetoothDevice as? RileyLinkHeartbeatBluetoothDevice {
            LogManager.shared.log(category: .bluetooth, message: "🔋 Battery Level: \(rlDevice.batteryPercentage ?? 0)%", isDebug: true)
            findAndUpdateDevice(with: rlDevice.deviceAddress) { device in
                device.batteryLevel = rlDevice.batteryPercentage
            }
        }
    }

    func didDisconnectFrom(bluetoothDevice: BluetoothDevice) {
        LogManager.shared.log(category: .bluetooth, message: "Disconnected from: \(bluetoothDevice.deviceName ?? "Unknown")", isDebug: true)

        findAndUpdateDevice(with: bluetoothDevice.deviceAddress) { device in
            device.isConnected = false
            device.lastConnected = Date()
        }
    }

    func heartBeat() {
        LogManager.shared.log(category: .bluetooth, message: "Bluetooth ping received", isDebug: true)
        
        guard let device = activeDevice else { return }
        
        // Ensure background alerts are armed on every heartbeat when background refresh is active.
        if Storage.shared.backgroundRefreshType.value != .none {
            LogManager.shared.log(
                category: .backgroundAlerts,
                message: "BLEManager.heartBeat: arming BackgroundAlertManager via startBackgroundAlert()",
                isDebug: true
            )
            BackgroundAlertManager.shared.startBackgroundAlert()
        }
        
        if let rlDevice = device as? RileyLinkHeartbeatBluetoothDevice {
            LogManager.shared.log(category: .bluetooth, message: "🔋 Latest Battery Level: \(rlDevice.batteryPercentage ?? 0)%", isDebug: true)
            findAndUpdateDevice(with: rlDevice.deviceAddress) { device in
                device.batteryLevel = rlDevice.batteryPercentage
            }
        }

        let now = Date()
        guard let expectedInterval = device.expectedHeartbeatInterval() else {
            LogManager.shared.log(category: .bluetooth, message: "Heartbeat triggered")
            device.lastHeartbeatTime = now
            TaskScheduler.shared.checkTasksNow()
            return
        }
        
        let marginPercentage: Double = 0.15 // 15% margin
        let margin = expectedInterval * marginPercentage
        let threshold = expectedInterval + margin
        
        // If this is the first heartbeat, or if device.lastHeartbeatTime is nil
        if device.lastHeartbeatTime == nil {
            LogManager.shared.log(category: .bluetooth, message: "Heartbeat triggered (First heartbeat)")
            firstHeartbeat = true
            firstHeartbeatTime = now
        } else {
            // If we are still within one minute of the first heartbeat, keep firstHeartbeat true
            if firstHeartbeat, let firstTime = firstHeartbeatTime, now.timeIntervalSince(firstTime) <= 60 {
                // firstHeartbeat remains true
            } else {
                firstHeartbeat = false
            }
            
            let elapsedTime = now.timeIntervalSince(device.lastHeartbeatTime!)
            if elapsedTime > threshold {
                let delay = elapsedTime - expectedInterval
                LogManager.shared.log(category: .bluetooth, message: "Heartbeat triggered (Delayed by \(String(format: "%.1f", delay)) seconds)")
            }
        }
        
        device.lastHeartbeatTime = now
        TaskScheduler.shared.checkTasksNow()
    }
}


extension BLEManager {
    /// Returns the expected sensor fetch offset as a formatted string ("mm:ss (fetch delay: XX sec)")
    /// for Dexcom and RileyLink devices. The expected offset is computed as the sensor's schedule offset plus the polling delay.
    /// The device’s lastSeen time is used (mod cycleDuration) to calculate the effective delay between when the sensor value
    /// becomes available and when the fetch is actually triggered.
    func expectedSensorFetchOffsetString(for device: BLEDevice) -> String? {
        // Determine the device type using your BackgroundRefreshType matching.
        guard let matchedType = BackgroundRefreshType.allCases.first(where: { $0.matches(device) }) else {
            return nil
        }

        // We calculate this for Dexcom and RileyLink devices.
        if matchedType == .dexcom || matchedType == .rileyLink {
            // Return nil if the sensor schedule offset hasn't been set.
            guard let sensorOffset = Storage.shared.sensorScheduleOffset.value else {
                return nil
            }

            // Polling delay: use dynamic setting if enabled, otherwise the default.
            let pollingDelay: TimeInterval = Double(UserDefaultsRepository.bgUpdateDelay.value)

            // T_expected: the time (in seconds) after the sensor reading when the value is available.
            let expectedOffset = sensorOffset + pollingDelay

            // Determine the cycle duration based on the device type.
            let cycleDuration: TimeInterval = (matchedType == .rileyLink) ? 60 : 300

            // For RileyLink, if lastHeartbeatTime is nil, return "waiting for heartbeat".
            if matchedType == .rileyLink, self.activeDevice?.lastHeartbeatTime == nil || firstHeartbeat {
                return "väntar på heartbeat"
            }

            // Use activeDevice.lastHeartbeatTime for RileyLink; otherwise use device.lastSeen.
            let heartbeatReferenceDate: Date
            if matchedType == .rileyLink,
               let activeDevice = self.activeDevice,
               let lastHeartbeat = activeDevice.lastHeartbeatTime {
                heartbeatReferenceDate = lastHeartbeat
            } else {
                heartbeatReferenceDate = device.lastSeen
            }

            // Compute the device’s heartbeat offset within the appropriate cycle.
            let calendar = Calendar(identifier: .gregorian)
            let startOfDay = calendar.startOfDay(for: heartbeatReferenceDate)
            let heartbeatOffset = heartbeatReferenceDate.timeIntervalSince(startOfDay).truncatingRemainder(dividingBy: cycleDuration)

            // Calculate effective delay:
            // If the heartbeat happens after the sensor value is available, delay = heartbeatOffset - expectedOffset.
            // Otherwise, the fetch will occur on the next cycle:
            // delay = (heartbeatOffset + cycleDuration) - expectedOffset.
            // Daniel: Add back + pollingdelay to the effective delay to get the net delay (ie on which minago time after 00:00 is the reading expected to be seen in LF?)
            let effectiveDelay: TimeInterval = (heartbeatOffset >= expectedOffset)
                ? (heartbeatOffset - expectedOffset + pollingDelay)
                : (heartbeatOffset + cycleDuration - expectedOffset + pollingDelay)

            return "\(Int(effectiveDelay)) sek"
        }
        return nil
    }

    /// Returns the expected sensor fetch offset as seconds for Dexcom/RileyLink devices.
    /// This is the same value shown by `expectedSensorFetchOffsetString(for:)` (without formatting).
    func expectedSensorFetchOffsetSeconds(for device: BLEDevice) -> Int? {
        // Determine the device type using your BackgroundRefreshType matching.
        guard let matchedType = BackgroundRefreshType.allCases.first(where: { $0.matches(device) }) else {
            return nil
        }

        // We calculate this for Dexcom and RileyLink devices.
        if matchedType == .dexcom || matchedType == .rileyLink {
            // Return nil if the sensor schedule offset hasn't been set.
            guard let sensorOffset = Storage.shared.sensorScheduleOffset.value else {
                return nil
            }

            // Polling delay: use dynamic setting if enabled, otherwise the default.
            let pollingDelay: TimeInterval = Double(UserDefaultsRepository.bgUpdateDelay.value)

            // T_expected: the time (in seconds) after the sensor reading when the value is available.
            let expectedOffset = sensorOffset + pollingDelay

            // Determine the cycle duration based on the device type.
            let cycleDuration: TimeInterval = (matchedType == .rileyLink) ? 60 : 300

            // For RileyLink, if lastHeartbeatTime is nil, return nil (waiting for heartbeat).
            if matchedType == .rileyLink, (self.activeDevice?.lastHeartbeatTime == nil || firstHeartbeat) {
                return nil
            }

            // Use activeDevice.lastHeartbeatTime for RileyLink; otherwise use device.lastSeen.
            let heartbeatReferenceDate: Date
            if matchedType == .rileyLink,
               let activeDevice = self.activeDevice,
               let lastHeartbeat = activeDevice.lastHeartbeatTime {
                heartbeatReferenceDate = lastHeartbeat
            } else {
                heartbeatReferenceDate = device.lastSeen
            }

            // Compute the device’s heartbeat offset within the appropriate cycle.
            let calendar = Calendar(identifier: .gregorian)
            let startOfDay = calendar.startOfDay(for: heartbeatReferenceDate)
            let heartbeatOffset = heartbeatReferenceDate.timeIntervalSince(startOfDay).truncatingRemainder(dividingBy: cycleDuration)

            // Calculate effective delay (same math as in expectedSensorFetchOffsetString).
            let effectiveDelay: TimeInterval = (heartbeatOffset >= expectedOffset)
                ? (heartbeatOffset - expectedOffset + pollingDelay)
                : (heartbeatOffset + cycleDuration - expectedOffset + pollingDelay)

            // Normalize into 0...(cycle-1)
            let normalized = Int(effectiveDelay.rounded())
            let cycleInt = Int(cycleDuration)
            let clamped = ((normalized % cycleInt) + cycleInt) % cycleInt
            return clamped
        }

        return nil
    }

    /// Suggests which offset (0...299) to use in `SyncNewSensorView` so that as many discovered
    /// Dexcom heartbeats as possible land in the "optimal" fetch delay window (default 20–40s).
    ///
    /// Interpretation (matches your SyncNewSensorView text):
    /// - offset = 0   => new sensor heartbeat same second as current
    /// - offset = 30  => new sensor heartbeat ~30s earlier
    /// - offset = 270 => new sensor heartbeat ~30s later
    ///
    /// Internally we assume shifting the new sensor by `offset` shifts each discovered sensor’s
    /// effective delay by +offset (mod 300).
    func suggestedHeartbeatOffsetForNextSensor(optimalWindow: ClosedRange<Int> = 20...40) -> (offset: Int, matches: Int, total: Int)? {
        // Only meaningful if we're in Dexcom mode.
        guard Storage.shared.backgroundRefreshType.value == .dexcom else {
            return nil
        }

        // Gather current effective delays for all discovered Dexcom-like devices.
        let dexcomDevices = devices.filter { BackgroundRefreshType.dexcom.matches($0) }
        let delays: [Int] = dexcomDevices.compactMap { expectedSensorFetchOffsetSeconds(for: $0) }

        guard !delays.isEmpty else {
            return nil
        }

        // Brute-force all offsets and pick the one that maximizes the number of devices
        // whose shifted delay ends up inside the optimal window.
        var bestOffset = 0
        var bestMatches = -1
        var bestDistanceSum = Int.max

        let targetCenter = (optimalWindow.lowerBound + optimalWindow.upperBound) / 2

        for candidate in 0...299 {
            var matches = 0
            var distanceSum = 0

            for d in delays {
                let shifted = (d + candidate) % 300
                if optimalWindow.contains(shifted) {
                    matches += 1
                    distanceSum += abs(shifted - targetCenter)
                } else {
                    // Penalize near-misses lightly so ties break toward "closest".
                    // Distance to nearest bound.
                    let distToWindow: Int
                    if shifted < optimalWindow.lowerBound {
                        distToWindow = optimalWindow.lowerBound - shifted
                    } else {
                        distToWindow = shifted - optimalWindow.upperBound
                    }
                    distanceSum += (distToWindow + 20) // small bias so true hits win
                }
            }

            if matches > bestMatches {
                bestMatches = matches
                bestOffset = candidate
                bestDistanceSum = distanceSum
            } else if matches == bestMatches {
                // Tie-breaker: minimize overall distance to the target window/center.
                if distanceSum < bestDistanceSum {
                    bestOffset = candidate
                    bestDistanceSum = distanceSum
                }
            }
        }

        return (offset: bestOffset, matches: bestMatches, total: delays.count)
    }
}

