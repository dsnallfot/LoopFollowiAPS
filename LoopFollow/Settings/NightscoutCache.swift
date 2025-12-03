// WORK IN PROGRESS: IDEA IS TO ADD A CACHE WITH entries 7-30 DAYS BACK to USE IN MEALANALYSISVIEW
//  NightscoutCache.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-04-26.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import Foundation
import Compression

// MARK: - Minimal JSON structs you already know from Nightscout
// • Add/remove fields as you need; only timestamp + value are mandatory.

struct SGVJSON: Codable {
    let date: TimeInterval       // epoch ms or sec – feed what you store
    let sgv:  Int
}

struct TreatmentJSON: Codable {
    let _id:        String
    let created_at: Date
    let eventType:  String

    // --- numeric payloads used in buildEventsArray ---
    let rate:       Double?      // Temp‑Basal U/h
    let absolute:   Double?      // fallback field for Temp‑Basal
    let insulin:    Double?      // SMB / Bolus
    let carbs:      Double?      // Carb Correction
    let glucose:    Double?      // Fingersticks

    // --- textual amount Nightscout sometimes stores in `amount` ---
    let amount:     String?      // “0.2u”, “12g”, … // Daniel: Denna tror jag inte finns
    let units:     String?       //mmol or mgdl

    // --- extra meta the array builder wants ---
    let foodType:   String?      // e.g. "pizza" or nil
    let notes: String?
    let tempBasalDuration: Double? // minutes; Nightscout's `duration`

    // If you add more Nightscout keys later, pop them in here as optionals.

    /// Build a `TreatmentJSON` from the raw Nightscout dictionary returned by `/treatments`.
    /// Only the fields MealAnalysisView needs are extracted; others default to `nil`.
    init?(dict: [String : Any]) {
        guard
            let id   = dict["_id"]        as? String,
            let iso  = dict["created_at"] as? String,
            let date = NightscoutUtils.parseDate(iso),
            let type = dict["eventType"]  as? String
        else { return nil }

        self._id        = id
        self.created_at = date
        self.eventType  = type

        self.rate       = dict["rate"]     as? Double
        self.absolute   = dict["absolute"] as? Double
        self.insulin    = dict["insulin"]  as? Double
        self.carbs      = dict["carbs"]    as? Double
        self.amount     = dict["amount"]   as? String
        self.foodType   = dict["foodType"] as? String
        self.notes      = dict["notes"] as? String
        self.glucose      = dict["glucose"]    as? Double
        self.units      = dict["units"] as? String
        self.tempBasalDuration = dict["duration"] as? Double
    }
}

// One day’s payload on disk
struct DayPayload: Codable {
    var sgv:        [SGVJSON]
    var treatments: [TreatmentJSON]
}

// MARK: - Disk cache helper

final class NightscoutCache {

    // Number of days to keep in cache (x * 24 hours back from now)
    static var retentionDays = 90

    // MARK: public API --------------------------------------------------------

    /// Return everything you already have between `start … end`.
    /// If a calendar-day file is missing, call `gapHandler(date)` so the app can fetch
    /// that day from Nightscout, then the cache will re-read it automatically.
    static func loadWindow(
        from start: Date,
        to end: Date,
        gapHandler: ((Date) async -> Void)? = nil
    ) async -> (sgv: [SGVJSON], treatments: [TreatmentJSON]) {

        var allSGV:        [SGVJSON]        = []
        var allTreatments: [TreatmentJSON]  = []

        var day = Calendar.current.startOfDay(for: start)
        let last = Calendar.current.startOfDay(for: end)

        while day <= last {
            if let dayData = try? readDay(day) {
                allSGV        += dayData.sgv
                allTreatments += dayData.treatments
            } else if let gapHandler = gapHandler {
                // Ask the app to fetch this missing day, await it, then retry read
                await gapHandler(day)
                if let dayData = try? readDay(day) {
                    allSGV        += dayData.sgv
                    allTreatments += dayData.treatments
                }
            }
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        }

        // Trim to exact time span
        let s = start.timeIntervalSince1970
        let e = end.timeIntervalSince1970
        allSGV        = allSGV       .filter { ($0.date >= s) && ($0.date <= e) }
        allTreatments = allTreatments.filter { ($0.created_at >= start) && ($0.created_at <= end) }

        return (allSGV, allTreatments)
    }

