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
        /// Offset for how many seconds before the curretn sensor heartbeat the insert sensor countdown should aim towards
        /// Maybe needs to be tweaked, but initial findings indicates that the sensor needs 180 s extra during warmup before the 300 s cycle starts, ie 150 s offset should give an effective offset of -30 s between the new sensor readings and the old sensor that will be used as heartbeat in LF
        @State private var pairingOffset: Int = 30
        @State private var offsetString: String = "30"
        @State private var lastValidOffset: Int = 30
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
        let offset = (lastBGCycle - pairingOffset - 120 + cycle) % cycle
        
        let currentTime = Int(effectiveTime.timeIntervalSince1970)
        let currentCycle = currentTime % cycle
        let elapsed = (currentCycle - offset + cycle) % cycle
        let countdown = cycle - elapsed
        //print("DEBUG: [calculatePairingCountdown] currentCycle = \(currentCycle), lastBGCycle = \(lastBGCycle), offset = \(offset), pairing countdown = \(countdown)")
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
                print("DEBUG: [togglePairingPause] Resuming pairing after pause \(pauseDuration) sec. Total adjustment = \(pairingPauseAdjustment)")
            }
            pairingPaused = false
            pairingPauseStart = nil
        } else {
            // Pausing pairing countdown.
            pairingPauseStart = Date()
            pairingPaused = true
            print("DEBUG: [togglePairingPause] Pairing countdown paused at \(pairingPauseStart!)")
        }
    }
    
    // MARK: - NS BG Data Fetching
    
    private func fetchNSBGData() {
        guard IsNightscoutEnabled() else {
            print("DEBUG: [fetchNSBGData] Nightscout is disabled.")
            return
        }
        
        var parameters: [String: String] = [:]
        let utcISODateFormatter = ISO8601DateFormatter()
        guard let startDate = Calendar.current.date(byAdding: .day,
                                                      value: -1 * UserDefaultsRepository.downloadDays.value,
                                                      to: Date()) else {
            print("DEBUG: [fetchNSBGData] Failed to calculate startDate.")
            return
        }
        parameters["count"] = "\(UserDefaultsRepository.downloadDays.value * 2 * 24 * 60 / 5)"
        parameters["find[dateString][$gte]"] = utcISODateFormatter.string(from: startDate)
        parameters["find[type][$ne]"] = "cal"
        
        print("DEBUG: [fetchNSBGData] Fetching NS BG data with parameters: \(parameters)")
        
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
                        print("DEBUG: [fetchNSBGData] Fetched \(nsData.count) entries. Latest reading at \(newLastBG) (seconds: \(bgSeconds))")
                    } else {
                        print("DEBUG: [fetchNSBGData] NS data is empty after processing.")
                    }
                }
            case .failure(let error):
                print("DEBUG: [fetchNSBGData] Failed to fetch NS BG data: \(error)")
            }
        }
    }
    
    private func updateLatestBG() {
        if !bgData.isEmpty {
            let latestReading = bgData[0]
            let newLastBG = Date(timeIntervalSince1970: latestReading.date)
            print("DEBUG: [updateLatestBG] Latest reading from bgData[0]: \(newLastBG)")
            if newLastBG != lastBG {
                DispatchQueue.main.async {
                    self.lastBG = newLastBG
                    let bgSeconds = Calendar.current.component(.second, from: newLastBG)
                    print("DEBUG: [updateLatestBG] Updated lastBG to: \(newLastBG) (seconds: \(bgSeconds))")
                }
            } else {
                let bgSeconds = Calendar.current.component(.second, from: lastBG)
                print("DEBUG: [updateLatestBG] lastBG remains unchanged: \(lastBG) (seconds: \(bgSeconds))")
            }
        } else {
            print("DEBUG: [updateLatestBG] No BG data available; retaining previous lastBG: \(lastBG)")
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
                    'Skjut fast ny sensor'-nedräkningen hjälper dig att initiera parkopplingen med den nya sensorn i dexcomappen vid exakt rätt ögonblick. Efter parkopplingen kommer den nya sensorn att skicka ett heartbeat var 5e minut. Genom att tajma offseten noggrant, så kommer du kunna använda den gamla sensorn som heartbeat för att väcka Loop Follow och hämta nya data från Nightscout med minimal fördröjning.\n\n Justera offset nedan till hur många sekunder tidigare du vill att den nya sensorn du skjuter fast ska skicka sin heartbeat vs när den nuvarande sensorn skickar sitt heartbeat (Standard 30s).
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
                    print("DEBUG: [onAppear] SyncNewSensorView onAppear triggered")
                    fetchNSBGData()
                    let bgSec = Calendar.current.component(.second, from: lastBG)
                    print("DEBUG: [onAppear] lastBG after NS fetch: \(lastBG) (seconds: \(bgSec))")
                    
                    pairingCountdown = calculatePairingCountdown(for: Date())
                    print("DEBUG: [onAppear] Initialized sensor countdown: \(pairingCountdown)")
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

/*
 
 import SwiftUI
 import Combine
 import AudioToolbox

 // Global bgData – updated by your Nightscout BG data logic.
 var bgData: [ShareGlucoseData] = []

 struct SyncNewSensorView: View {
     // Updated with the timestamp from the latest Nightscout BG reading.
     @State private var lastBG: Date = Date()
     
     // Sensor sync countdown (60-second cycle) state.
     @State private var sensorSecondsSync: Int = 60
     @State private var sensorPaused: Bool = true
     @State private var sensorPauseStart: Date? = nil
     @State private var sensorPauseAdjustment: TimeInterval = 0
     
     // Pairing countdown (300-second cycle) state.
     @State private var pairingCountdown: Int = 300
     @State private var pairingPaused: Bool = true
     @State private var pairingPauseStart: Date? = nil
     @State private var pairingPauseAdjustment: TimeInterval = 0
     
     // Timer publisher: fires every second.
     let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
     
     // Offsets: for sensor sync use 15 sec; for pairing use 30 sec.
     let sensorOffset: Int = 15
     let pairingOffset: Int = 30
     
     // MARK: - Countdown Calculations

     /// Calculates sensor sync countdown (60-sec cycle) based on lastBG.
     private var sensorInitialOffset: Int {
         let lastBGSeconds = Calendar.current.component(.second, from: lastBG)
         let offset = (lastBGSeconds - sensorOffset + 60) % 60
         //print("DEBUG: [sensorInitialOffset] lastBG seconds = \(lastBGSeconds), computed sensor offset = \(offset)")
         return offset
     }

     private func calculateSensorCountdown(for current: Date) -> Int {
         let effectiveTime = current.addingTimeInterval(sensorPauseAdjustment)
         let currentSecond = Calendar.current.component(.second, from: effectiveTime)
         let elapsed = (currentSecond - sensorInitialOffset + 60) % 60
         let countdown = 60 - elapsed
         //print("DEBUG: [calculateSensorCountdown] currentSecond = \(currentSecond), elapsed = \(elapsed), sensor countdown = \(countdown)")
         return countdown
     }

     /// Calculates pairing countdown (300-sec cycle) based on lastBG.
     private func calculatePairingCountdown(for current: Date) -> Int {
         let cycle = 300
         let effectiveTime = current.addingTimeInterval(pairingPauseAdjustment)
         
         let lastBGTime = Int(lastBG.timeIntervalSince1970)
         let lastBGCycle = lastBGTime % cycle
         let offset = (lastBGCycle - pairingOffset + cycle) % cycle
         
         let currentTime = Int(effectiveTime.timeIntervalSince1970)
         let currentCycle = currentTime % cycle
         let elapsed = (currentCycle - offset + cycle) % cycle
         let countdown = cycle - elapsed
         //print("DEBUG: [calculatePairingCountdown] currentCycle = \(currentCycle), lastBGCycle = \(lastBGCycle), offset = \(offset), pairing countdown = \(countdown)")
         return countdown
     }
     
     // MARK: - Sound Playback
     
     private func playBeep() {
         AudioServicesPlaySystemSound(1057)
     }
     
     private func playFinalBeep() {
         AudioServicesPlaySystemSound(1013)
     }
     
     // For sensor countdown sounds.
     @State private var prevSensorCountdown: Int = 60
     private func checkSensorSounds(with countdown: Int) {
         // Check for the last 5 seconds (1 to 5) and compare with the previous countdown value.
         if countdown >= 1 && countdown <= 5 && countdown != prevSensorCountdown {
             if countdown == 1 {
                 playFinalBeep()
             } else {
                 playBeep()
             }
         }
         prevSensorCountdown = countdown
     }

     // For pairing countdown sounds.
     @State private var prevPairingCountdown: Int = 300
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
     
     private func toggleSensorPause() {
         if sensorPaused {
             // Resuming sensor countdown.
             if let pauseStart = sensorPauseStart {
                 let pauseDuration = Date().timeIntervalSince(pauseStart)
                 sensorPauseAdjustment += pauseDuration
                 print("DEBUG: [toggleSensorPause] Resuming sensor after pause \(pauseDuration) sec. Total adjustment = \(sensorPauseAdjustment)")
             }
             sensorPaused = false
             sensorPauseStart = nil
         } else {
             // Pausing sensor countdown.
             sensorPauseStart = Date()
             sensorPaused = true
             print("DEBUG: [toggleSensorPause] Sensor countdown paused at \(sensorPauseStart!)")
         }
     }
     
     private func togglePairingPause() {
         if pairingPaused {
             // Resuming pairing countdown.
             if let pauseStart = pairingPauseStart {
                 let pauseDuration = Date().timeIntervalSince(pauseStart)
                 pairingPauseAdjustment += pauseDuration
                 print("DEBUG: [togglePairingPause] Resuming pairing after pause \(pauseDuration) sec. Total adjustment = \(pairingPauseAdjustment)")
             }
             pairingPaused = false
             pairingPauseStart = nil
         } else {
             // Pausing pairing countdown.
             pairingPauseStart = Date()
             pairingPaused = true
             print("DEBUG: [togglePairingPause] Pairing countdown paused at \(pairingPauseStart!)")
         }
     }
     
     // MARK: - NS BG Data Fetching
     
     private func fetchNSBGData() {
         guard IsNightscoutEnabled() else {
             print("DEBUG: [fetchNSBGData] Nightscout is disabled.")
             return
         }
         
         var parameters: [String: String] = [:]
         let utcISODateFormatter = ISO8601DateFormatter()
         guard let startDate = Calendar.current.date(byAdding: .day,
                                                       value: -1 * UserDefaultsRepository.downloadDays.value,
                                                       to: Date()) else {
             print("DEBUG: [fetchNSBGData] Failed to calculate startDate.")
             return
         }
         parameters["count"] = "\(UserDefaultsRepository.downloadDays.value * 2 * 24 * 60 / 5)"
         parameters["find[dateString][$gte]"] = utcISODateFormatter.string(from: startDate)
         parameters["find[type][$ne]"] = "cal"
         
         print("DEBUG: [fetchNSBGData] Fetching NS BG data with parameters: \(parameters)")
         
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
                         print("DEBUG: [fetchNSBGData] Fetched \(nsData.count) entries. Latest reading at \(newLastBG) (seconds: \(bgSeconds))")
                     } else {
                         print("DEBUG: [fetchNSBGData] NS data is empty after processing.")
                     }
                 }
             case .failure(let error):
                 print("DEBUG: [fetchNSBGData] Failed to fetch NS BG data: \(error)")
             }
         }
     }
     
     private func updateLatestBG() {
         if !bgData.isEmpty {
             let latestReading = bgData[0]
             let newLastBG = Date(timeIntervalSince1970: latestReading.date)
             print("DEBUG: [updateLatestBG] Latest reading from bgData[0]: \(newLastBG)")
             if newLastBG != lastBG {
                 DispatchQueue.main.async {
                     self.lastBG = newLastBG
                     let bgSeconds = Calendar.current.component(.second, from: newLastBG)
                     print("DEBUG: [updateLatestBG] Updated lastBG to: \(newLastBG) (seconds: \(bgSeconds))")
                 }
             } else {
                 let bgSeconds = Calendar.current.component(.second, from: lastBG)
                 print("DEBUG: [updateLatestBG] lastBG remains unchanged: \(lastBG) (seconds: \(bgSeconds))")
             }
         } else {
             print("DEBUG: [updateLatestBG] No BG data available; retaining previous lastBG: \(lastBG)")
         }
     }
     
     // MARK: - View Body
     
     var body: some View {
             NavigationView {
                 VStack(spacing: 20) {
                     // First button: Sensor sync countdown (60-sec cycle).
                     Button(action: {
                         toggleSensorPause()
                     }) {
                         VStack {
                             if sensorPaused {
                                 Text("1. Skjut fast ny sensor")
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
                                 Text("\(sensorSecondsSync) sekunder")
                                     .font(.largeTitle)
                                     .fontWeight(.bold)
                                     .foregroundColor(.primary)
                             }
                         }
                         .multilineTextAlignment(.center)
                         .frame(maxWidth: .infinity, minHeight: 90)
                         .padding()
                         .background(Color(.secondarySystemBackground))
                         .cornerRadius(12)
                     }
                     
                     // Footer text with explanation.
                     Text("""
                     Steg 1: 'Skjut fast ny sensor'-nedräkningen hjälper dig att hitta rätt offset mellan den nya sensorn du sätter och den nuvarande, om den nuvarande ska användas som heartbeat till Loop Follow efter att ha stoppats och avlägsnats från kroppen. Efter att sensorn har skjutits fast kommer den att skicka en BT-parningsförfrågan en gång i minuten. Detta första steg hjälper till att få parningsförfrågningen synkad till \(sensorOffset) sek innan den gamla sensorn skickar sin heartbeat.
                     """)
                     .font(.caption2)
                     .foregroundColor(.secondary)
                     .multilineTextAlignment(.center)
                     .padding(.bottom, 20)
                     
                     // Second button: Pairing countdown (300-sec cycle).
                     Button(action: {
                         togglePairingPause()
                     }) {
                         VStack {
                             if pairingPaused {
                                 Text("2. Parkoppla ny sensor")
                                     .font(.title)
                                     .padding(.bottom, 2)
                                     .foregroundColor(.gray)
                                 Text("Starta nedräkning")
                                     .font(.largeTitle)
                                     .fontWeight(.bold)
                                     .foregroundColor(.gray)
                             } else {
                                 Text("Parkoppla ny sensor om:")
                                     .font(.title)
                                     .padding(.bottom, 2)
                                     .foregroundColor(.primary)
                                 Text("\(pairingCountdown) sekunder")
                                     .font(.largeTitle)
                                     .fontWeight(.bold)
                                     .foregroundColor(.primary)
                             }
                         }
                         .multilineTextAlignment(.center)
                         .frame(maxWidth: .infinity, minHeight: 90)
                         .padding()
                         .background(Color(.secondarySystemBackground))
                         .cornerRadius(12)
                     }
                     
                     // Footer text with explanation.
                     Text("""
                     Steg 2: 'Parkoppla ny sensor'-nedräkningen hjälper dig att initiera parkopplingen med den nya sensorn i dexcomappen vid exakt rätt ögonblick. Efter parkopplingen kommer den nya sensorn att skicka ett heartbeat var 5e minut. Genom att tajma offseten noggrant i detta andra steg, så kommer du kunna använda den gamla sensorn som heartbeat för att väcka Loop Follow och hämta nya data från Nightscout med minimal fördröjning.
                     """)
                     .font(.caption2)
                     .foregroundColor(.secondary)
                     .multilineTextAlignment(.center)
                     
                     Spacer()
                 }
                 .padding()
                 .navigationTitle("Synka heartbeat för ny sensor")
                 .navigationBarTitleDisplayMode(.inline)
                 .toolbar {
                     ToolbarItem(placement: .navigationBarTrailing) {
                         Button("Klar") {
                             // Add dismissal logic.
                         }
                     }
                 }
                 .onAppear {
                     print("DEBUG: [onAppear] SyncNewSensorView onAppear triggered")
                     fetchNSBGData()
                     let bgSec = Calendar.current.component(.second, from: lastBG)
                     print("DEBUG: [onAppear] lastBG after NS fetch: \(lastBG) (seconds: \(bgSec))")
                     
                     sensorSecondsSync = calculateSensorCountdown(for: Date())
                     pairingCountdown = calculatePairingCountdown(for: Date())
                     print("DEBUG: [onAppear] Initialized sensor countdown: \(sensorSecondsSync) sec, pairing countdown: \(pairingCountdown)")
                 }
                 .onReceive(timer) { currentTime in
                     if !sensorPaused {
                         sensorSecondsSync = calculateSensorCountdown(for: currentTime)
                         checkSensorSounds(with: sensorSecondsSync)
                     }
                     if !pairingPaused {
                         pairingCountdown = calculatePairingCountdown(for: currentTime)
                         checkPairingSounds(with: pairingCountdown)
                     }
                 }
             }
         }
     }
 */

