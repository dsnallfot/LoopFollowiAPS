//
//  BLEDeviceSelectionView.swift
//  LoopFollow
//

import SwiftUI

struct BLEDeviceSelectionView: View {
    @ObservedObject var bleManager: BLEManager
    var selectedFilter: BackgroundRefreshType
    var onSelectDevice: (BLEDevice) -> Void

    // MARK: - Constants for Activation Date thresholds
    let daysOld = 60
    let manyDaysOld = 75

    // MARK: - Constants for BG delay thresholds
    let goodDelay = 90
    let okDelay = 180

    // MARK: - Computed Property for Filtered Devices
    var filteredDevices: [BLEDevice] {
        bleManager.devices.filter { selectedFilter.matches($0) && !isSelected($0) }
    }

    // MARK: - Body
    var body: some View {
        VStack {
            List {
                if filteredDevices.isEmpty {
                    Text("Inga enheter funna ännu. De dyker upp här när de har identifierats.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ForEach(filteredDevices, id: \.id) { (device: BLEDevice) in
                        HStack {
                            VStack(alignment: .leading) {
                                // Device Name
                                Text(device.name ?? "Okänd")
                                
                                // RSSI
                                Text("RSSI: \(device.rssi) dBm")
                                    .foregroundColor(.secondary)
                                    .font(.footnote)
                                
                                // Sensor Activation Date with color logic
                                if let sensorID = device.name,
                                   let activationDateStr = Storage.shared.latestActivationDate(for: sensorID) {
                                    Group {
                                        // Create a date formatter using a closure so that let-statements are enclosed
                                        let formatter: DateFormatter = {
                                            let df = DateFormatter()
                                            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
                                            return df
                                        }()
                                        
                                        if let activationDate = formatter.date(from: activationDateStr) {
                                            // Compute threshold dates
                                            let orangeThreshold = Calendar.current.date(byAdding: .day, value: -daysOld, to: Date())!
                                            let redThreshold = Calendar.current.date(byAdding: .day, value: -manyDaysOld, to: Date())!
                                            
                                            // Determine the color
                                            let activationColor: Color = activationDate < redThreshold ? .red : (activationDate < orangeThreshold ? .orange : .secondary)
                                            HStack{
                                                Text("Aktiverades:")
                                                    .foregroundColor(.secondary)
                                                    .font(.footnote)
                                                Text("\(activationDateStr)")
                                                    .foregroundColor(activationColor)
                                                    .font(.footnote)
                                            }
                                        } else {
                                            Text("Aktiverades: \(activationDateStr)")
                                                .foregroundColor(.secondary)
                                                .font(.footnote)
                                        }
                                    }
                                }
                                
                                // Expected BG Delay with color logic (for Dexcom devices only)
                                if Storage.shared.backgroundRefreshType.value == .dexcom,
                                   let offsetStr = BLEManager.shared.expectedSensorFetchOffsetString(for: device) {
                                    Group {
                                        // Expect offset string like "120 sek" – get the number portion.
                                        let offsetNumberString = offsetStr.components(separatedBy: " ").first ?? ""
                                        if let offsetInt = Int(offsetNumberString) {
                                            let offsetColor: Color = offsetInt > okDelay ? .red : (offsetInt > goodDelay ? .orange : .green)
                                            HStack{
                                                Text("Förväntad fördröjning BG:")
                                                    .foregroundColor(.secondary)
                                                    .font(.footnote)
                                                Text("\(offsetInt) sek")
                                                    .foregroundColor(offsetColor)
                                                    .font(.footnote)
                                            }
                                        }
                                    }
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectDevice(device)
                        }
                    }
                }
            }
        }
        .onAppear {
            bleManager.startScanning()
        }
        .onDisappear {
            bleManager.stopScanning()
        }
    }

    // MARK: - Helper
    private func isSelected(_ device: BLEDevice) -> Bool {
        guard let selectedDevice = Storage.shared.selectedBLEDevice.value else {
            return false
        }
        return selectedDevice.id == device.id
    }
}
