//
//  SyncNewSensorView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-04-09.
//

import SwiftUI
import Combine
import AudioToolbox

// Global bgData – updated by your Nightscout BG data logic.
var bgData: [ShareGlucoseData] = []

struct SyncNewSensorView: View {
    // MARK: – Environment
        @Environment(\.presentationMode) private var presentationMode

        // MARK: – BG & pairing state
        @State private var lastBG: Date = Date()
        @State private var pairingCountdown: Int = 300
        @State private var pairingPaused: Bool = true
        @State private var pairingPauseStart: Date? = nil
        @State private var pairingPauseAdjustment: TimeInterval = 0

        // Now mutable via UI
        /// Offset for how many seconds before the current sensor heartbeat the insert sensor countdown should aim towards
        /// Maybe needs to be tweaked, but initial findings indicates that the sensor needs ~183 s extra during warmup before the 300 s cycle starts, ie 153 s offset should give an effective offset of -30 s between the new sensor readings and the old sensor that will be used as heartbeat in LF
        // Persist these values through UserDefaultsRepository
        @State private var pairingOffset: Int = UserDefaultsRepository.pairingOffset.value
        @State private var offsetString: String = UserDefaultsRepository.offsetString.value
        @State private var lastValidOffset: Int = UserDefaultsRepository.pairingOffset.value
        @State private var showOffsetError: Bool = false

        // For pairing countdown sounds
        @State private var prevPairingCountdown: Int = 300
    
    // Timer publisher: fires every second.
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    

    
    // MARK: - Countdown Calculations

    /// Calculates pairing countdown (300-sec cycle) based on lastBG.
    private func calculatePairingCountdown(for current: Date) -> Int {
        let cycle = 300
        let effectiveTime = current.addingTimeInterval(pairingPauseAdjustment)
        
        let lastBGTime = Int(lastBG.timeIntervalSince1970)
        let lastBGCycle = lastBGTime % cycle
        let offset = (lastBGCycle - pairingOffset - 123 + cycle) % cycle
        
        let currentTime = Int(effectiveTime.timeIntervalSince1970)
        let currentCycle = currentTime % cycle
        let elapsed = (currentCycle - offset + cycle) % cycle
        let countdown = cycle - elapsed
        LogManager.shared.log(category: .dexcom, message: "DEBUG: [calculatePairingCountdown] currentCycle = \(currentCycle), lastBGCycle = \(lastBGCycle), offset = \(offset), pairing countdown = \(countdown)", isDebug: true)
        return countdown
    }
    
    // MARK: - Sound Playback
    
    private func playBeep() {
        AudioServicesPlaySystemSound(1057)
    }
    
    private func playFinalBeep() {
        AudioServicesPlaySystemSound(1013)
    }
    
    // For pairing countdown sounds.
    private func checkPairingSounds(with countdown: Int) {
        if countdown >= 1 && countdown <= 5 && countdown != prevPairingCountdown {
            if countdown == 1 {
                playFinalBeep()
            } else {
                playBeep()
            }
        }
        prevPairingCountdown = countdown
    }
    
    // MARK: - Pause/Resume per Button
    
    private func togglePairingPause() {
        if pairingPaused {
            // Resuming pairing countdown.
            if let pauseStart = pairingPauseStart {
                let pauseDuration = Date().timeIntervalSince(pauseStart)
                pairingPauseAdjustment += pauseDuration
                LogManager.shared.log(category: .dexcom, message: "DEBUG: [togglePairingPause] Resuming pairing after pause \(pauseDuration) sec. Total adjustment = \(pairingPauseAdjustment)", isDebug: true)
            }
            pairingPaused = false
            pairingPauseStart = nil
        } else {
            // Pausing pairing countdown.
            pairingPauseStart = Date()
            pairingPaused = true
            LogManager.shared.log(category: .dexcom, message: "DEBUG: [togglePairingPause] Pairing countdown paused at \(pairingPauseStart!)", isDebug: true)
        }
    }
    
