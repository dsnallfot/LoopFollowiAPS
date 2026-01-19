//
//  BLEManager.swift
//  LoopFollow
//

import Foundation
import CoreBluetooth
import Combine

// MARK: - Bluetooth Heartbeat Notification
extension Notification.Name {
    static let bluetoothHeartbeatUpdated = Notification.Name("bluetoothHeartbeatUpdated")
}

class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()

    @Published private(set) var devices: [BLEDevice] = []

    private var centralManager: CBCentralManager!
    internal var activeDevice: BluetoothDevice?
    
    var firstHeartbeat: Bool = false
    var firstHeartbeatTime: Date?

    // Throttle for offset debug logging (per device)
    private var lastOffsetLogTimestamp: [UUID: Date] = [:]
    private var lastOffsetLogSignature: [UUID: String] = [:]

    /// Returns the timestamp of the latest Bluetooth heartbeat, if any
    var lastHeartbeatDate: Date? {
        return activeDevice?.lastHeartbeatTime
    }

    private override init() {
        super.init()

        // Use a dedicated queue so CoreBluetooth callbacks are not dependent on the main runloop.
        let bleQueue = DispatchQueue(label: "com.loopfollow.blemanager.queue")
        
        // NOTE: We intentionally do NOT enable state restoration here.
        // State restoration is handled by the per-device BluetoothDevice central (e.g. DexcomHeartbeatBluetoothDevice)
        // which owns the active connection. Having multiple restoring centrals can create ambiguous relaunch/restore behavior.
        LogManager.shared.log(category: .bluetooth, message: "BLEManager: creating non-restoring central", isDebug: true, isTempDebug: true)

        centralManager = CBCentralManager(
            delegate: self,
            queue: bleQueue,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "LoopFollow-ScanningCentral"]
        )

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

    func disconnect(clearSelection: Bool = true) {
        if let device = activeDevice {
            device.disconnect()
            activeDevice = nil
            device.lastHeartbeatTime = nil
            firstHeartbeat = false
            firstHeartbeatTime = nil
        }

        if clearSelection {
            Storage.shared.selectedBLEDevice.value = nil
        }
    }

    func connect(device: BLEDevice) {
        // IMPORTANT: Do not clear selectedBLEDevice during reconnects; a transient nil can cause UI/observers
        // to auto-select another discovered sensor.
        disconnect(clearSelection: false)

        if let matchedType = BackgroundRefreshType.allCases.first(where: { $0.matches(device) }) {
            DispatchQueue.main.async {
                Storage.shared.backgroundRefreshType.value = matchedType
                Storage.shared.selectedBLEDevice.value = device
            }

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
    /// NOTE: CoreBluetooth callbacks can arrive on a background queue; `@Published` must update on main.
    private func addOrUpdateDevice(_ device: BLEDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let idx = self.devices.firstIndex(where: { $0.id == device.id }) {
                var updatedDevice = self.devices[idx]
                updatedDevice.rssi = device.rssi
                updatedDevice.lastSeen = device.lastSeen
                updatedDevice.batteryLevel = device.batteryLevel
                self.devices[idx] = updatedDevice
            } else {
                var newDevice = device
                newDevice.lastSeen = Date()
                self.devices.append(newDevice)
            }

            // Force SwiftUI to refresh for in-place mutations.
            self.devices = self.devices
        }
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
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        LogManager.shared.log(category: .bluetooth, message: "🔄 BLEManager: State Restoration triggered!", isDebug: true, isTempDebug: true)

        // 1. Hantera återställda enheter (Peripherals)
        // Om iOS har hållit en anslutning vid liv åt oss, får vi tillbaka den här.
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                LogManager.shared.log(category: .bluetooth, message: "🔄 Restored peripheral: \(peripheral.name ?? "Unknown") - State: \(peripheral.state.rawValue)", isDebug: true, isTempDebug: true)
                
                // Om vi hittar en enhet här kan det vara bra att återupprätta kopplingen till vår interna lista
                // Men eftersom BLEManager främst scannar, räcker det ofta med att bara logga detta.
                // Om enheten är 'connected' men vi tappat referensen, kan vi behöva hantera det,
                // men CoreBluetooth sköter oftast det mesta automatiskt om identifieraren är satt.
            }
        }

        // 2. Hantera återställd scanning
        // Detta bekräftar att iOS kommer fortsätta scanna åt oss i bakgrunden.
        if let services = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID] {
            let serviceNames = services.map { $0.uuidString }.joined(separator: ", ")
            LogManager.shared.log(category: .bluetooth, message: "🔄 Restored scanning for services: \(serviceNames)", isDebug: true, isTempDebug: true)
        } else {
            LogManager.shared.log(category: .bluetooth, message: "🔄 No scan services found in restoration state. Might need to restart scan.", isDebug: true, isTempDebug: true)
            // Om ingen scanning återställdes, kan det vara säkert att trigga en ny scan här:
            if central.state == .poweredOn {
                startScanning()
            }
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            LogManager.shared.log(category: .bluetooth, message: "Central poweredOn", isDebug: true, isTempDebug: true)
            // If we have a previously selected device, ensure we are connected when Bluetooth becomes available again.
            if let selected = Storage.shared.selectedBLEDevice.value {
                // If activeDevice is missing or we are not currently connected, attempt a reconnect.
                let isConnected = (self.getSelectedDevice()?.isConnected ?? false)
                if self.activeDevice == nil || !isConnected {
                    LogManager.shared.log(category: .bluetooth, message: "Bluetooth poweredOn: ensuring connection to selected device", isDebug: true, isTempDebug: true)
                    DispatchQueue.main.async {
                        self.connect(device: selected)
                    }
                }
            }
        default:
            LogManager.shared.log(category: .bluetooth, message: "Central state = \(central.state.rawValue), not powered on.", isDebug: true, isTempDebug: true)
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
        LogManager.shared.log(category: .bluetooth, message: "Connected to: \(bluetoothDevice.deviceName ?? "Unknown")", isDebug: true, isTempDebug: true)

        findAndUpdateDevice(with: bluetoothDevice.deviceAddress) { device in
            device.isConnected = true
            device.lastConnected = Date()
            device.lastSeen = Date()
        }
        
        if let rlDevice = bluetoothDevice as? RileyLinkHeartbeatBluetoothDevice {
            LogManager.shared.log(category: .bluetooth, message: "🔋 Battery Level: \(rlDevice.batteryPercentage ?? 0)%", isDebug: true, isTempDebug: true)
            findAndUpdateDevice(with: rlDevice.deviceAddress) { device in
                device.batteryLevel = rlDevice.batteryPercentage
            }
        }
    }

    func didDisconnectFrom(bluetoothDevice: BluetoothDevice) {
        LogManager.shared.log(category: .bluetooth, message: "Disconnected from: \(bluetoothDevice.deviceName ?? "Unknown")", isDebug: true, isTempDebug: true)

        findAndUpdateDevice(with: bluetoothDevice.deviceAddress) { device in
            device.isConnected = false
            device.lastConnected = Date()
            device.lastSeen = Date()
        }
    }

    func heartBeat() {
        LogManager.shared.log(category: .bluetooth, message: "Bluetooth ping received")
        
        guard let device = activeDevice else { return }
        
        // Ensure background alerts are armed on every heartbeat when background refresh is active.
        if Storage.shared.backgroundRefreshType.value != .none {
            LogManager.shared.log(
                category: .backgroundAlerts,
                message: "BLEManager.heartBeat: arming BackgroundAlertManager via startBackgroundAlert()",
                isDebug: true,
                isTempDebug: true
            )
            BackgroundAlertManager.shared.startBackgroundAlert()
        }
        
        if let rlDevice = device as? RileyLinkHeartbeatBluetoothDevice {
            LogManager.shared.log(category: .bluetooth, message: "🔋 Latest Battery Level: \(rlDevice.batteryPercentage ?? 0)%", isDebug: true, isTempDebug: true)
            findAndUpdateDevice(with: rlDevice.deviceAddress) { device in
                device.batteryLevel = rlDevice.batteryPercentage
            }
        }

        let now = Date()
        guard let expectedInterval = device.expectedHeartbeatInterval() else {
            LogManager.shared.log(category: .bluetooth, message: "Heartbeat triggered")
            device.lastHeartbeatTime = now
            // Keep the selected/stored device's lastSeen moving so expectedSensorFetchOffsetString(for:) stays current
            findAndUpdateDevice(with: device.deviceAddress) { d in
                d.lastSeen = now
            }
            TaskScheduler.shared.checkTasksNow()
            // Notify UI that a new Bluetooth heartbeat was received
            NotificationCenter.default.post(name: .bluetoothHeartbeatUpdated, object: nil)
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
        // Keep the selected/stored device's lastSeen moving so expectedSensorFetchOffsetString(for:) stays current
        findAndUpdateDevice(with: device.deviceAddress) { d in
            d.lastSeen = now
        }
        TaskScheduler.shared.checkTasksNow()
        // Notify UI that a new Bluetooth heartbeat was received
        NotificationCenter.default.post(name: .bluetoothHeartbeatUpdated, object: nil)
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
            
            // Prefer activeDevice.lastHeartbeatTime for the *currently selected* device (Dexcom or RileyLink),
            // since device.lastSeen for the stored device can include app-side latency (≈ pollingDelay).
            let heartbeatReferenceDate: Date
            if let activeDevice = self.activeDevice,
               let lastHeartbeat = activeDevice.lastHeartbeatTime,
               let selected = Storage.shared.selectedBLEDevice.value,
               selected.id.uuidString == activeDevice.deviceAddress,
               device.id.uuidString == activeDevice.deviceAddress,
               (matchedType == .rileyLink || matchedType == .dexcom) {
                // Only the currently selected device should use the active device's heartbeat timestamp.
                heartbeatReferenceDate = lastHeartbeat - 10
            } else {
                // Discovered/non-selected devices use their own advertisement lastSeen timestamp.
                heartbeatReferenceDate = device.lastSeen
            }
            
            // Compute the device’s heartbeat offset within the appropriate cycle.
            let calendar = Calendar(identifier: .gregorian)
            let startOfDay = calendar.startOfDay(for: heartbeatReferenceDate)
            let heartbeatOffset = heartbeatReferenceDate.timeIntervalSince(startOfDay).truncatingRemainder(dividingBy: cycleDuration)

            // Throttle this debug log heavily; SwiftUI can call this function many times per second.
            let signature = "refIsActive=\(device.id.uuidString == self.activeDevice?.deviceAddress) hbOffset=\(Int(heartbeatOffset)) expectedOffset=\(Int(expectedOffset)) pollingDelay=\(Int(pollingDelay))"
            let lastSig = lastOffsetLogSignature[device.id]
            let lastTs = lastOffsetLogTimestamp[device.id] ?? .distantPast

            if lastSig != signature || Date().timeIntervalSince(lastTs) >= 10 {
                lastOffsetLogSignature[device.id] = signature
                lastOffsetLogTimestamp[device.id] = Date()

                LogManager.shared.log(
                    category: .bluetooth,
                    message: "Offset calc: name=\(device.name ?? "?") id=\(device.id.uuidString.prefix(6)) \(signature)",
                    isTempDebug: true
                )
            }
            
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
            
            // Prefer activeDevice.lastHeartbeatTime for the *currently selected* device (Dexcom or RileyLink),
            // since device.lastSeen for the stored device can include app-side latency (≈ pollingDelay).
            let heartbeatReferenceDate: Date
            if let activeDevice = self.activeDevice,
               let lastHeartbeat = activeDevice.lastHeartbeatTime,
               let selected = Storage.shared.selectedBLEDevice.value,
               selected.id.uuidString == activeDevice.deviceAddress,
               device.id.uuidString == activeDevice.deviceAddress,
               (matchedType == .rileyLink || matchedType == .dexcom) {
                // Only the currently selected device should use the active device's heartbeat timestamp.
                heartbeatReferenceDate = lastHeartbeat - 10
            } else {
                // Discovered/non-selected devices use their own advertisement lastSeen timestamp.
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
    /// Dexcom heartbeats as possible land in the "optimal" fetch delay window (default 40–60s).
    ///
    /// Interpretation (matches your SyncNewSensorView text):
    /// - offset = 0   => new sensor heartbeat same second as current
    /// - offset = 30  => new sensor heartbeat ~30s earlier
    /// - offset = 270 => new sensor heartbeat ~30s later
    ///
    /// Internally we assume shifting the new sensor by `offset` shifts each discovered sensor’s
    /// effective delay by +offset (mod 300).
    func suggestedHeartbeatOffsetForNextSensor(optimalWindow: ClosedRange<Int> = 40...60) -> (offset: Int, matches: Int, total: Int)? {
        // Only meaningful if we're in Dexcom mode.
        guard Storage.shared.backgroundRefreshType.value == .dexcom else {
            return nil
        }

        // Age thresholds (same intent as BLEDeviceSelectionView coloring)
        let daysOld = 60
        let manyDaysOld = 75

        // Helper to parse the stored activation date string ("yyyy-MM-dd HH:mm:ss")
        let activationFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return df
        }()

        // Gather effective delays for discovered Dexcom devices, with age-based filtering/prioritization:
        // - Exclude sensors older than `manyDaysOld`
        // - Prefer sensors <= `daysOld` (fresh) over 60–75 day sensors (stale) during offset selection
        let dexcomDevices = devices.filter { BackgroundRefreshType.dexcom.matches($0) }

        var freshDelays: [Int] = []
        var staleDelays: [Int] = []

        for device in dexcomDevices {
            guard let delay = expectedSensorFetchOffsetSeconds(for: device) else { continue }

            // If we can resolve activation date, use it for age-based filtering/priority.
            // If we cannot, treat it as "stale" (lower priority) but still include it (unless you prefer strict exclusion).
            if let sensorID = device.name,
               let activationStr = Storage.shared.latestActivationDate(for: sensorID),
               let activationDate = activationFormatter.date(from: activationStr) {

                let ageDays = Calendar.current.dateComponents([.day], from: activationDate, to: Date()).day ?? 0

                // Exclude very old sensors
                if ageDays > manyDaysOld {
                    continue
                }

                if ageDays <= daysOld {
                    freshDelays.append(delay)
                } else {
                    staleDelays.append(delay)
                }
            } else {
                // Unknown activation date: keep it, but deprioritize
                staleDelays.append(delay)
            }
        }

        let total = freshDelays.count + staleDelays.count
        guard total > 0 else {
            return nil
        }

        // Brute-force all offsets:
        // Primary objective: maximize fresh hits in optimal window
        // Secondary objective: maximize stale hits in optimal window
        // Tie-breaker: minimize distance to window center (overall)
        var bestOffset = 0
        var bestFreshHits = -1
        var bestStaleHits = -1
        var bestDistanceSum = Int.max

        let targetCenter = (optimalWindow.lowerBound + optimalWindow.upperBound) / 2

        for candidate in 0...299 {
            var freshHits = 0
            var staleHits = 0
            var distanceSum = 0

            for d in freshDelays {
                let shifted = (d + candidate) % 300
                if optimalWindow.contains(shifted) {
                    freshHits += 1
                    distanceSum += abs(shifted - targetCenter)
                } else {
                    let distToWindow: Int
                    if shifted < optimalWindow.lowerBound {
                        distToWindow = optimalWindow.lowerBound - shifted
                    } else {
                        distToWindow = shifted - optimalWindow.upperBound
                    }
                    distanceSum += (distToWindow + 20)
                }
            }

            for d in staleDelays {
                let shifted = (d + candidate) % 300
                if optimalWindow.contains(shifted) {
                    staleHits += 1
                    distanceSum += abs(shifted - targetCenter)
                } else {
                    let distToWindow: Int
                    if shifted < optimalWindow.lowerBound {
                        distToWindow = optimalWindow.lowerBound - shifted
                    } else {
                        distToWindow = shifted - optimalWindow.upperBound
                    }
                    distanceSum += (distToWindow + 20)
                }
            }

            if freshHits > bestFreshHits {
                bestFreshHits = freshHits
                bestStaleHits = staleHits
                bestOffset = candidate
                bestDistanceSum = distanceSum
            } else if freshHits == bestFreshHits {
                if staleHits > bestStaleHits {
                    bestStaleHits = staleHits
                    bestOffset = candidate
                    bestDistanceSum = distanceSum
                } else if staleHits == bestStaleHits {
                    if distanceSum < bestDistanceSum {
                        bestOffset = candidate
                        bestDistanceSum = distanceSum
                    }
                }
            }
        }

        return (offset: bestOffset, matches: bestFreshHits + bestStaleHits, total: total)
    }
}
