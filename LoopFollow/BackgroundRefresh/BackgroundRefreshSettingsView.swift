//
//  BackgroundRefreshSettingsView.swift
//  LoopFollow
//

import SwiftUI

@available(iOS 16.0, *)
struct BackgroundRefreshSettingsView: View {
    @ObservedObject var viewModel: BackgroundRefreshSettingsViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var forceRefresh = false
    @State private var timer: Timer?
    @State private var showSyncNewSensorView: Bool = false
    @State private var minAgoNavText: String = ""
    @State private var minAgoNavShortText: String = ""
    @State private var showOffsetConfirmAlert: Bool = false
    @State private var pendingOffset: Int?

    @ObservedObject var bleManager = BLEManager.shared

    @State private var batteryPercentage: Int = 0
    
    // MARK: - Constants for BG delay thresholds
    let goodDelay = 90
    let okDelay = 180

    // MARK: - Constants for sensor age thresholds
    let manyDaysOld = 75

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // MARK: - Typ
                    Text("Välj metod för bakgrundsuppdateringar")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        themedRow {
                            Picker("Bakgrundsaktivitet Typ", selection: $viewModel.backgroundRefreshType) {
                                ForEach(BackgroundRefreshType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        Divider().opacity(0.35)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Välj typ av bakgrundsaktivitet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            switch viewModel.backgroundRefreshType {
                            case .none:
                                Text("No background refresh. Alarms and updates will not work unless the app is open in the foreground.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            case .silentTune:
                                Text("En tyst melodi spelas i bakgrunden, vilket håller appen aktiv. Den kan avbrytas av andra appar. Möjliggör kontinuerliga uppdateringar men förbrukar mer batteri.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            case .rileyLink:
                                Text("Kräver en RileyLink-kompatibel enhet inom Bluetooth-räckvidd. Ger uppdateringar en gång per minut och använder mindre batteri än metoden med tyst melodi.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            case .dexcom:
                                Text("Kräver en Dexcom G6/ONE/G7/ONE+ sändare inom Bluetooth-räckvidd. Ger uppdateringar var 5:e minut och använder mindre batteri än metoden med tyst melodi.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .themedCardBackground()

                    // MARK: - Vald enhet / Tillgängliga enheter
                    if viewModel.backgroundRefreshType.isBluetooth {
                        if let storedDevice = bleManager.getSelectedDevice() {
                            Text("Vald enhet")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)

                            VStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        let deviceName = storedDevice.name ?? "Okänd enhet"
                                        let isHitDevice: Bool = {
                                            guard viewModel.backgroundRefreshType == .dexcom,
                                                  let suggestion = bleManager.suggestedHeartbeatOffsetForNextSensor(optimalWindow: 40...60)
                                            else { return false }

                                            return hitDeviceIDs(for: suggestion.offset, optimalWindow: 40...60).contains(storedDevice.id)
                                        }()

                                        Text(isHitDevice ? "* \(deviceName)" : deviceName)
                                            .font(.headline)

                                        // Battery indicator
                                        if let batteryLevel = storedDevice.batteryLevel {
                                            let batterySymbol = getBatterySymbol(batteryLevel: batteryLevel)
                                            let batteryColor = getBatteryColor(batteryLevel: batteryLevel)

                                            Spacer()

                                            ZStack {
                                                Image(systemName: batterySymbol)
                                                    .foregroundColor(batteryColor)
                                                    .font(.title2)

                                                Image(systemName: "battery.0percent")
                                                    .foregroundColor(.primary)
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
                                            .foregroundStyle(.secondary)
                                            .font(.footnote)
                                    }

                                    if let sensorID = storedDevice.name,
                                       let activationDate = Storage.shared.latestActivationDate(for: sensorID) {
                                        Text("Aktiverades: \(activationDate)")
                                            .foregroundStyle(.secondary)
                                            .font(.footnote)
                                    }
                                    
                                    // Expected BG Delay with color logic (for Dexcom devices only)
                                    if Storage.shared.backgroundRefreshType.value == .dexcom,
                                       let offsetStr = BLEManager.shared.expectedSensorFetchOffsetString(for: storedDevice) {
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

                                    HStack {
                                        Spacer()
                                        Button("Koppla från") {
                                            bleManager.disconnect()
                                        }
                                        .foregroundColor(Color(uiColor: .systemBlue))
                                        .buttonStyle(.plain)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Spacer()
                                    }
                                    .padding(.top, 4)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                            .themedCardBackground()
                            .id(forceRefresh)
                        }

                        Text("Tillgängliga enheter")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)

                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Söker efter \(viewModel.backgroundRefreshType.rawValue)...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                BLEDeviceSelectionView(
                                    bleManager: bleManager,
                                    selectedFilter: viewModel.backgroundRefreshType,
                                    onSelectDevice: { device in
                                        bleManager.connect(device: device)
                                    }
                                )
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        .themedCardBackground()
                    }

                    // MARK: - Dexcom offset-suggestion
                    if viewModel.backgroundRefreshType == .dexcom {
                        Text("Optimal offset nästa sensorbyte")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)

                        VStack(spacing: 0) {
                            if #available(iOS 26.0, *) {
                                Button {
                                    if let suggestion = bleManager.suggestedHeartbeatOffsetForNextSensor(optimalWindow: 40...60) {
                                        // Store the suggested offset and show confirmation alert
                                        pendingOffset = suggestion.offset
                                        showOffsetConfirmAlert = true
                                    } else {
                                        // If we for some reason don't have a suggestion yet, keep the old behavior:
                                        // go straight to SyncNewSensorView so the user can adjust things manuellt.
                                        showSyncNewSensorView = true
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        if let suggestion = bleManager.suggestedHeartbeatOffsetForNextSensor(optimalWindow: 40...60) {
                                            Text("\(suggestion.offset) sekunder")
                                                .font(.headline)
                                                .frame(maxWidth: .infinity, alignment: .center)
                                            
                                            Text("Optimerar för 40–60 s fördröjning • träffar \(suggestion.matches)/\(suggestion.total) *")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .center)
                                            
                                            let hitIDs = hitDeviceIDs(for: suggestion.offset, optimalWindow: 40...60)
                                            let hitNames: [String] = bleManager.devices
                                                .filter { hitIDs.contains($0.id) }
                                                .compactMap { $0.name }
                                                .sorted()
                                            
                                            if !hitNames.isEmpty {
                                                Divider().opacity(0.35)
                                                    //.padding(.top, 6)
                                                
                                                VStack(alignment: .leading, spacing: 4) {
                                                    ForEach(hitNames, id: \.self) { name in
                                                        Text("* \(name)")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                                .frame(maxWidth: .infinity, alignment: .center)
                                                .padding(.top, 2)
                                            }
                                        } else {
                                            Text("Väntar på fler heartbeats…")
                                                .font(.headline)
                                                .frame(maxWidth: .infinity, alignment: .center)
                                            
                                            Text("Öppna vyn i ~5 minuter så hinner flera sensorer synas.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .center)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                }
                                .alert("Använd offset", isPresented: $showOffsetConfirmAlert) {
                                    Button("Fortsätt") {
                                        if let offset = pendingOffset {
                                            UserDefaultsRepository.pairingOffset.value = offset
                                            UserDefaultsRepository.offsetString.value = "\(offset)"
                                            showSyncNewSensorView = true
                                        }
                                        pendingOffset = nil
                                    }
                                    Button("Avbryt", role: .cancel) {
                                        pendingOffset = nil
                                    }
                                } message: {
                                    if let offset = pendingOffset {
                                        Text("Vill du använda \(offset) sekunder för nästa sensor-synk?")
                                    } else {
                                        Text("Vill du använda den föreslagna offseten för nästa sensor-synk?")
                                    }
                                }
                                .buttonStyle(.glass)
                                //.padding(.top, 14)
                                //.padding(.bottom, 30)
                                //.padding(.vertical, 12)
                            } else {
                                // Fallback on earlier versions
                            }
                        }
                        //.themedCardBackground()
                        .background(
                            Color(uiColor: .clear)
                        )
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
        .sheet(isPresented: $showSyncNewSensorView) {
            SyncNewSensorSheetContainer()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 6) {
                    Text(minAgoNavShortText.isEmpty ? "–" : minAgoNavShortText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .minAgoTextUpdated)) { notification in
            let text = notification.userInfo?["text"] as? String ?? ""
            let short = notification.userInfo?["short"] as? String ?? ""
            self.minAgoNavText = text
            self.minAgoNavShortText = short.isEmpty ? text : short
        }
    }


    private func formattedTimeString(from seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds)) sekunder"
        } else {
            let minutes = Int(seconds / 60)
            let seconds = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes):\(String(format: "%02d", seconds)) minuter"
        }
    }


    private func deviceConnectionStatus(for device: BLEDevice) -> some View {
        let expectedConnectionTime: TimeInterval = bleManager.expectedHeartbeatInterval() ?? 300
        let now = Date()
        let timeSinceLastConnection = device.isConnected ? 0 : now.timeIntervalSince(device.lastConnected ?? now)

        if device.isConnected {
            return Text("Ansluten")
                .foregroundColor(.green)
        } else if let lastConnected = device.lastConnected {
            let timeRatio = timeSinceLastConnection / expectedConnectionTime
            let timeString = formattedTimeString(from: timeSinceLastConnection)

            if timeRatio < 1.0 {
                return Text("Frånkopplad i \(timeString)")
                    .foregroundColor(.green)
            } else if timeRatio <= 1.15 {
                return Text("Frånkopplad i \(timeString)")
                    .foregroundColor(.orange)
            } else if timeRatio <= 3.0 {
                return Text("Frånkopplad i \(timeString)")
                    .foregroundColor(.red)
            } else {
                let date = dateTimeUtils.formattedDate(from: lastConnected)
                return Text("Senaste anslutning: \(date)")
                    .foregroundColor(.red)
            }
        } else {
            return Text("Återansluter...")
                .foregroundColor(.orange)
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
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


    @ViewBuilder
    private func themedRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .tint(Color(uiColor: .systemBlue))
    }
    
    private func hitDeviceIDs(for suggestionOffset: Int, optimalWindow: ClosedRange<Int>) -> Set<UUID> {
        // Only Dexcom devices participate in the 5-min cycle alignment.
        let dexcomDevices = bleManager.devices.filter { BackgroundRefreshType.dexcom.matches($0) }

        var hits = Set<UUID>()

        // Date formatter for activation dates ("yyyy-MM-dd HH:mm:ss")
        let formatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return df
        }()

        for device in dexcomDevices {
            // Exclude very old sensors (> manyDaysOld days) from being considered hits
            if let sensorID = device.name,
               let activationStr = Storage.shared.latestActivationDate(for: sensorID),
               let activationDate = formatter.date(from: activationStr) {

                let ageDays = Calendar.current.dateComponents([.day], from: activationDate, to: Date()).day ?? 0
                if ageDays > manyDaysOld {
                    continue
                }
            }

            guard let d = bleManager.expectedSensorFetchOffsetSeconds(for: device) else { continue }
            let shifted = (d + suggestionOffset) % 300
            if optimalWindow.contains(shifted) {
                hits.insert(device.id)
            }
        }
        return hits
    }
}
