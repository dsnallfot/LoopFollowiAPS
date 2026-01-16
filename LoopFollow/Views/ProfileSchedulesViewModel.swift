//
//  ProfileSchedulesViewModel.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-26.

//

import Foundation
import HealthKit

struct ScheduleEntry: Identifiable {
    let id = UUID()
    let time: String
    let value: String
}

final class ProfileSchedulesLastChangedStore {
    static let shared = ProfileSchedulesLastChangedStore()

    private let defaultsKey = "ProfileSchedulesLastChangedDates"
    private var cache: [String: Date] = [:]

    private init() {
        load()
    }

    private func load() {
        let defaults = UserDefaults.standard
        guard let dict = defaults.dictionary(forKey: defaultsKey) as? [String: TimeInterval] else {
            return
        }

        var result: [String: Date] = [:]
        for (key, ts) in dict {
            result[key] = Date(timeIntervalSince1970: ts)
        }
        cache = result
    }

    private func save() {
        var dict: [String: TimeInterval] = [:]
        for (key, date) in cache {
            dict[key] = date.timeIntervalSince1970
        }
        UserDefaults.standard.set(dict, forKey: defaultsKey)
    }

    func registerChange(forKey normalizedKey: String, at date: Date) {
        if let existing = cache[normalizedKey], existing >= date {
            return
        }
        cache[normalizedKey] = date
        save()
    }

    func mergedLatest(forKey normalizedKey: String, candidate: Date?) -> Date? {
        let persisted = cache[normalizedKey]

        switch (persisted, candidate) {
        case (nil, nil):
            return nil
        case (let p?, nil):
            return p
        case (nil, let c?):
            cache[normalizedKey] = c
            save()
            return c
        case (let p?, let c?):
            let latest = max(p, c)
            if latest != p {
                cache[normalizedKey] = latest
                save()
            }
            return latest
        }
    }
}

class ProfileSchedulesViewModel: ObservableObject {
    @Published var basalEntries: [ScheduleEntry] = []
    @Published var carbRatioEntries: [ScheduleEntry] = []
    @Published var isfEntries: [ScheduleEntry] = []
    @Published var targetEntries: [ScheduleEntry] = []
    @Published var csfEntries: [ScheduleEntry] = []
    @Published var minCarbsEntries: [ScheduleEntry] = []
    @Published var smbEntries: [ScheduleEntry] = []
    @Published var basalIOBEntries: [ScheduleEntry] = []
    @Published var lastChangedBasalProfile: Date?
    @Published var lastChangedCRProfile: Date?
    @Published var lastChangedISFProfile: Date?
    @Published var lastChangedTargetProfile: Date?
    
    private var minCarbImpact: Double = 8 // Default value, will be fetched
    private let lastChangedStore = ProfileSchedulesLastChangedStore.shared

    init() {
        fetchProfileData()
        scanCachedProfileNoteTreatments()
    }

