
//  NightscoutCache.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-04-26.
//

import Foundation
import Compression
import ZIPFoundation

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

    // --- meta ---
    let enteredBy:  String?

    // --- numeric payloads used in buildEventsArray ---
    let rate:       Double?      // Temp‑Basal U/h
    let absolute:   Double?      // fallback field for Temp‑Basal
    let insulin:    Double?      // SMB / Bolus
    let carbs:      Double?      // Carb Correction
    let glucose:    Double?      // Fingersticks
    let fat:        Double?      // Fat (grams)
    let protein:    Double?      // Protein (grams)

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

        self.enteredBy   = dict["enteredBy"] as? String

        self.rate       = dict["rate"]     as? Double
        self.absolute   = dict["absolute"] as? Double
        self.insulin    = dict["insulin"]  as? Double
        self.carbs      = dict["carbs"]    as? Double
        self.amount     = dict["amount"]   as? String
        self.foodType   = dict["foodType"] as? String
        self.notes      = dict["notes"] as? String
        self.glucose      = dict["glucose"]    as? Double

        // Parse fat and protein, supporting both Double and String (with "," or ".")
        if let fatVal = dict["fat"] as? Double {
            self.fat = fatVal
        } else if let fatStr = dict["fat"] as? String, let fatVal = Double(fatStr.replacingOccurrences(of: ",", with: ".")) {
            self.fat = fatVal
        } else {
            self.fat = nil
        }

        if let proteinVal = dict["protein"] as? Double {
            self.protein = proteinVal
        } else if let proteinStr = dict["protein"] as? String, let proteinVal = Double(proteinStr.replacingOccurrences(of: ",", with: ".")) {
            self.protein = proteinVal
        } else {
            self.protein = nil
        }

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
    
    /// Returns the sick-day override note if this treatment represents
    /// a known sickness override.
    ///
    /// We currently detect:
    /// - eventType == "Exercise"
    /// - notes containing "Förkyld" or "Magsjuka"
    static func sickDayOverrideNote(from treatment: TreatmentJSON) -> String? {
        guard treatment.eventType.caseInsensitiveCompare("Exercise") == .orderedSame else {
            return nil
        }

        guard let notes = treatment.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
              !notes.isEmpty else {
            return nil
        }

        let normalized = notes.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if normalized.contains("forkyld") || normalized.contains("magsjuka") {
            return notes
        }

        return nil
    }

    /// Rebuilds the sick-day cache entry for a given day from that day's cached treatments.
    /// If no matching override exists anymore, any existing sick-day entry is removed.
    static func refreshSickDayCache(for day: Date, treatments: [TreatmentJSON]) {
        let latestMatchingNotes = treatments
            .sorted { $0.created_at < $1.created_at }
            .compactMap { sickDayOverrideNote(from: $0) }
            .last

        Storage.shared.setSickDayHistoryEntry(for: day, notes: latestMatchingNotes)
    }

    /// Returns the stored sick-day entry for a given date if one exists.
    /// Useful for quickly marking sick days in charts or tables.
    static func isSickDay(_ date: Date) -> SickDayHistoryEntry? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)

        return Storage.shared.sickDayHistory.first {
            calendar.isDate(Date(timeIntervalSince1970: $0.date), inSameDayAs: dayStart)
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
/*
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
*/
    private static func fileURL(for date: Date) -> URL {
        let dayStr = isoFormatter.string(from: Calendar.current.startOfDay(for: date))
        return dir.appendingPathComponent(dayStr).appendingPathExtension("json")
    }

    static func readDay(_ date: Date) throws -> DayPayload {
        let url = fileURL(for: date)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DayPayload.self, from: data)
    }
    
    /// Refresh cached treatments within a time window by **deleting** cached treatments in that window and then inserting the given entries for that window.
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
                refreshSickDayCache(for: day, treatments: payload.treatments)
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
                payload.treatments.sort { $0.created_at < $1.created_at }
            } else {
                payload = DayPayload(sgv: [], treatments: [tjson])
            }

            try writeDay(date: day, sgv: payload.sgv, treatments: payload.treatments)
            refreshSickDayCache(for: day, treatments: payload.treatments)
        } catch {
            // Silently ignore cache write errors; cache is best-effort only.
        }
    }
}

