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
        (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil)
        )?.isEmpty == false
    }
}

extension MainViewController {
    /// Schedule the nightly cache-fill task.
    func scheduleCacheTask(initialDelay: TimeInterval = 10) {
        let now = Date()
        let cal = Calendar.current

        // First run: immediately if cache empty, else tomorrow at 00:01
        let firstRun: Date
        if !NightscoutCache.hasAnyFiles {
            firstRun = now.addingTimeInterval(initialDelay)
        } else {
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.day! += 1
            comps.hour = 0; comps.minute = 1; comps.second = 0
            firstRun = cal.date(from: comps) ?? now.addingTimeInterval(3600)
        }

        TaskScheduler.shared.scheduleTask(id: .cacheFill, nextRun: firstRun) { [weak self] in
            self?.cacheTaskAction()
        }
    }

    /// Perform the cache backfill or nightly update.
    private func cacheTaskAction() {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())

        // On first run (empty cache) fetch retentionDays; thereafter only yesterday.
        let daysToFetch = NightscoutCache.hasAnyFiles ? 1 : NightscoutCache.retentionDays
        let group = DispatchGroup()

        for i in 1...daysToFetch {
            guard let day = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            group.enter()
            webLoadNSBGDataCache(forDay: day) { group.leave() }
            group.enter()
            WebLoadNSTreatmentsCache(forDay: day) { group.leave() }
        }

        group.notify(queue: .main) {
            // Reschedule for next midnight+2
            var comps = cal.dateComponents([.year, .month, .day], from: today)
            comps.day! += 1; comps.hour = 0; comps.minute = 2; comps.second = 0
            let next = cal.date(from: comps)!
            TaskScheduler.shared.rescheduleTask(id: .cacheFill, to: next)
        }
    }
}

// MARK: SGV Cache Fetch
extension MainViewController {
    /// Fetch one calendar day of SGVs and write to cache.
    func webLoadNSBGDataCache(
        forDay day: Date,
        finished: @escaping () -> Void
    ) {
        guard IsNightscoutEnabled() else { finished(); return }

        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!

        var params: [String: String] = [:]
        // Count for one day: 12 readings/hour + buffer
        let hours = 24
        params["count"] = "\(hours * 12 + 12)"
        let iso = ISO8601DateFormatter()
        params["find[dateString][$gte]"] = iso.string(from: start)
        params["find[dateString][$lte]"] = iso.string(from: end)
        params["find[type][$ne]"] = "cal"

        NightscoutUtils.executeRequest(eventType: .sgv,
            parameters: params
        ) { (result: Result<[ShareGlucoseData], Error>) in
            defer { finished() }
            guard case .success(let raw) = result else { return }

            var cleaned: [ShareGlucoseData] = []
            var lastTs = Double.infinity
            for var e in raw {
                e.date /= 1000; e.date.round()
                if lastTs - e.date >= 240 {
                    cleaned.append(e)
                    lastTs = e.date
                }
                if cleaned.count >= hours * 12 { break }
            }

            let sgvJSON = cleaned.map { SGVJSON(date: $0.date, sgv: $0.sgv) }
            let existingTreatments = (try? NightscoutCache.readDay(start).treatments) ?? []
            try? NightscoutCache.writeDay(date: start,
                                          sgv: sgvJSON,
                                          treatments: existingTreatments)
        }
    }
}

// MARK: Treatment Cache Fetch
extension MainViewController {
    /// Fetch one calendar day of treatments and write to cache.
    func WebLoadNSTreatmentsCache(
        forDay day: Date,
        finished: @escaping () -> Void
    ) {
        guard UserDefaultsRepository.downloadTreatments.value,
              IsNightscoutEnabled() else { finished(); return }

        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!

        let iso = ISO8601DateFormatter()
        let params: [String: String] = [
            "find[created_at][$gte]": iso.string(from: start),
            "find[created_at][$lte]": iso.string(from: end)
        ]

        NightscoutUtils.executeDynamicRequest(eventType: .treatments,
            parameters: params
        ) { (result: Result<Any, Error>) in
            defer { finished() }
            switch result {
            case .success(let data):
                if let entries = data as? [[String: AnyObject]] {
                    // Uppdatera appens behandlingstillstånd på main-tråden som tidigare
                    DispatchQueue.main.async {
                        self.updateTreatments(entries: entries)
                    }
                    
                    // Skriv samma behandlingsdata till NightscoutCache i bakgrunden.
                    // Detta gör att TreatmentsTableView (och andra vyer som läser via NightscoutCache)
                    // får löpande uppdaterade 90-dagarsfiler utan extra nattliga fetchar.
                    DispatchQueue.global(qos: .utility).async {
                        for entry in entries {
                            NightscoutCache.upsertTreatment(from: entry as [String: Any])
                        }
                        // Rensa gamla filer efter att vi lagt till nya entries (best-effort).
                        NightscoutCache.purgeOldFiles()
                    }
                } else {
                    LogManager.shared.log(category: .nightscout, message: "WebLoadNSTreatments, Unexpected data structure")
                }
            case .failure(let error):
                LogManager.shared.log(category: .nightscout, message: "WebLoadNSTreatments, error \(error.localizedDescription)")
            }
        }
    }
}
