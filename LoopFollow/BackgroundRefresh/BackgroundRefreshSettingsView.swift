//
//  BackgroundRefreshSettingsView.swift
//  LoopFollow
//

import SwiftUI

struct BackgroundRefreshSettingsView: View {
    @ObservedObject var viewModel: BackgroundRefreshSettingsViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var forceRefresh = false
    @State private var timer: Timer?

    @ObservedObject var bleManager = BLEManager.shared

    @State private var batteryPercentage: Int = 0

    var body: some View {
        NavigationView {
            Form {
                refreshTypeSection

                if viewModel.backgroundRefreshType.isBluetooth {
                    selectedDeviceSection
                    availableDevicesSection
                }
            }
            .navigationBarTitle("Background Refresh Settings", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                startTimer()
            }
            .onDisappear {
                stopTimer()
            }
        }
    }

    // MARK: - Subviews / Computed Properties

    private var refreshTypeSection: some View {
        Section {
            Picker("Background Refresh Type", selection: $viewModel.backgroundRefreshType) {
                ForEach(BackgroundRefreshType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(MenuPickerStyle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Adjust the background refresh type.")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                switch viewModel.backgroundRefreshType {
                case .none:
                    Text("No background refresh. Alarms and updates will not work unless the app is open in the foreground.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                case .silentTune:
                    Text("A silent tune will play in the background, keeping the app active. May be interrupted by other apps. Allows continuous updates but consumes more battery.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                case .rileyLink:
                    Text("Requires a RileyLink-compatible device within Bluetooth range. Provides updates once per minute and uses less battery than the silent tune method.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                case .dexcom:
                    Text("Requires a Dexcom G6/ONE/G7/ONE+ transmitter within Bluetooth range. Provides updates every 5 minutes and uses less battery than the silent tune method.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var selectedDeviceSection: some View {
        if let storedDevice = bleManager.getSelectedDevice() {
            Section(header: Text("Selected Device")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(storedDevice.name ?? "Unknown Device")
                            .font(.headline)
                        
                        // ✅ Battery Indicator (if battery level is available)
                        if let batteryLevel = storedDevice.batteryLevel {
                            let batterySymbol = getBatterySymbol(batteryLevel: batteryLevel)
                            let batteryColor = getBatteryColor(batteryLevel: batteryLevel)
                            
                            Spacer()
                            
                            ZStack {
                                Image(systemName: batterySymbol) // Fills inside dynamically
                                    .foregroundColor(batteryColor) // Conditional color
                                    .font(.title2)
                                
                                Image(systemName: "battery.0percent") // Always shows a battery outline
                                    .foregroundColor(.primary) // Keeps the outline in label color
                                    .font(.title2)
                                
                                Text("\(batteryLevel) ")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                    .scaleEffect(0.85)
                            }
                        }
                    }
                    
                    deviceConnectionStatus(for: storedDevice)
                    
                    if storedDevice.rssi != 0 {
                        Text("RSSI: \(storedDevice.rssi) dBm")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                    
                    // ✅ Show Sensor Activation Date (if found)
                    if let sensorID = storedDevice.name,
                       let activationDate = Storage.shared.latestActivationDate(for: sensorID) {
                        Text("Activated: \(activationDate)")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                    
                    if let offset = BLEManager.shared.expectedSensorFetchOffsetString(for: storedDevice) {
                        
                        
                        Text("Expected bg delay: \(offset)")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                    
                    HStack {
                        Spacer()
                        Button(action: {
                            bleManager.disconnect()
                        }) {
                            Text("Disconnect")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        Spacer()
                    }
                }
                .padding(.vertical, 8)
            }
            .id(forceRefresh)
        }
    }

    private func formattedTimeString(from seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds)) seconds"
        } else {
            let minutes = Int(seconds / 60)
            let seconds = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes):\(String(format: "%02d", seconds)) minutes"
        }
    }

    private var availableDevicesSection: some View {
        Section(header: scanningStatusHeader) {
            BLEDeviceSelectionView(
                bleManager: bleManager,
                selectedFilter: viewModel.backgroundRefreshType,
                onSelectDevice: { device in
                    bleManager.connect(device: device)
                }
            )
        }
    }

    private var scanningStatusHeader: some View {
        Text("Scanning for \(viewModel.backgroundRefreshType.rawValue)...")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }

    private func deviceConnectionStatus(for device: BLEDevice) -> some View {
        let expectedConnectionTime: TimeInterval = bleManager.expectedHeartbeatInterval() ?? 300
        let now = Date()
        let timeSinceLastConnection = device.isConnected ? 0 : now.timeIntervalSince(device.lastConnected ?? now)

        if device.isConnected {
            return Text("Connected")
                .foregroundColor(.green)
        } else if let lastConnected = device.lastConnected {
            let timeRatio = timeSinceLastConnection / expectedConnectionTime
            let timeString = formattedTimeString(from: timeSinceLastConnection)

            if timeRatio < 1.0 {
                return Text("Disconnected for \(timeString)")
                    .foregroundColor(.green)
            } else if timeRatio <= 1.15 {
                return Text("Disconnected for \(timeString)")
                    .foregroundColor(.orange)
            } else if timeRatio <= 3.0 {
                return Text("Disconnected for \(timeString)")
                    .foregroundColor(.red)
            } else {
                let date = dateTimeUtils.formattedDate(from: lastConnected)
                return Text("Last connection: \(date)")
                    .foregroundColor(.red)
            }
        } else {
            return Text("Reconnecting...")
                .foregroundColor(.orange)
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.forceRefresh.toggle()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// ✅ Get SF Symbol based on battery level
    private func getBatterySymbol(batteryLevel: Int) -> String {
        switch batteryLevel {
        case 90...100:
            return "battery.100percent"
        case 70...89:
            return "battery.75percent"
        case 50...69:
            return "battery.50percent"
        case 20...49:
            return "battery.25percent"
        default:
            return "battery.0percent"
        }
    }

    /// ✅ Get battery color based on level
    private func getBatteryColor(batteryLevel: Int) -> Color {
        switch batteryLevel {
        case 50...100:
            return .green
        case 20...49:
            return .orange
        default:
            return .red
        }
    }
}