// MARK: - Battery history cache (local only, built incrementally from deviceStatus)

/// One battery reading.
struct BatterySampleJSON: Codable {
    let date: TimeInterval      // seconds since 1970
    let percent: Double         // 0-100
    let isCharging: Bool
}

/// One day’s battery payload on disk.
private struct BatteryDayPayload: Codable {
    var samples: [BatterySampleJSON]
}

/// Local disk cache for uploader battery readings (built over time).
final class BatteryCache {

    /// Keep up to ~3 months to match other logs.
    static var retentionDays = 91

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    static var dir: URL = {
        let d = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BatteryCache", isDirectory: true)
        return d
    }()

    /// Append a single battery sample to the appropriate day file. Best-effort only.
    /// Deduplicates by timestamp (last one wins).
    static func appendSample(timestamp: TimeInterval, batteryPercent: Double, isCharging: Bool) {
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date(timeIntervalSince1970: timestamp))

        let sample = BatterySampleJSON(date: timestamp, percent: batteryPercent, isCharging: isCharging)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            var payload: BatteryDayPayload
            if let existing = try? readDay(day) {
                payload = existing
            } else {
                payload = BatteryDayPayload(samples: [])
            }

            // Deduplicate by timestamp (last wins)
            var byTs: [TimeInterval: BatterySampleJSON] = [:]
            for s in payload.samples { byTs[s.date] = s }
            byTs[sample.date] = sample

            payload.samples = byTs.values.sorted { $0.date < $1.date }

            try writeDay(date: day, payload: payload)

