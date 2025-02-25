//
//  ProfileSchedulesViewModel.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-26.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import Foundation

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
    
    init() {
        fetchProfileData()
    }
    
    func fetchProfileData() {
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

        }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}