    // MARK: - NS BG Data Fetching
    
    private func fetchNSBGData() {
        guard IsNightscoutEnabled() else {
            LogManager.shared.log(category: .dexcom, message: "DEBUG: [fetchNSBGData] Nightscout is disabled.", isDebug: true)
            return
        }
        
        var parameters: [String: String] = [:]
        let utcISODateFormatter = ISO8601DateFormatter()
        guard let startDate = Calendar.current.date(byAdding: .day,
                                                      value: -1 * UserDefaultsRepository.downloadDays.value,
                                                      to: Date()) else {
            LogManager.shared.log(category: .dexcom, message: "DEBUG: [fetchNSBGData] Failed to calculate startDate.", isDebug: true)
            return
        }
        parameters["count"] = "\(UserDefaultsRepository.downloadDays.value * 2 * 24 * 60 / 5)"
        parameters["find[dateString][$gte]"] = utcISODateFormatter.string(from: startDate)
        parameters["find[type][$ne]"] = "cal"
        
        LogManager.shared.log(category: .dexcom, message: "DEBUG: [fetchNSBGData] Fetching NS BG data with parameters: \(parameters)", isDebug: true)
        
        NightscoutUtils.executeRequest(eventType: .sgv, parameters: parameters) { (result: Result<[ShareGlucoseData], Error>) in
            switch result {
            case .success(let entriesResponse):
                var nsData = entriesResponse
                DispatchQueue.main.async {
                    for i in 0..<nsData.count {
                        nsData[i].date /= 1000
                        nsData[i].date.round(FloatingPointRoundingRule.toNearestOrEven)
                    }
                    nsData.sort { $0.date > $1.date }
                    bgData = nsData
                    if let latest = nsData.first {
                        let newLastBG = Date(timeIntervalSince1970: latest.date)
                        self.lastBG = newLastBG
                        let bgSeconds = Calendar.current.component(.second, from: newLastBG)
                        LogManager.shared.log(category: .dexcom, message: "DEBUG: [fetchNSBGData] Fetched \(nsData.count) entries. Latest reading at \(newLastBG) (seconds: \(bgSeconds))", isDebug: true)
                    } else {
                        LogManager.shared.log(category: .dexcom, message: "DEBUG: [fetchNSBGData] NS data is empty after processing.", isDebug: true)
                    }
                }
            case .failure(let error):
                LogManager.shared.log(category: .dexcom, message: "DEBUG: [fetchNSBGData] Failed to fetch NS BG data: \(error)", isDebug: true)
            }
        }
    }
    
    private func updateLatestBG() {
        if !bgData.isEmpty {
            let latestReading = bgData[0]
            let newLastBG = Date(timeIntervalSince1970: latestReading.date)
            LogManager.shared.log(category: .dexcom, message: "DEBUG: [updateLatestBG] Latest reading from bgData[0]: \(newLastBG)", isDebug: true)
            if newLastBG != lastBG {
                DispatchQueue.main.async {
                    self.lastBG = newLastBG
                    let bgSeconds = Calendar.current.component(.second, from: newLastBG)
                    LogManager.shared.log(category: .dexcom, message: "DEBUG: [updateLatestBG] Updated lastBG to: \(newLastBG) (seconds: \(bgSeconds))", isDebug: true)
                }
            } else {
                let bgSeconds = Calendar.current.component(.second, from: lastBG)
                LogManager.shared.log(category: .dexcom, message: "DEBUG: [updateLatestBG] lastBG remains unchanged: \(lastBG) (seconds: \(bgSeconds))", isDebug: true)
            }
        } else {
            LogManager.shared.log(category: .dexcom, message: "DEBUG: [updateLatestBG] No BG data available; retaining previous lastBG: \(lastBG)", isDebug: true)
        }
    }
    
    // MARK: - View Body
    
