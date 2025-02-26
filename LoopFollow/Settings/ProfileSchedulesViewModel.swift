//
//  ProfileSchedulesViewModel.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-26.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import Foundation
import HealthKit

struct ScheduleEntry: Identifiable {
    let id = UUID()
    let time: String
    let value: String
}

class ProfileSchedulesViewModel: ObservableObject {
    @Published var basalEntries: [ScheduleEntry] = []
    @Published var carbRatioEntries: [ScheduleEntry] = []
    @Published var isfEntries: [ScheduleEntry] = []
    @Published var targetEntries: [ScheduleEntry] = []
    @Published var csfEntries: [ScheduleEntry] = []
    @Published var minCarbsEntries: [ScheduleEntry] = []
    
    private var minCarbImpact: Double = 8 // Default value, will be fetched

    init() {
        fetchProfileData()
    }

    func fetchProfileData() {
            // First fetch preferences to get min_5m_carbimpact value
            fetchPreferences { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    let profile = ProfileManager.shared
                    
                    // Fetch and format basal schedule
                    self.basalEntries = profile.basalSchedule.map { entry in
                        ScheduleEntry(time: self.formatTime(entry.timeAsSeconds), value: String(format: "%.2f", entry.value))
                    }

                    // Fetch and format carb ratio schedule
                    self.carbRatioEntries = profile.carbRatioSchedule.map { entry in
                        ScheduleEntry(time: self.formatTime(entry.timeAsSeconds), value: "\(Int(entry.value))")
                    }

                    // Fetch and format ISF schedule
                    self.isfEntries = profile.isfSchedule.map { entry in
                        let value = entry.value.doubleValue(for: profile.units)
                        return ScheduleEntry(time: self.formatTime(entry.timeAsSeconds), value: String(format: "%.1f", value))
                    }

                    // Fetch and format Target schedule
                    self.targetEntries = profile.targetLowSchedule.map { entry in
                        let value = entry.value.doubleValue(for: profile.units)
                        return ScheduleEntry(time: self.formatTime(entry.timeAsSeconds), value: String(format: "%.1f", value))
                    }

                    // Compute CSF schedule
                    self.csfEntries = self.calculateCSFSchedule(isfSchedule: profile.isfSchedule, carbRatioSchedule: profile.carbRatioSchedule, unit: profile.units)

                    // Compute Minimum Carbs g/Hr schedule
                    self.minCarbsEntries = self.calculateMinCarbsSchedule(isfSchedule: profile.isfSchedule, carbRatioSchedule: profile.carbRatioSchedule, unit: profile.units)
                }
            }
        }
    
    private func fetchPreferences(completion: @escaping () -> Void) {
            NightscoutUtils.executeRequest(eventType: .profile, parameters: [:]) { (result: Result<NSProfile, Error>) in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let profileData):
                        if let value = profileData.nsPreferences?.preferences["min_5m_carbimpact"], let impact = Double(value) {
                            self.minCarbImpact = impact
                        }
                    case .failure(let error):
                        print("Error fetching preferences: \(error)")
                    }
                    completion()
                }
            }
        }
    
    private func calculateCSFSchedule(isfSchedule: [ProfileManager.TimeValue<HKQuantity>],
                                      carbRatioSchedule: [ProfileManager.TimeValue<Double>],
                                      unit: HKUnit) -> [ScheduleEntry] {
        var csfEntries: [ScheduleEntry] = []
        var lastISF: Double?
        var lastCarbRatio: Double?
        var isfDict: [Int: Double] = [:]
        var carbRatioDict: [Int: Double] = [:]
        
        // Convert ISF schedule to a lookup dictionary
        for entry in isfSchedule {
            isfDict[entry.timeAsSeconds / 3600] = entry.value.doubleValue(for: unit)
        }
        
        // Convert Carb Ratio schedule to a lookup dictionary
        for entry in carbRatioSchedule {
            carbRatioDict[entry.timeAsSeconds / 3600] = entry.value
        }
        
        // Compute CSF for every full hour
        for hour in 0..<24 {
            if let newISF = isfDict[hour] {
                lastISF = newISF
            }
            if let newCarbRatio = carbRatioDict[hour] {
                lastCarbRatio = newCarbRatio
            }

            if let isf = lastISF, let carbRatio = lastCarbRatio, carbRatio != 0 {
                let csf = isf / carbRatio
                let time = String(format: "%02d:00", hour)
                csfEntries.append(ScheduleEntry(time: time, value: String(format: "%.2f", csf)))
            }
        }

        return csfEntries
    }

    private func calculateMinCarbsSchedule(isfSchedule: [ProfileManager.TimeValue<HKQuantity>],
                                               carbRatioSchedule: [ProfileManager.TimeValue<Double>],
                                               unit: HKUnit) -> [ScheduleEntry] {
            var minCarbsEntries: [ScheduleEntry] = []
            var lastISF: Double?
            var lastCarbRatio: Double?
            var isfDict: [Int: Double] = [:]
            var carbRatioDict: [Int: Double] = [:]
            var totalMinCarbs: Double = 0

            for entry in isfSchedule {
                isfDict[entry.timeAsSeconds / 3600] = entry.value.doubleValue(for: unit)
            }

            for entry in carbRatioSchedule {
                carbRatioDict[entry.timeAsSeconds / 3600] = entry.value
            }

            for hour in 0..<24 {
                if let newISF = isfDict[hour] {
                    lastISF = newISF
                }
                if let newCarbRatio = carbRatioDict[hour] {
                    lastCarbRatio = newCarbRatio
                }

                if let isf = lastISF, let carbRatio = lastCarbRatio, isf != 0 {
                    let minCarbs = (self.minCarbImpact * (carbRatio / (isf * 18.181818))) * 12
                    totalMinCarbs += minCarbs
                    let time = String(format: "%02d:00", hour)
                    minCarbsEntries.append(ScheduleEntry(time: time, value: String(format: "%.0f", minCarbs)))
                }
            }

            let averageMinCarbs = totalMinCarbs / 24
            minCarbsEntries.append(ScheduleEntry(time: "Average", value: String(format: "%.0f", averageMinCarbs)))

            return minCarbsEntries
        }

        private func formatTime(_ seconds: Int) -> String {
            let hours = seconds / 3600
            return String(format: "%02d:00", hours)
        }
}