            purgeOldFiles()
        } catch {
            // Best-effort cache only; ignore write errors.
        }
    }

    /// Load samples between start and end (inclusive). Returns ascending by time.
    static func loadWindow(from start: Date, to end: Date) async -> [BatterySampleJSON] {
        var all: [BatterySampleJSON] = []
        let cal = Calendar.current
        var day = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)

        while day <= last {
            if let dayData = try? readDay(day) {
                all += dayData.samples
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }

        let s = start.timeIntervalSince1970
        let e = end.timeIntervalSince1970
        all = all.filter { $0.date >= s && $0.date <= e }
        return all.sorted { $0.date < $1.date }
    }

    /// Load one calendar day (local time) worth of samples. Returns ascending by time.
    static func loadDay(_ date: Date) async -> [BatterySampleJSON] {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        return (try? readDay(day))?.samples.sorted { $0.date < $1.date } ?? []
    }

    /// Delete cached files older than `retentionDays` calendar days.
    static func purgeOldFiles() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let oldestToKeep = calendar.date(byAdding: .day, value: -retentionDays, to: todayStart)!

        for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            guard let dayDate = isoFormatter.date(from: url.deletingPathExtension().lastPathComponent) else {
                continue
            }
            let localDayStart = calendar.startOfDay(for: dayDate)
            if localDayStart < oldestToKeep {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Private helpers

    private static func fileURL(for date: Date) -> URL {
        let dayStr = isoFormatter.string(from: Calendar.current.startOfDay(for: date))
        return dir.appendingPathComponent(dayStr).appendingPathExtension("json")
    }

    private static func readDay(_ date: Date) throws -> BatteryDayPayload {
        let url = fileURL(for: date)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BatteryDayPayload.self, from: data)
    }

    private static func writeDay(date: Date, payload: BatteryDayPayload) throws {
        let data = try JSONEncoder().encode(payload)
        try data.write(to: fileURL(for: date), options: .atomic)
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
/*
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
 */

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

// MARK: - Monthly archive (store historical data for all time)

/// Copies the previous month's cached day-files into a permanent archive folder.
///
/// Archive layout:
///   Application Support/LoopFollow/Arkiv/YYYY-MM/
///     BatteryCache/2025-11-18.json
///     NightscoutCache/2025-11-18.json
///     NightscoutGlucoseCache/2025-11-18.json
///     StatsCache.json
///     _archiveComplete.json
final class ArchiveManager {
    
    private static func isoTimestampForFilename(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: date)
    }

    private static let fm = FileManager.default

    /// Base folder for the archive (Application Support is persistent and backed up).
    /// We intentionally avoid Caches because iOS may purge it.
    static var archiveRootDir: URL {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        // New location (no redundant LoopFollow folder):
        // Application Support/Arkiv
        let newDir = appSupport.appendingPathComponent("Arkiv", isDirectory: true)

        // Old location (used previously): Application Support/LoopFollow/Arkiv
        let oldDir = appSupport
            .appendingPathComponent("LoopFollow", isDirectory: true)
            .appendingPathComponent("Arkiv", isDirectory: true)

        migrateIfNeeded(from: oldDir, to: newDir)
        return newDir
    }
    
    /// User-visible ZIP archive folder (Files app: On My iPhone → LoopFollow → Ziparkiv)
    /// Note: The app's Documents directory is already exposed as the "LoopFollow" folder in Files.
    private static var documentsZipArchiveDir: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Ziparkiv", isDirectory: true)
    }
    
    /// Local exports folder for ZIP snapshots (still inside sandbox).
    private static var archiveExportsDir: URL {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        // New location (no redundant LoopFollow folder):
        // Application Support/ArkivExports
        let newDir = appSupport.appendingPathComponent("ArkivExports", isDirectory: true)

        // Old location (used previously): Application Support/LoopFollow/ArkivExports
        let oldDir = appSupport
            .appendingPathComponent("LoopFollow", isDirectory: true)
            .appendingPathComponent("ArkivExports", isDirectory: true)

        migrateIfNeeded(from: oldDir, to: newDir)
        return newDir
    }

    static func createArchiveZipSnapshot() async throws -> URL {

        try fm.createDirectory(at: archiveExportsDir, withIntermediateDirectories: true)

        let timestamp = isoTimestampForFilename(Date())
        let zipURL = archiveExportsDir
            .appendingPathComponent("LoopFollow-Arkiv-\(timestamp)")
            .appendingPathExtension("zip")

        if fm.fileExists(atPath: zipURL.path) {
            try? fm.removeItem(at: zipURL)
        }

        // ZIPFoundation extends FileManager with zipItem/unzipItem.
        // shouldKeepParent=true keeps the top-level "Arkiv" folder inside the zip.
        try fm.zipItem(at: archiveRootDir, to: zipURL, shouldKeepParent: true)

        LogManager.shared.log(category: .taskScheduler, message: "ArchiveManager - created archive zip: \(zipURL.lastPathComponent)")
        print("📦 ArchiveManager - created archive zip: \(zipURL.lastPathComponent)")
        
        // Avoid unbounded growth in ArkivExports.
        cleanupArchiveExports(keepingLatest: 3)

        return zipURL
    }
    
    /// Creates a zip for a single archived month folder: Arkiv/YYYY-MM
    /// Output filename: LoopFollow-Arkiv-YYYY-MM.zip (overwritten if it already exists)
    static func createMonthlyArchiveZipSnapshot(monthFolderName: String) async throws -> URL {
        try fm.createDirectory(at: archiveExportsDir, withIntermediateDirectories: true)

        let sourceMonthDir = archiveRootDir.appendingPathComponent(monthFolderName, isDirectory: true)
        guard fm.fileExists(atPath: sourceMonthDir.path) else {
            throw NSError(
                domain: "ArchiveManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Month folder does not exist: \(monthFolderName)"]
            )
        }

        let zipURL = archiveExportsDir
            .appendingPathComponent("LoopFollow-Arkiv-\(monthFolderName)")
            .appendingPathExtension("zip")

        if fm.fileExists(atPath: zipURL.path) {
            try? fm.removeItem(at: zipURL)
        }

        // ZIPFoundation extends FileManager with zipItem/unzipItem.
        // shouldKeepParent=true keeps the top-level "YYYY-MM" folder inside the zip.
        try fm.zipItem(at: sourceMonthDir, to: zipURL, shouldKeepParent: true)

        LogManager.shared.log(category: .taskScheduler, message: "ArchiveManager - created monthly zip: \(zipURL.lastPathComponent)")
        print("📦 ArchiveManager - created monthly zip: \(zipURL.lastPathComponent)")
        
        // Avoid unbounded growth in ArkivExports.
        cleanupArchiveExports(keepingLatest: 3)
        
        return zipURL
    }


    /// Ensures the previous month exists in the archive. If it has not been archived yet,
    /// copy the previous month’s per-day cache json files + write a month-scoped StatsCache.json.
    static func archivePreviousMonthIfNeeded() async {
        LogManager.shared.log(category: .taskScheduler, message: "ArchiveManager - start archivePreviousMonthIfNeeded")
        print("📦 ArchiveManager - start archivePreviousMonthIfNeeded")
        let cal = Calendar.current
        let now = Date()

        // Interval for previous calendar month: [startPrevMonth, startThisMonth)
        guard let startThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return }
        guard let startPrevMonth = cal.date(byAdding: .month, value: -1, to: startThisMonth) else { return }

        let interval = DateInterval(start: startPrevMonth, end: startThisMonth)
        let monthFolderName = Self.monthFolderName(for: startPrevMonth)
        let destMonthDir = archiveRootDir.appendingPathComponent(monthFolderName, isDirectory: true)
        
        LogManager.shared.log(category: .taskScheduler, message: "ArchiveManager - target month folder: \(monthFolderName)")
        print("📦 ArchiveManager - target month folder: \(monthFolderName)")

        // If we already have a completion marker, assume this month is archived.
        let markerURL = destMonthDir.appendingPathComponent("_archiveComplete.json")
        if fm.fileExists(atPath: markerURL.path) {
            LogManager.shared.log(category: .taskScheduler, message: "ArchiveManager - already archived (marker exists) for \(monthFolderName)")
            print("📦 ArchiveManager - already archived for \(monthFolderName)")
            
            // Still ensure a user-visible ZIP exists in Documents.
            exportMonthlyZipToDocuments(monthFolderName: monthFolderName)
            return
        }

        do {
            try fm.createDirectory(at: destMonthDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: destMonthDir.appendingPathComponent("BatteryCache", isDirectory: true), withIntermediateDirectories: true)
            try fm.createDirectory(at: destMonthDir.appendingPathComponent("NightscoutCache", isDirectory: true), withIntermediateDirectories: true)
            try fm.createDirectory(at: destMonthDir.appendingPathComponent("NightscoutGlucoseCache", isDirectory: true), withIntermediateDirectories: true)
        } catch {
            LogManager.shared.log(category: .taskScheduler, message: "ArchiveManager - failed creating month directories: \(error)")
            return
        }

        // Copy per-day cache files for the previous month
        copyDayFiles(
            fromDir: BatteryCache.dir,
            toDir: destMonthDir.appendingPathComponent("BatteryCache", isDirectory: true),
            within: interval
        )

        copyDayFiles(
            fromDir: NightscoutCache.dir,
            toDir: destMonthDir.appendingPathComponent("NightscoutCache", isDirectory: true),
            within: interval
        )

        copyDayFiles(
            fromDir: GlucoseNSOnlyCache.dir,
            toDir: destMonthDir.appendingPathComponent("NightscoutGlucoseCache", isDirectory: true),
            within: interval
        )

        // Export month-scoped StatsCache.json (best-effort)
        StatsCacheManager.shared.exportMonthStatsCache(
            interval: interval,
            destinationURL: destMonthDir.appendingPathComponent("StatsCache.json")
        )

        // Write completion marker
        let marker = ArchiveCompletionMarker(
            archivedMonth: monthFolderName,
            intervalStart: interval.start,
            intervalEnd: interval.end,
            archivedAt: Date()
        )

        do {
            let data = try JSONEncoder().encode(marker)
            try data.write(to: markerURL, options: [.atomic])
        } catch {
            // Best effort only.
        }

        // Create/overwrite a user-visible ZIP snapshot for the archived month.
        exportMonthlyZipToDocuments(monthFolderName: monthFolderName)

        LogManager.shared.log(
            category: .taskScheduler,
            message: "ArchiveManager - archived previous month: \(monthFolderName)",
            isDebug: true
        )
    }

    // MARK: - Helpers

    private struct ArchiveCompletionMarker: Codable {
        let archivedMonth: String
        let intervalStart: Date
        let intervalEnd: Date
        let archivedAt: Date
    }

    private static func monthFolderName(for dateInMonth: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: dateInMonth)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        return String(format: "%04d-%02d", y, m)
    }
    
    /// Returns the newest archived month folder name (YYYY-MM) under Arkiv.
    /// Throws if no month folders exist yet.
    static func latestArchivedMonthFolderName() throws -> String {
        let urls = (try? fm.contentsOfDirectory(
            at: archiveRootDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let monthNames: [String] = urls.compactMap { url in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }

            let name = url.lastPathComponent
            guard !name.hasPrefix("_") else { return nil }     // skip marker files etc
            guard name.count == 7 else { return nil }          // "YYYY-MM"
            // Quick sanity: "YYYY-MM" with hyphen at pos 5
            let chars = Array(name)
            guard chars.count == 7, chars[4] == "-" else { return nil }
            return name
        }

        let sorted = monthNames.sorted() // lexicographic works for YYYY-MM
        guard let latest = sorted.last else {
            throw NSError(
                domain: "ArchiveManager",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Inga arkiverade månader hittades ännu."]
            )
        }
        return latest
    }

    /// Copies all YYYY-MM-DD.json files in `fromDir` that fall within the given interval.
    /// Best-effort: overwrites existing destination files.
    private static func copyDayFiles(fromDir: URL, toDir: URL, within interval: DateInterval) {
        do {
            try fm.createDirectory(at: toDir, withIntermediateDirectories: true)

            let urls = (try? fm.contentsOfDirectory(at: fromDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for src in urls {
                guard src.pathExtension.lowercased() == "json" else { continue }

                let dayName = src.deletingPathExtension().lastPathComponent
                guard let day = isoDayFormatter.date(from: dayName) else { continue }

                if day >= interval.start && day < interval.end {
                    let dest = toDir.appendingPathComponent(src.lastPathComponent)
                    copyReplaceFile(from: src, to: dest)
                }
            }
        } catch {
            // Best-effort only.
        }
    }

    private static func copyReplaceFile(from src: URL, to dest: URL) {
        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            // Data roundtrip is robust & avoids cross-volume copy quirks.
            let data = try Data(contentsOf: src)
            try data.write(to: dest, options: [.atomic])
        } catch {
            // Best-effort only.
        }
    }
    
    /// Deletes old ZIP files in ArkivExports to avoid unbounded growth.
    /// Keeps the newest `keepingLatest` files by modification date.
    static func cleanupArchiveExports(keepingLatest: Int = 3) {
        guard keepingLatest >= 0 else { return }

        do {
            let urls = try fm.contentsOfDirectory(
                at: archiveExportsDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            let zipFiles: [(url: URL, mtime: Date)] = urls.compactMap { url in
                guard url.pathExtension.lowercased() == "zip" else { return nil }
                let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard (rv?.isRegularFile ?? true) else { return nil }
                return (url, rv?.contentModificationDate ?? Date.distantPast)
            }

            let sorted = zipFiles.sorted { $0.mtime > $1.mtime } // newest first
            let keepSet = Set(sorted.prefix(keepingLatest).map { $0.url.path })

            for item in sorted where !keepSet.contains(item.url.path) {
                try? fm.removeItem(at: item.url)
            }

            LogManager.shared.log(
                category: .taskScheduler,
                message: "ArchiveManager - cleanupArchiveExports complete (kept \(keepingLatest))",
                isDebug: true
            )
            print("📦 ArchiveManager - cleanupArchiveExports complete (kept \(keepingLatest))")

        } catch {
            LogManager.shared.log(
                category: .taskScheduler,
                message: "ArchiveManager - cleanupArchiveExports failed: \(error)",
                isDebug: true
            )
            print("📦 ArchiveManager - cleanupArchiveExports failed: \(error)")
        }
    }
    
    /// Ensures a month-scoped ZIP exists in the user-visible Documents folder.
    /// Output: Documents/LoopFollow/Ziparkiv/LoopFollow-Arkiv-YYYY-MM.zip
    /// Best-effort: overwrites existing file so the export stays in sync.
    private static func exportMonthlyZipToDocuments(monthFolderName: String) {
        do {
            try fm.createDirectory(at: documentsZipArchiveDir, withIntermediateDirectories: true)

            let sourceMonthDir = archiveRootDir.appendingPathComponent(monthFolderName, isDirectory: true)
            guard fm.fileExists(atPath: sourceMonthDir.path) else {
                LogManager.shared.log(category: .taskScheduler, message: "ArchiveManager - monthly zip export skipped (month folder missing): \(monthFolderName)")
                return
            }

            let destZipURL = documentsZipArchiveDir
                .appendingPathComponent("LoopFollow-Arkiv-\(monthFolderName)")
                .appendingPathExtension("zip")

            if fm.fileExists(atPath: destZipURL.path) {
                try? fm.removeItem(at: destZipURL)
            }

            // ZIPFoundation extends FileManager with zipItem/unzipItem.
            // shouldKeepParent=true keeps the top-level "YYYY-MM" folder inside the zip.
            try fm.zipItem(at: sourceMonthDir, to: destZipURL, shouldKeepParent: true)

            LogManager.shared.log(category: .taskScheduler, message: "ArchiveManager - exported monthly zip to Documents: \(destZipURL.lastPathComponent)")
            print("📦 ArchiveManager - exported monthly zip to Documents: \(destZipURL.lastPathComponent)")
        } catch {
            LogManager.shared.log(category: .taskScheduler, message: "ArchiveManager - monthly zip export to Documents failed: \(error)")
            print("📦 ArchiveManager - monthly zip export to Documents failed: \(error)")
        }
    }
    
    /// One-time migration helper. If the old directory exists and the new directory does not,
    /// move the old directory into the new location.
    private static func migrateIfNeeded(from oldDir: URL, to newDir: URL) {
        // Only migrate if old exists and new doesn't.
        guard fm.fileExists(atPath: oldDir.path) else { return }
        guard !fm.fileExists(atPath: newDir.path) else { return }

        do {
            // Ensure parent exists
            try fm.createDirectory(at: newDir.deletingLastPathComponent(), withIntermediateDirectories: true)

            try fm.moveItem(at: oldDir, to: newDir)

            LogManager.shared.log(category: .taskScheduler, message: "ArchiveManager - migrated folder: \(oldDir.path) → \(newDir.path)")
            print("📦 ArchiveManager - migrated folder: \(oldDir.path) → \(newDir.path)")
        } catch {
            // Best-effort only. If move fails, we leave old in place.
            LogManager.shared.log(category: .taskScheduler, message: "ArchiveManager - migration failed: \(error)", isDebug: true)
            print("📦 ArchiveManager - migration failed: \(error)")
        }
    }

    private static let isoDayFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
    
}