    var body: some View {
            NavigationView {
                VStack(spacing: 20) {
                    // Pairing countdown button
                    Button(action: togglePairingPause) {
                        VStack {
                            if pairingPaused {
                                Text("Skjut fast ny sensor")
                                    .font(.title)
                                    .padding(.bottom, 2)
                                    .foregroundColor(.gray)
                                Text("Starta nedräkning")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.gray)
                            } else {
                                Text("Skjut fast ny sensor om:")
                                    .font(.title)
                                    .padding(.bottom, 2)
                                    .foregroundColor(.primary)
                                Text("\(pairingCountdown) sekunder")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 90)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }

                    // Explanation text
                    Text("""
                    'Skjut fast ny sensor'-nedräkningen hjälper dig att initiera parkopplingen med den nya sensorn i dexcomappen vid exakt rätt ögonblick. Efter parkopplingen kommer den nya sensorn att skicka ett heartbeat var 5e minut. Genom att tajma offseten noggrant, så kommer du kunna använda den gamla sensorn som heartbeat för att väcka Loop Follow och hämta nya data från Nightscout med minimal fördröjning.\n\n Justera offset nedan till hur många sekunder tidigare du vill att den nya sensorn du skjuter fast ska skicka sin heartbeat vs när den nuvarande sensorn skickar sitt heartbeat (Standard 30s). \n\nExempel: Om du vill att heartbeat ska ske samma sekund som den gamla sätter du offset till 0s. Om du vill att heartbeat ska ske 30s efter den gamla sätter du offset till 270s.
                    """)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                    HStack {
                        Text("Justera offset (sekunder):")
                        Spacer()
                        TextField("", text: $offsetString)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 60)
                            .textFieldStyle(PlainTextFieldStyle())
                            .background(Color.clear)
                            .onChange(of: offsetString) { newValue in
                                if let val = Int(newValue) {
                                    if (0...299).contains(val) {
                                        // valid: update both offset and lastValid
                                        pairingOffset = val
                                        UserDefaultsRepository.pairingOffset.value = val
                                        UserDefaultsRepository.offsetString.value = "\(val)"
                                        lastValidOffset = val
                                        pairingCountdown = calculatePairingCountdown(for: Date())
                                    } else {
                                        // too big: revert & show error
                                        offsetString = "\(lastValidOffset)"
                                        showOffsetError = true
                                    }
                                } else if newValue.isEmpty {
                                    // user clearing out field: do nothing yet
                                } else {
                                    // non‑numeric: revert & show error
                                    offsetString = "\(lastValidOffset)"
                                    showOffsetError = true
                                }
                            }
                            .alert("Felaktig offset", isPresented: $showOffsetError) {
                                Button("OK", role: .cancel) { }
                            } message: {
                                Text("\nAnge en offset mellan 0-299 sekunder")
                            }
                    }
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                    Spacer()
                }
                .padding()
                .navigationTitle("Synka heartbeat för ny sensor")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Klar") {
                            // Dismiss the modal
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
                .onAppear {
                    LogManager.shared.log(category: .dexcom, message: "DEBUG: [onAppear] SyncNewSensorView onAppear triggered", isDebug: true)
                    fetchNSBGData()
                    let bgSec = Calendar.current.component(.second, from: lastBG)
                    LogManager.shared.log(category: .dexcom, message: "DEBUG: [onAppear] lastBG after NS fetch: \(lastBG) (seconds: \(bgSec))", isDebug: true)
                    
                    pairingCountdown = calculatePairingCountdown(for: Date())
                    LogManager.shared.log(category: .dexcom, message: "DEBUG: [onAppear] Initialized sensor countdown: \(pairingCountdown)", isDebug: true)
                }
                .onReceive(timer) { currentTime in
                    if !pairingPaused {
                        pairingCountdown = calculatePairingCountdown(for: currentTime)
                        checkPairingSounds(with: pairingCountdown)
                    }
                }
            }
        }
    }
