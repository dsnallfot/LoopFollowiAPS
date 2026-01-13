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

    // MARK: - Dev deviation analysis (ad hoc)

    struct DevPoint: Identifiable {
        let id = UUID()
        let date: Date
        let dev: Double
    }

    @Published var devPoints: [DevPoint] = []
    @Published var devIsLoading: Bool = false
    @Published var devLastError: String? = nil
    
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

    // MARK: - Dev fetch + parsing

    private static let devRegex: NSRegularExpression? = {
        // Lite robustare: tillåter flera siffror + decimals (och ev utan decimal)
        return try? NSRegularExpression(pattern: #"Dev:\s*([-+]?\d+(?:\.\d+)?)"#)
    }()

    private func parseDevValue(from reasonString: String) -> Double? {
        guard let regex = Self.devRegex else { return nil }
        let range = NSRange(location: 0, length: reasonString.utf16.count)
        guard let match = regex.firstMatch(in: reasonString, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        let devValueString = (reasonString as NSString).substring(with: match.range(at: 1))
        return Double(devValueString)
    }

    private func parseCreatedAt(_ createdAtString: String) -> Date? {
        // Primary: ISO8601 with fractional seconds
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso1.date(from: createdAtString) { return d }

        // Fallback: ISO8601 without fractional seconds
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        return iso2.date(from: createdAtString)
    }

    private func extractReasonString(from deviceStatusDict: [String: Any]) -> String? {
        // Only use suggested. Enacted is usually a near-duplicate and halves our effective coverage.
        if let openaps = deviceStatusDict["openaps"] as? [String: Any],
           let suggested = openaps["suggested"] as? [String: Any],
           let reason = suggested["reason"] as? String {
            return reason
        }
        return nil
    }

    /// Fetch the latest 300 device-status documents from Nightscout and build a 24h window of Dev points.
    func fetchDevDeviationsLast24h(count: Int = 300) {
        devIsLoading = true
        devLastError = nil

        let params: [String: String] = ["count": "\(count)"]

        NightscoutUtils.executeDynamicRequest(eventType: .deviceStatus, parameters: params) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let payload):
                guard let array = payload as? [[String: Any]] else {
                    DispatchQueue.main.async {
                        self.devIsLoading = false
                        self.devLastError = "Unexpected deviceStatus payload"
                        self.devPoints = []
                    }
                    return
                }

                var points: [DevPoint] = []
                points.reserveCapacity(array.count)

                for ds in array {
                    guard let createdAt = ds["created_at"] as? String,
                          let date = self.parseCreatedAt(createdAt) else {
                        continue
                    }

                    guard let reason = self.extractReasonString(from: ds),
                          let dev = self.parseDevValue(from: reason) else {
                        continue
                    }

                    points.append(DevPoint(date: date, dev: dev))
                }

                // Sort oldest -> newest
                points.sort(by: { $0.date < $1.date })

                // Keep only last 24h, anchored to newest point (so it is truly "rolling")
                let end = points.last?.date ?? Date()
                let start = end.addingTimeInterval(-24 * 60 * 60)
                let windowed = points.filter { $0.date >= start && $0.date <= end }

                DispatchQueue.main.async {
                    self.devIsLoading = false
                    self.devPoints = windowed
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    self.devIsLoading = false
                    self.devLastError = error.localizedDescription
                    self.devPoints = []
                }
            }
        }
    }
}
