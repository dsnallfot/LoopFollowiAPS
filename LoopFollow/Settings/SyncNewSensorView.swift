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
    
    // Countdown value for the sensor sync button.
    @State private var sensorSecondsSync: Int = 60
    
    // Timer publisher that fires every second.
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    let secondsOffset: Int = 15
    
    // MARK: - Countdown Calculation
    
    /// Computes the initial offset from lastBG in seconds.
    /// Calculation: (lastBGSeconds – secondsOffset + 60) mod 60.
    private var initialOffset: Int {
        let lastBGSeconds = Calendar.current.component(.second, from: lastBG)
        let offset = (lastBGSeconds - secondsOffset + 60) % 60
        print("DEBUG: [initialOffset] lastBG seconds = \(lastBGSeconds), computed offset = \(offset)")
        return offset
    }
    
    /// Computes the countdown based on the current time and the computed offset.
    private func calculateCountdown(for current: Date) -> Int {
        let currentSecond = Calendar.current.component(.second, from: current)
        let elapsed = (currentSecond - initialOffset + 60) % 60
        let countdown = 60 - elapsed
        print("DEBUG: [calculateCountdown] currentSecond = \(currentSecond), elapsed = \(elapsed), countdown = \(countdown)")
        return countdown
    }
    
    // MARK: - NS BG Data Fetching (Once on View Appear)
    
    /// Replicates your Nightscout BG fetch logic.
    /// It builds the same parameters, calls NightscoutUtils.executeRequest,
    /// converts the NS timestamps from milliseconds to seconds, sorts the data (newest first),
    /// updates global bgData and sets lastBG to the timestamp from the first (newest) reading.
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
        parameters["find[type][$ne]"] = "cal"  // Exclude calibration entries
        
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
                    // Sort so the newest reading is first.
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
    
    // MARK: - View Body
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                // Button showing the dynamic countdown.
                Button(action: {
                    // Implement the sensor sync action.
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
                
                // Button with placeholder text.
                Button(action: {
                    // Implement pairing action.
                }) {
                    VStack {
                        Text("Parkoppla ny sensor om:")
                            .font(.title2)
                            .multilineTextAlignment(.center)
                        Text("TBD timer")
                            .font(.title3)
                            .foregroundColor(.secondary)
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
                // Fetch NS BG data only once when the view appears.
                fetchNSBGData()
                
                // Log the current state of lastBG.
                let bgSec = Calendar.current.component(.second, from: lastBG)
                print("DEBUG: [onAppear] lastBG after NS fetch: \(lastBG) (seconds: \(bgSec))")
                
                // Initialize the countdown.
                sensorSecondsSync = calculateCountdown(for: Date())
                print("DEBUG: [onAppear] Initialized countdown: \(sensorSecondsSync) sekunder")
            }
            .onReceive(timer) { currentTime in
                // Only update the countdown using the previously fetched BG data.
                sensorSecondsSync = calculateCountdown(for: currentTime)
            }
        }
    }
}

