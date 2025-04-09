//
//  SyncNewSensorView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-04-09.
//

import SwiftUI
import Combine

// Global bgData – updated by your Nightscout BG data logic.
var bgData: [ShareGlucoseData] = []

struct SyncNewSensorView: View {
    // Updated with the timestamp from the latest Nightscout BG reading.
    @State private var lastBG: Date = Date()
    
    // First button countdown: 60-second mode (for sensor sync).
    @State private var sensorSecondsSync: Int = 60
    
    // Second button pairing countdown: 300-second mode.
    @State private var pairingCountdown: Int = 300
    
    // Timer publisher fires every second.
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    // Offset values as per your requirements:
    let sensorOffset: Int = 15    // For the first button countdown.
    let pairingOffset: Int = 30   // For the pairing countdown.
    
    // MARK: - Countdown Calculations
    
    /// Computes the initial offset for the 60-second cycle based on lastBG.
    /// Formula: (lastBGSeconds – sensorOffset + 60) mod 60.
    private var initialOffset: Int {
        let lastBGSeconds = Calendar.current.component(.second, from: lastBG)
        let offset = (lastBGSeconds - sensorOffset + 60) % 60
        print("DEBUG: [initialOffset] lastBG seconds = \(lastBGSeconds), computed sensor offset = \(offset)")
        return offset
    }
    
    /// Calculates the sensor sync countdown (60-second cycle).
    private func calculateSensorCountdown(for current: Date) -> Int {
        let currentSecond = Calendar.current.component(.second, from: current)
        let elapsed = (currentSecond - initialOffset + 60) % 60
        let countdown = 60 - elapsed
        print("DEBUG: [calculateSensorCountdown] currentSecond = \(currentSecond), elapsed = \(elapsed), sensor countdown = \(countdown)")
        return countdown
    }
    
    /// Calculates the pairing countdown (300-second cycle) using lastBG and pairingOffset.
    private func calculatePairingCountdown(for current: Date) -> Int {
        let cycle = 300  // Total seconds in the cycle.
        
        // Use the full timestamp modulo cycle.
        let lastBGTime = Int(lastBG.timeIntervalSince1970)
        let lastBGCycle = lastBGTime % cycle
        // Compute offset for pairing: subtract pairingOffset and wrap.
        let offset = (lastBGCycle - pairingOffset + cycle) % cycle
        
        let currentTime = Int(current.timeIntervalSince1970)
        let currentCycle = currentTime % cycle
        let elapsed = (currentCycle - offset + cycle) % cycle
        let countdown = cycle - elapsed
        print("DEBUG: [calculatePairingCountdown] currentCycle = \(currentCycle), lastBGCycle = \(lastBGCycle), offset = \(offset), pairing countdown = \(countdown)")
        return countdown
    }
    
    /// Formats a number of seconds into a "MM:SS" string.
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
    
    // MARK: - NS BG Data Fetching (Once on View Appear)
    
    /// Replicates your Nightscout BG fetch logic.
    /// Fetches NS BG data once when the view appears, converts timestamps, sorts data,
    /// updates global bgData, and sets lastBG to the timestamp from the newest reading (data[0]).
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
        parameters["find[type][$ne]"] = "cal"  // Exclude calibration entries.
        
        print("DEBUG: [fetchNSBGData] Fetching NS BG data with parameters: \(parameters)")
        
        NightscoutUtils.executeRequest(eventType: .sgv, parameters: parameters) { (result: Result<[ShareGlucoseData], Error>) in
            switch result {
            case .success(let entriesResponse):
                var nsData = entriesResponse
                DispatchQueue.main.async {
                    // Convert NS timestamps from milliseconds to seconds.
                    for i in 0..<nsData.count {
                        nsData[i].date /= 1000
                        nsData[i].date.round(FloatingPointRoundingRule.toNearestOrEven)
                    }
                    // Sort so that the newest reading is first.
                    nsData.sort { $0.date > $1.date }
                    
                    // Update global bgData.
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
                // Optionally, schedule a retry here.
            }
        }
    }
    
    /// Updates lastBG using the available bgData.
    private func updateLatestBG() {
        if !bgData.isEmpty {
            let latestReading = bgData[0]  // Use the first (newest) element.
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
            VStack(spacing: 40) {
                // First large button – sensor sync countdown (60-second cycle).
                Button(action: {
                    // Implement sensor sync action.
                }) {
                    VStack {
                        Text("Skjut fast ny sensor om:")
                            .font(.title2)
                            .multilineTextAlignment(.center)
                        Text("\(sensorSecondsSync) sekunder")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                
                // Second large button – new sensor pairing countdown (300-second cycle).
                Button(action: {
                    // Implement pairing action.
                }) {
                    VStack {
                        Text("Parkoppla ny sensor om:")
                            .font(.title2)
                            .multilineTextAlignment(.center)
                        Text("\(formatTime(pairingCountdown))")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Synka ny sensor")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Klar") {
                        // Add dismissal logic.
                    }
                }
            }
            .onAppear {
                print("DEBUG: [onAppear] SyncNewSensorView onAppear triggered")
                // Fetch NS BG data once when the view appears.
                fetchNSBGData()
                
                // Log the current state of lastBG.
                let bgSec = Calendar.current.component(.second, from: lastBG)
                print("DEBUG: [onAppear] lastBG after NS fetch: \(lastBG) (seconds: \(bgSec))")
                
                // Initialize both countdowns.
                sensorSecondsSync = calculateSensorCountdown(for: Date())
                pairingCountdown = calculatePairingCountdown(for: Date())
                print("DEBUG: [onAppear] Initialized sensor countdown: \(sensorSecondsSync) sec, pairing countdown: \(formatTime(pairingCountdown))")
            }
            .onReceive(timer) { currentTime in
                // Update only the countdowns (do not fetch NS data every second).
                sensorSecondsSync = calculateSensorCountdown(for: currentTime)
                pairingCountdown = calculatePairingCountdown(for: currentTime)
            }
        }
    }
}