    /// Save/overwrite one complete calendar day worth of data.
    static func writeDay(date: Date, sgv: [SGVJSON], treatments: [TreatmentJSON]) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = DayPayload(sgv: sgv, treatments: treatments)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: fileURL(for: date), options: .atomic)
    }

    /// Delete cached files older than `retentionDays`.
    static func purgeOldFiles() {
        let cutoff = Calendar.current.date(byAdding: .day,
                                           value: -retentionDays,
                                           to: Date())!
        for url in (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                 includingPropertiesForKeys: nil)) ?? [] {
            if let day = isoFormatter.date(from: url.deletingPathExtension().lastPathComponent),
               day < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: private -----------------------------------------------------------

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    static var dir: URL = {
        let d = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NightscoutCache", isDirectory: true)
        return d
    }()

    /// Merge a batch of SGVJSON entries into the per‑day cache files.
    /// - Note: Best‑effort only; errors are silently ignored.
    static func mergeSGVBatch(_ batch: [SGVJSON]) {
        guard !batch.isEmpty else { return }

        let cal = Calendar.current

        // Group incoming readings per calendar day (UTC/local calendar startOfDay)
        var perDay: [Date: [SGVJSON]] = [:]
        for s in batch {
            let day = cal.startOfDay(for: Date(timeIntervalSince1970: s.date))
            perDay[day, default: []].append(s)
        }

        for (day, newItems) in perDay {
            do {
                var payload: DayPayload
                if let existing = try? readDay(day) {
                    payload = existing
                    // Remove any existing SGV with the same timestamp as in the new items
                    let newTimestamps = Set(newItems.map { $0.date })
                    payload.sgv.removeAll { newTimestamps.contains($0.date) }
                    payload.sgv.append(contentsOf: newItems)
                } else {
                    payload = DayPayload(sgv: newItems, treatments: [])
                }

                // Keep SGVs sorted by time, oldest first
                payload.sgv.sort { $0.date < $1.date }

                try writeDay(date: day, sgv: payload.sgv, treatments: payload.treatments)
            } catch {
                // Cache is best‑effort only; ignore write errors.
            }
        }
    }
    
    /// Debug: List all cached day files and their sizes.
    static func debugListSegments() {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
            print("📦 NightscoutCache — Cached segments:")
            if urls.isEmpty {
                print("   (no cached day files)")
            }
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let attrs = try? url.resourceValues(forKeys: [.fileSizeKey])
                let size = attrs?.fileSize ?? 0
                print("   • \(url.lastPathComponent) — \(size) bytes")
            }
        } catch {
            print("❌ NightscoutCache.debugListSegments error:", error.localizedDescription)
        }
    }

    private static func fileURL(for date: Date) -> URL {
        let dayStr = isoFormatter.string(from: Calendar.current.startOfDay(for: date))
        return dir.appendingPathComponent(dayStr).appendingPathExtension("json")
    }

    static func readDay(_ date: Date) throws -> DayPayload {
        let url = fileURL(for: date)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DayPayload.self, from: data)
    }
    
    /// Insert or replace a single treatment in the cache based on its Nightscout dictionary.
    /// If the day file exists, the treatment with the same _id is replaced; otherwise a new day file is created.
    static func upsertTreatment(from dict: [String: Any]) {
        guard let tjson = TreatmentJSON(dict: dict) else { return }
        let day = Calendar.current.startOfDay(for: tjson.created_at)

        do {
            var payload: DayPayload
            if let existing = try? readDay(day) {
                payload = existing
                // Remove any previous treatment with the same _id
                payload.treatments.removeAll { $0._id == tjson._id }
                payload.treatments.append(tjson)
            } else {
                payload = DayPayload(sgv: [], treatments: [tjson])
            }
            try writeDay(date: day, sgv: payload.sgv, treatments: payload.treatments)
        } catch {
            // Silently ignore cache write errors; cache is best-effort only.
        }
    }
}