    func fetchProfileData() {
            // First fetch preferences to get min_5m_carbimpact value
            fetchPreferences { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    let profile = ProfileManager.shared
                    
                    // Fetch and format basal schedule
                    self.basalEntries = self.calculateBasalSchedule(basalSchedule: profile.basalSchedule)
                    
                    // Efter att du satt self.basalEntries
                    let basalIOBTimeValues = BasalIOBCalculator.computeBasalIOBTimeValues(
                        from: profile.basalSchedule
                    )

                    // Om du vill visa det i din ProfileSchedulesView:
                    var basalIOBEntries: [ScheduleEntry] = basalIOBTimeValues.map { entry in
                        ScheduleEntry(
                            time: self.formatTime(entry.timeAsSeconds),
                            value: String(format: "%.2f", entry.value)
                        )
                    }

                    // Lägg till medelvärde längst ned
                    let totalIOB = basalIOBTimeValues.reduce(0.0) { partial, entry in
                        partial + entry.value
                    }
                    let averageIOB = basalIOBTimeValues.isEmpty ? 0.0 : totalIOB / Double(basalIOBTimeValues.count)
                    basalIOBEntries.append(
                        ScheduleEntry(
                            time: "Medel basal IOB/h",
                            value: String(format: "%.2f", averageIOB)
                        )
                    )

                    self.basalIOBEntries = basalIOBEntries
                    
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
                    // Existing logic for minCarbImpact
                    if let value = profileData.nsPreferences?.preferences["min_5m_carbimpact"],
                       let impact = Double(value) {
                        self.minCarbImpact = impact
                    }

                    // ✅ New: Extract SMB preferences here
                    let maxSMBMinutes = Int(profileData.nsPreferences?.preferences["maxSMBBasalMinutes"] ?? "") ?? 30
                    let maxUAMSMBMinutes = Int(profileData.nsPreferences?.preferences["maxUAMSMBBasalMinutes"] ?? "") ?? 30

                    // ✅ Trigger SMB calculation
                    let profile = ProfileManager.shared
                    self.smbEntries = self.calculateSMBSchedule(
                        basalSchedule: profile.basalSchedule,
                        maxSMBMinutes: maxSMBMinutes,
                        maxUAMSMBMinutes: maxUAMSMBMinutes
                    )

                case .failure(let error):
                    LogManager.shared.log(category: .trio, message: "Error fetching preferences: \(error)", isDebug: true)
                }

                completion()
            }
        }
    }
    
    private func calculateBasalSchedule(basalSchedule: [ProfileManager.TimeValue<Double>]) -> [ScheduleEntry] {
            var basalEntries: [ScheduleEntry] = []
            var lastBasal: Double?
            var basalDict: [Int: Double] = [:]
            var totalDailyBasal: Double = 0

            // Store basal values in a lookup dictionary
            for entry in basalSchedule {
                basalDict[entry.timeAsSeconds / 3600] = entry.value
            }

            // Generate a complete 24-hour schedule
            for hour in 0..<24 {
                if let newBasal = basalDict[hour] {
                    lastBasal = newBasal
                }

                if let basal = lastBasal {
                    totalDailyBasal += basal
                    let time = String(format: "%02d:00", hour)
                    basalEntries.append(ScheduleEntry(time: time, value: String(format: "%.2f", basal)))
                }
            }

            // Append total daily basal row
            basalEntries.append(ScheduleEntry(time: "Total daglig basal", value: String(format: "%.2f", totalDailyBasal)))

            return basalEntries
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
            minCarbsEntries.append(ScheduleEntry(time: "Medelvärde", value: String(format: "%.0f", averageMinCarbs)))

            return minCarbsEntries
        }
    
    private func calculateSMBSchedule(basalSchedule: [ProfileManager.TimeValue<Double>],
                                      maxSMBMinutes: Int,
                                      maxUAMSMBMinutes: Int) -> [ScheduleEntry] {
        var entries: [ScheduleEntry] = []
        var lastBasal: Double?
        var basalDict: [Int: Double] = [:]

        for entry in basalSchedule {
            basalDict[entry.timeAsSeconds / 3600] = entry.value
        }

        for hour in 0..<24 {
            if let newBasal = basalDict[hour] {
                lastBasal = newBasal
            }

            if let basal = lastBasal {
                let maxSMB = basal * Double(maxSMBMinutes) / 60.0
                let maxUAMSMB = basal * Double(maxUAMSMBMinutes) / 60.0
                let time = String(format: "%02d:00", hour)
                let roundedSMB = (maxSMB * 100).rounded() / 100
                let roundedUAMSMB = (maxUAMSMB * 100).rounded() / 100
                let value = String(format: "%.2f / %.2f", roundedSMB, roundedUAMSMB)
                entries.append(ScheduleEntry(time: time, value: value))
            }
        }

        return entries
    }

        private func formatTime(_ seconds: Int) -> String {
            let hours = seconds / 3600
            return String(format: "%02d:00", hours)
        }
    
    private func normalize(_ s: String) -> String {
        return s
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func scanCachedProfileNoteTreatments() {
        Task {
            let now = Date()
            let cal = Calendar.current
            let start = cal.date(byAdding: .day, value: -NightscoutCache.retentionDays, to: now)
                ?? now.addingTimeInterval(-90 * 24 * 60 * 60)

            let (_, treatments) = await NightscoutCache.loadWindow(from: start, to: now)

            var latest: [String: Date] = [:]

            // Behåll termerna som du vill att de ska vara “mänskliga”
            let rawTargets = ["Basalprofil", "CR-profil", "ISF-profil", "Mål-profil"]

            for t in treatments {
                guard t.eventType == "Note", let note = t.notes else { continue }
                guard note.contains("Justerad") || note.contains("ändrades") else { continue }

                let n = normalize(note) // tar bort _ - och mellanslag osv

                for raw in rawTargets {
                    let target = normalize(raw)               // <-- nyckeln här!
                    guard n.contains(target) else { continue }

                    if let existing = latest[target] {
                        if t.created_at > existing { latest[target] = t.created_at }
                    } else {
                        latest[target] = t.created_at
                    }
                }
            }

            // Swift 6-snapshot (candidates från cache-fönstret)
            let basalKey  = normalize("Basalprofil")
            let crKey     = normalize("CR-profil")
            let isfKey    = normalize("ISF-profil")
            let targetKey = normalize("Mål-profil")

            let basalCandidate  = latest[basalKey]
            let crCandidate     = latest[crKey]
            let isfCandidate    = latest[isfKey]
            let targetCandidate = latest[targetKey]

            await MainActor.run {
                // Persist: se till att vi inte tappar bort dessa datum när cachen åldras ut.
                for (normalizedKey, date) in latest {
                    self.lastChangedStore.registerChange(forKey: normalizedKey, at: date)
                }

                // Merge: om candidate är nil (pga 90-dagars fönstret), visa ändå persisterat värde.
                self.lastChangedBasalProfile  = self.lastChangedStore.mergedLatest(forKey: basalKey, candidate: basalCandidate)
                self.lastChangedCRProfile     = self.lastChangedStore.mergedLatest(forKey: crKey, candidate: crCandidate)
                self.lastChangedISFProfile    = self.lastChangedStore.mergedLatest(forKey: isfKey, candidate: isfCandidate)
                self.lastChangedTargetProfile = self.lastChangedStore.mergedLatest(forKey: targetKey, candidate: targetCandidate)
            }
        }
    }
}
