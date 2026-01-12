//
//  TrioPreferencesViewModel.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-23.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//
import Foundation

struct PreferenceEntry: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

class TrioPreferencesViewModel: ObservableObject {
    @Published var preferences: [PreferenceEntry] = []
    @Published var latestChangeDateByNormalizedKey: [String: Date] = [:]
    
    init() {
        fetchPreferences()
    }
    
    func fetchPreferences() {
        // Using your NightscoutUtils to fetch the NSProfile
        NightscoutUtils.executeRequest(eventType: .profile, parameters: [:]) { (result: Result<NSProfile, Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let profileData):
                    if let prefs = profileData.nsPreferences?.preferences {
                        self.preferences = prefs.map { key, value in
                            PreferenceEntry(key: key, value: value)
                        }
                        .sorted { $0.key < $1.key }

                        // Also scan cached Note-treatments to mark which settings have changed and when.
                        self.scanCachedNoteTreatmentsForPreferenceChanges(keys: Array(prefs.keys))
                    } else {
                        self.preferences = []
                        self.latestChangeDateByNormalizedKey = [:]
                    }
                case .failure(let error):
                    LogManager.shared.log(category: .trio, message: "Error fetching profile: \(error)", isDebug: true)

                    self.preferences = []
                }
            }
        }
    }

    private func normalizeKey(_ s: String) -> String {
        return s
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    func latestChangeDate(forKey key: String) -> Date? {
        latestChangeDateByNormalizedKey[normalizeKey(key)]
    }

    private func scanCachedNoteTreatmentsForPreferenceChanges(keys: [String]) {
        let normalizedKeys = keys.map { normalizeKey($0) }

        Task {
            let now = Date()
            let cal = Calendar.current
            let start = cal.date(byAdding: .day, value: -NightscoutCache.retentionDays, to: now)
                ?? now.addingTimeInterval(-90 * 24 * 60 * 60)

            let (_, treatments) = await NightscoutCache.loadWindow(from: start, to: now)

            let noteTreatments = treatments.filter { t in
                guard t.eventType == "Note", let note = t.notes else { return false }
                return note.contains("Justerad") || note.contains("ändrades")
            }

            var latest: [String: Date] = [:]

            for t in noteTreatments {
                guard let note = t.notes else { continue }
                let normalizedNote = normalizeKey(note)

                for nk in normalizedKeys {
                    guard normalizedNote.contains(nk) else { continue }
                    if let existing = latest[nk] {
                        if t.created_at > existing { latest[nk] = t.created_at }
                    } else {
                        latest[nk] = t.created_at
                    }
                }
            }

            await MainActor.run {
                self.latestChangeDateByNormalizedKey = latest
            }
        }
    }
}
