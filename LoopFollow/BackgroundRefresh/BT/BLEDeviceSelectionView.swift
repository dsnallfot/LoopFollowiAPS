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

    @State private var showConfirmAlert: Bool = false
    @State private var pendingDevice: BLEDevice?

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if filteredDevices.isEmpty {
                Text("Inga enheter funna ännu. De dyker upp här när de har identifierats.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredDevices, id: \.id) { (device: BLEDevice) in
                        VStack(alignment: .leading, spacing: 2) {
                            // Device Name
                            let deviceName = device.name ?? "Okänd"
                            let isHit: Bool = {
                                // Only show hit-markers for Dexcom mode (5-min cycle alignment)
                                guard Storage.shared.backgroundRefreshType.value == .dexcom,
                                      let suggestion = bleManager.suggestedHeartbeatOffsetForNextSensor(optimalWindow: 40...60),
                                      BackgroundRefreshType.dexcom.matches(device),
                                      let d = bleManager.expectedSensorFetchOffsetSeconds(for: device)
                                else { return false }

                                let shifted = (d + suggestion.offset) % 300
                                return (40...60).contains(shifted)
                            }()

                            Text(isHit ? "* \(deviceName)" : deviceName)

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
                                        HStack {
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
                                        HStack {
                                            Text("Förväntad fördröjning BG:")
                                                .foregroundColor(.secondary)
                                                .font(.footnote)
                                            Text("\(offsetInt) sek")
                                                .foregroundColor(offsetColor)
                                                .font(.footnote)
                                        }

                                        // Offset you should enter in SyncNewSensorView so the *new* sensor reports ~30s before THIS device.
                                        // We want: (deviceDelay + pairingOffset) % 300 == 30
                                        let targetDelay = 50
                                        let optimalPairingOffset = ((targetDelay - offsetInt) % 300 + 300) % 300

                                        HStack {
                                            Text("Optimal offset nästa sensorbyte:")
                                                .foregroundColor(.secondary)
                                                .font(.footnote)

                                            Text("\(optimalPairingOffset) sek")
                                                .foregroundColor(.secondary)
                                                .font(.footnote)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            pendingDevice = device
                            showConfirmAlert = true
                        }
                        .alert("Ställ in enhet för heartbeat", isPresented: $showConfirmAlert) {
                            Button("Ja") {
                                if let device = pendingDevice {
                                    onSelectDevice(device)
                                }
                                pendingDevice = nil
                            }
                            Button("Avbryt", role: .cancel) {
                                pendingDevice = nil
                            }
                        } message: {
                            if let name = pendingDevice?.name {
                                Text("\nVill du använda \(name) för att väcka appen i bakgrunden?")
                            }
                        }

                        // Divider between rows
                        Divider().opacity(0.35)
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
