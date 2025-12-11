
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
    static var retentionDays = 91

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
                let normalizedSGV = normalizeAndDedupeSGV(dayData.sgv)
                allSGV        += normalizedSGV
                allTreatments += dayData.treatments
            } else if let gapHandler = gapHandler {
                // Ask the app to fetch this missing day, await it, then retry read
                await gapHandler(day)
                if let dayData = try? readDay(day) {
                    let normalizedSGV = normalizeAndDedupeSGV(dayData.sgv)
                    allSGV        += normalizedSGV
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

    /// Delete cached files older than `retentionDays` calendar days.
    /// Uses startOfDay in the current calendar to avoid off‑by‑one errors due to time-of-day/UTC.
    static func purgeOldFiles() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        // Oldest day we want to keep = todayStart - (retentionDays - 1) days
        // Example: retentionDays = 90 → keep 90 hela kalenderdagar inklusive idag.
        let oldestToKeep = calendar.date(byAdding: .day,
                                         value: -retentionDays,// + 1,
                                         to: todayStart)!

        for url in (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                 includingPropertiesForKeys: nil)) ?? [] {
            guard let dayDate = isoFormatter.date(from: url.deletingPathExtension().lastPathComponent) else {
                continue
            }
            let localDayStart = calendar.startOfDay(for: dayDate)
            if localDayStart < oldestToKeep {
                /*LogManager.shared.log(
                    category: .temporaryDebug,
                    message: "purgeOldFiles – DELETING \(localDayStart) (< oldestToKeep \(oldestToKeep))",
                    isDebug: true
                )*/
                try? FileManager.default.removeItem(at: url)
            } else {
                /*LogManager.shared.log(
                    category: .temporaryDebug,
                    message: "purgeOldFiles – keeping \(localDayStart) (>= oldestToKeep \(oldestToKeep))",
                    isDebug: true
                )*/
            }
        }
    }

    /// Normalize SGV timestamps so they are always stored/handled in **seconds** since 1970
    /// and deduplicate entries with the same timestamp (last one wins).
    /// Some older cache files may have `date` in milliseconds; this helper converts those
    /// on-the-fly when reading so that mixed second/ms data does not cause partial days
    /// or dropped entries in statistics.
    static func normalizeAndDedupeSGV(_ sgv: [SGVJSON]) -> [SGVJSON] {
        guard !sgv.isEmpty else { return [] }

        var byTimestamp: [TimeInterval: Int] = [:]

        for entry in sgv {
            let raw = entry.date
            // Heuristic: if the value is larger than ~year 2100 in seconds,
            // assume it is stored in milliseconds and convert to seconds.
            let seconds: TimeInterval
            if raw > 4_000_000_000 { // ~2100-02-07 in seconds
                seconds = raw / 1000.0
            } else {
                seconds = raw
            }
            byTimestamp[seconds] = entry.sgv
        }

        let normalized = byTimestamp.map { (ts, value) in
            SGVJSON(date: ts, sgv: value)
        }

        return normalized.sorted { $0.date < $1.date }
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
    
    /// Refresh cached treatments within a time window, replacing treatments in that window with the given entries.
    static func refreshTreatmentsWindow(from start: Date, to end: Date, entries: [[String: Any]]) {
        let treatments = entries.compactMap { TreatmentJSON(dict: $0) }
            .filter { $0.created_at >= start && $0.created_at <= end }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: treatments) { calendar.startOfDay(for: $0.created_at) }

        var day = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)

        while day <= lastDay {
            do {
                var payload = (try? readDay(day)) ?? DayPayload(sgv: [], treatments: [])

                // Remove treatments in the payload that lie between start and end inclusive
                payload.treatments.removeAll { $0.created_at >= start && $0.created_at <= end }

                if let incoming = grouped[day] {
                    let incomingIDs = Set(incoming.map { $0._id })
                    // Remove any existing treatments with the same _id as incoming
                    payload.treatments.removeAll { incomingIDs.contains($0._id) }
                    payload.treatments.append(contentsOf: incoming)
                    payload.treatments.sort { $0.created_at < $1.created_at }
                }

                try writeDay(date: day, sgv: payload.sgv, treatments: payload.treatments)
            } catch {
                // Silently ignore errors
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
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

// MARK: - NS-only SGV cache for GlucoseView

/// Lightweight per-day payload for NS-only glucose cache (no treatments).
private struct GlucoseNSDayPayload: Codable {
    var sgv: [SGVJSON]
}

/// Separate Nightscout SGV cache used exclusively by GlucoseView for NS-only gap analysis.
/// This cache is intentionally not touched by BGTask/BGData or Dexcom logic.
final class GlucoseNSOnlyCache {

    // Number of days to keep in cache (x * 24 hours back from now)
    static var retentionDays = 91

    // Directory for NS-only glucose cache
    static var dir: URL = {
        let d = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NightscoutGlucoseCache", isDirectory: true)
        return d
    }()

    // ISO formatter for day file names (YYYY-MM-DD)
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    /// Return SGVs you already have between `start … end` from the NS-only cache.
    static func loadWindow(from start: Date, to end: Date) async -> [SGVJSON] {
        var allSGV: [SGVJSON] = []

        var day = Calendar.current.startOfDay(for: start)
        let last = Calendar.current.startOfDay(for: end)

        while day <= last {
            if let dayData = try? readDay(day) {
                let normalizedSGV = NightscoutCache.normalizeAndDedupeSGV(dayData.sgv)
                allSGV += normalizedSGV
            }
            guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }

        // Trim to exact time span
        let s = start.timeIntervalSince1970
        let e = end.timeIntervalSince1970
        allSGV = allSGV.filter { ($0.date >= s) && ($0.date <= e) }

        return allSGV
    }

    /// Merge a batch of SGVJSON entries into the per‑day NS-only cache files.
    /// - Note: Best‑effort only; errors are silently ignored.
    static func mergeSGVBatch(_ batch: [SGVJSON]) {
        guard !batch.isEmpty else { return }

        let cal = Calendar.current

        // Group incoming readings per calendar day (local startOfDay)
        var perDay: [Date: [SGVJSON]] = [:]
        for s in batch {
            let day = cal.startOfDay(for: Date(timeIntervalSince1970: s.date))
            perDay[day, default: []].append(s)
        }

        for (day, newItems) in perDay {
            do {
                var payload: GlucoseNSDayPayload
                if let existing = try? readDay(day) {
                    payload = existing
                    // Remove any existing SGV with the same timestamp as in the new items
                    let newTimestamps = Set(newItems.map { $0.date })
                    payload.sgv.removeAll { newTimestamps.contains($0.date) }
                    payload.sgv.append(contentsOf: newItems)
                } else {
                    payload = GlucoseNSDayPayload(sgv: newItems)
                }

                // Keep SGVs sorted by time, oldest first
                payload.sgv.sort { $0.date < $1.date }

                try writeDay(date: day, sgv: payload.sgv)
            } catch {
                // Cache is best‑effort only; ignore write errors.
            }
        }
    }

    /// Delete cached files older than `retentionDays` calendar days.
    static func purgeOldFiles() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let oldestToKeep = calendar.date(byAdding: .day,
                                         value: -retentionDays,
                                         to: todayStart)!

        for url in (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                 includingPropertiesForKeys: nil)) ?? [] {
            guard let dayDate = isoFormatter.date(from: url.deletingPathExtension().lastPathComponent) else {
                continue
            }
            let localDayStart = calendar.startOfDay(for: dayDate)
            if localDayStart < oldestToKeep {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Debug: List all cached NS-only glucose day files and their sizes.
    static func debugListSegments() {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
            print("📦 GlucoseNSOnlyCache — Cached segments:")
            if urls.isEmpty {
                print("   (no cached day files)")
            }
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let attrs = try? url.resourceValues(forKeys: [.fileSizeKey])
                let size = attrs?.fileSize ?? 0
                print("   • \(url.lastPathComponent) — \(size) bytes")
            }
        } catch {
            print("❌ GlucoseNSOnlyCache.debugListSegments error:", error.localizedDescription)
        }
    }

    // MARK: - Private helpers

    private static func fileURL(for date: Date) -> URL {
        let dayStr = isoFormatter.string(from: Calendar.current.startOfDay(for: date))
        return dir.appendingPathComponent(dayStr).appendingPathExtension("json")
    }

    private static func readDay(_ date: Date) throws -> GlucoseNSDayPayload {
        let url = fileURL(for: date)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GlucoseNSDayPayload.self, from: data)
    }

    private static func writeDay(date: Date, sgv: [SGVJSON]) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = GlucoseNSDayPayload(sgv: sgv)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: fileURL(for: date), options: .atomic)
    }
}
