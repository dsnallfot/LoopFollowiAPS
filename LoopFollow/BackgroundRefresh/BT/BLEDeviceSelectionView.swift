//
//  BLEDeviceSelectionView.swift
//  LoopFollow
//

import SwiftUI

struct BLEDeviceSelectionView: View {
    @ObservedObject var bleManager: BLEManager
    var selectedFilter: BackgroundRefreshType
    var onSelectDevice: (BLEDevice) -> Void

    var body: some View {
        VStack {
            List {
                let filteredDevices = bleManager.devices.filter { selectedFilter.matches($0) && !isSelected($0) }
                if filteredDevices.isEmpty {
                    Text("Inga enheter funna ännu. De dyker upp här när de har identifierats.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ForEach(filteredDevices, id: \.id) { device in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name ?? "Okänd")
                                
                                Text("RSSI: \(device.rssi) dBm")
                                    .foregroundColor(.secondary)
                                    .font(.footnote)
                                
                                // ✅ Show Sensor Activation Date (if found)
                                if let sensorID = device.name,
                                   let activationDate = Storage.shared.latestActivationDate(for: sensorID) {
                                    Text("Aktiverades: \(activationDate)")
                                        .foregroundColor(.secondary)
                                        .font(.footnote)
                                }
                                
                                if Storage.shared.backgroundRefreshType.value == .dexcom,
                                   let offset = BLEManager.shared.expectedSensorFetchOffsetString(for: device) {
                                    Text("Förväntad fördröjning BG: \(offset)")
                                        .foregroundColor(.secondary)
                                        .font(.footnote)
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

    private func isSelected(_ device: BLEDevice) -> Bool {
        guard let selectedDevice = Storage.shared.selectedBLEDevice.value else {
            return false
        }
        return selectedDevice.id == device.id
    }
}
