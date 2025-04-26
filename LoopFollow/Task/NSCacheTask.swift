//
//  NSCacheTask.swift
//  LoopFollow
//
//  Created by ChatGPT on 2025-04-26.
//

import Foundation

// Helper to know if any cache files already exist
private extension NightscoutCache {
    static var hasAnyFiles: Bool {
        (try? FileManager.default.contentsOfDirectory(at: dir,
                                                      includingPropertiesForKeys: nil))?
            .isEmpty == false
    }
}

extension MainViewController {

    // Call this once from scheduleAllTasks()
    // -------------------------------------------------------------------------
    func scheduleCacheTask(initialDelay: TimeInterval = 10) {
        let now = Date()
        let cal = Calendar.current

        // Decide firstRun: immediately if cache empty, else next 00:02
        let firstRun: Date
        if !NightscoutCache.hasAnyFiles {
            firstRun = now.addingTimeInterval(initialDelay)
        } else {
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.day! += 1
            comps.hour = 0
            comps.minute = 2
            comps.second = 0
            firstRun = cal.date(from: comps) ?? now.addingTimeInterval(3600)
        }

        TaskScheduler.shared.scheduleTask(id: .cacheFill, nextRun: firstRun) { [weak self] in
            guard let self = self else { return }
            self.cacheTaskAction()
        }
    }

    // -------------------------------------------------------------------------
    private func cacheTaskAction() {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())

        // If no cache yet, back‑fill the full retention window; otherwise just yesterday
        let daysToFetch = NightscoutCache.hasAnyFiles ? 1 : NightscoutCache.retentionDays

        let group = DispatchGroup()

        for i in 1...daysToFetch {
            guard let day = cal.date(byAdding: .day, value: -i, to: today) else { continue }

            // BG
            group.enter()
            self.webLoadNSBGDataCache(forDay: day) { group.leave() }

            // Treatments
            group.enter()
            self.WebLoadNSTreatmentsCache(forDay: day) { group.leave() }
        }

        group.notify(queue: .main) {
            // schedule next nightly run (tomorrow 00:02)
            var comps = cal.dateComponents([.year,.month,.day], from: today)
            comps.day! += 1
            comps.hour = 0; comps.minute = 2; comps.second = 0
            let next = cal.date(from: comps)!
            TaskScheduler.shared.rescheduleTask(id: .cacheFill, to: next)
        }
    }
}
// MARK: - BG cache fetch
// -------------------------------------------------------------------------
extension MainViewController {

    /// Fetch exactly one calendar day of SGVs and write to NightscoutCache.
    func webLoadNSBGDataCache(forDay day: Date, finished: @escaping () -> Void) {

        guard IsNightscoutEnabled() else { finished(); return }

        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!

        var params: [String:String] = [:]
        // Request a full day's SGVs, allowing some extra
        let hours = 24
        params["count"] = "\(hours * 12 + 12)"  // 12 readings per hour, plus buffer
        let iso = ISO8601DateFormatter()
        params["find[dateString][$gte]"] = iso.string(from: start)
        params["find[dateString][$lte]"] = iso.string(from: end)
        params["find[type][$ne]"] = "cal"

        NightscoutUtils.executeRequest(eventType: .sgv, parameters: params) {
            (result: Result<[ShareGlucoseData],Error>) in
            defer { finished() }

            guard case .success(let rawEntries) = result else { return }

            // Transform NS data to seconds and filter ≥4 min apart
            var cleaned: [ShareGlucoseData] = []
            var lastAddedTime = Double.infinity
            for var entry in rawEntries {
                entry.date /= 1000      // ms → s
                entry.date.round()
                if lastAddedTime - entry.date >= 240 {
                    cleaned.append(entry)
                    lastAddedTime = entry.date
                }
                if cleaned.count >= hours * 12 { break }
            }

            // Map to SGVJSON
            let sgvJSON = cleaned.map {
                SGVJSON(date: $0.date, sgv: $0.sgv)
            }

            // Preserve any existing treatments and overwrite SGVs
            let existingTreatments = (try? NightscoutCache.readDay(start).treatments) ?? []
            try? NightscoutCache.writeDay(date: start,
                                          sgv: sgvJSON,
                                          treatments: existingTreatments)
        }
    }
}
// MARK: - Treatments cache fetch
// -------------------------------------------------------------------------
extension MainViewController {

    /// Fetch exactly one calendar day of treatments and write to NightscoutCache.
    func WebLoadNSTreatmentsCache(forDay day: Date, finished: @escaping () -> Void) {

        guard UserDefaultsRepository.downloadTreatments.value,
              IsNightscoutEnabled() else { finished(); return }

        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!

        let iso = ISO8601DateFormatter()
        let params: [String:String] = [
            "find[created_at][$gte]": iso.string(from: start),
            "find[created_at][$lte]": iso.string(from: end)
        ]

        NightscoutUtils.executeDynamicRequest(eventType: .treatments, parameters: params) {
            (result: Result<Any,Error>) in
            defer { finished() }

            guard case .success(let data) = result,
                  let arr = data as? [[String:AnyObject]] else { return }

            let treats = arr.compactMap { TreatmentJSON(dict: $0 as [String : Any]) }

            // Preserve any existing SGVs and overwrite treatments
            let existingSGVs = (try? NightscoutCache.readDay(start).sgv) ?? []
            try? NightscoutCache.writeDay(date: start,
                                          sgv: existingSGVs,
                                          treatments: treats)
        }
    }
}
