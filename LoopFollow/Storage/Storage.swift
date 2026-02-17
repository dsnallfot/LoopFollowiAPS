//
//  Storage.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-08-25.

//

import Foundation
import HealthKit

class Storage {
    var remoteType = StorageValue<RemoteType>(key: "remoteType", defaultValue: .nightscout)
    var deviceToken = StorageValue<String>(key: "deviceToken", defaultValue: "")
    var sharedSecret = StorageValue<String>(key: "sharedSecret", defaultValue: "")
    var productionEnvironment = StorageValue<Bool>(key: "productionEnvironment", defaultValue: true)
    var apnsKey = StorageValue<String>(key: "apnsKey", defaultValue: "")
    var teamId = StorageValue<String?>(key: "teamId", defaultValue: nil)
    var keyId = StorageValue<String>(key: "keyId", defaultValue: "")
    var bundleId = StorageValue<String>(key: "bundleId", defaultValue: "")
    var user = StorageValue<String>(key: "user", defaultValue: "")

    var maxBolus = SecureStorageValue<HKQuantity>(key: "maxBolus", defaultValue: HKQuantity(unit: .internationalUnit(), doubleValue: 1.0))
    var maxCarbs = SecureStorageValue<HKQuantity>(key: "maxCarbs", defaultValue: HKQuantity(unit: .gram(), doubleValue: 30.0))
    var maxProtein = SecureStorageValue<HKQuantity>(key: "maxProtein", defaultValue: HKQuantity(unit: .gram(), doubleValue: 30.0))
    var maxFat = SecureStorageValue<HKQuantity>(key: "maxFat", defaultValue: HKQuantity(unit: .gram(), doubleValue: 30.0))

    var mealWithBolus = StorageValue<Bool>(key: "mealWithBolus", defaultValue: false)
    var mealWithFatProtein = StorageValue<Bool>(key: "mealWithFatProtein", defaultValue: false)

    var cachedJWT = StorageValue<String?>(key: "cachedJWT", defaultValue: nil)
    var jwtExpirationDate = StorageValue<Date?>(key: "jwtExpirationDate", defaultValue: nil)

    var backgroundRefreshType = StorageValue<BackgroundRefreshType>(key: "backgroundRefreshType", defaultValue: .silentTune)

    var selectedBLEDevice = StorageValue<BLEDevice?>(key: "selectedBLEDevice", defaultValue: nil)
    
    var debugLogLevel = StorageValue<Bool>(key: "debugLogLevel", defaultValue: false)
    var tempDebugLogLevel = StorageValue<Bool>(key: "tempDebugLogLevel", defaultValue: false)
    
    var uploadAppStartNote = StorageValue<Bool>(key: "uploadAppStartNote", defaultValue: false)
    
    var sensorScheduleOffset = StorageValue<Double?>(key: "sensorScheduleOffset", defaultValue: nil)

    // Persist latest Bluetooth heartbeat so UI can show a value immediately after app restart
    var lastBluetoothHeartbeatDate = StorageValue<Date?>(key: "lastBluetoothHeartbeatDate", defaultValue: nil)

    // Statistics display preferences
    var showGMI = StorageValue<Bool>(key: "showGMI", defaultValue: true)
    var showStdDev = StorageValue<Bool>(key: "showStdDev", defaultValue: true)
    var showAvgGlucose = StorageValue<Bool>(key: "showAvgGlucose", defaultValue: true)
    var showTITR = StorageValue<Bool>(key: "showTITR", defaultValue: true)
    var showFPU = StorageValue<Bool>(key: "showFPU", defaultValue: false)
    var showSMB = StorageValue<Bool>(key: "showSMB", defaultValue: false)
    var showDextroAmount = StorageValue<Bool>(key: "showDextroAmount", defaultValue: false)
    var showProfileBasal = StorageValue<Bool>(key: "showProfileBasal", defaultValue: false)
    var showLowPercentage = StorageValue<Bool>(key: "showLowPercentage", defaultValue: false)
    
    static let shared = Storage()

    private init() { }
}

struct SensorStartHistoryEntry: Codable, Equatable {
    var date: TimeInterval
    var note: String
    /// Optional, persisted summary of sensor error analysis (text shown in alert)
    var sensorErrors: String?

    static func == (lhs: SensorStartHistoryEntry, rhs: SensorStartHistoryEntry) -> Bool {
        return lhs.date == rhs.date && lhs.note == rhs.note
    }

    /// Extracts sensor ID and formatted activation date from note string.
    var extractedSensorInfo: (id: String, activationDate: String)? {
        // Clean string (trim whitespace, normalize spaces)
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                              .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Updated regex (case-insensitive, flexible format)
        let regexPattern = #"([A-Za-z0-9]{6})\s+activated\s+on\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s*(?:\+\d{4})?"#

        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: cleanedNote, options: [], range: NSRange(location: 0, length: cleanedNote.utf16.count)) else {
            LogManager.shared.log(category: .bluetooth, message: "❌ Regex failed to match sensor start note -> '\(cleanedNote)'")
            return nil
        }

        if let sensorIDRange = Range(match.range(at: 1), in: cleanedNote),
           let dateRange = Range(match.range(at: 2), in: cleanedNote) {
            let sensorID = String(cleanedNote[sensorIDRange])
            let activationDate = String(cleanedNote[dateRange])

            return (sensorID, activationDate)
        }

        LogManager.shared.log(category: .bluetooth, message: "❌ Failed to extract ID or Date from sensor start note -> '\(cleanedNote)'")
        return nil
    }
}

// Dexcom sensor error outage cache item (derived from Note + SGV span)
struct DexcomSensorErrorOutageCacheItem: Codable, Equatable {
    /// The Dexcom Note timestamp (seconds since 1970)
    var noteTimestamp: TimeInterval
    /// Outage start time (seconds since 1970)
    var startTimestamp: TimeInterval
    /// Outage end time (seconds since 1970)
    var endTimestamp: TimeInterval
    var notesText: String?
    var enteredBy: String?
}

struct PumpChangeHistoryEntry: Codable, Equatable {
    /// Unix timestamp (seconds since 1970) for when the pump was changed.
    var date: TimeInterval

    static func == (lhs: PumpChangeHistoryEntry, rhs: PumpChangeHistoryEntry) -> Bool {
        return lhs.date == rhs.date
    }
}

struct AlarmHistoryEntry: Codable, Equatable {
    /// Unix timestamp (seconds since 1970) for when the alarm was triggered.
    var date: TimeInterval

    /// Human readable message (e.g. "Alarm triggered: ⚠️ Akut lågt!")
    var message: String

    /// Optional raw alarm label (e.g. AlarmSound.whichAlarm)
    var alarmLabel: String?

    static func == (lhs: AlarmHistoryEntry, rhs: AlarmHistoryEntry) -> Bool {
        return lhs.date == rhs.date && lhs.message == rhs.message && lhs.alarmLabel == rhs.alarmLabel
    }
}

struct UserProfileEntry: Codable, Equatable {
    var name: String
    var birthDate: Date?
    var t1dSince: Date?
    var heightCm: Double?
    var weightKg: Double?
    var tdd: Double?
    var hbA1c: Double?
    var actualBasal: Double?
    var actualMorningCR: Double?
    var actualDayCR: Double?
    var actualAverageISF: Double?
    var updatedAt: Date

    // För framtida CSV-export/import lagrar vi även de kalkylerade fälten
    var insulinPerKg: Double?
    var walsh500CR: Double?
    var walsh300CR: Double?
    var walshWeightCR: Double?
    var walsh100ISF: Double?
    var walshTDD: Double?
    var walshBasal: Double?
    var walshBasalPerHour: Double?
    var actualBasalPerHour: Double?
}

extension UserProfileEntry {
    fileprivate static let csvDateFormatter: ISO8601DateFormatter = {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]
        return df
    }()

    fileprivate static func csvString(from date: Date?) -> String {
        guard let date else { return "" }
        return csvDateFormatter.string(from: date)
    }

    fileprivate static func csvString(from value: Double?, decimals: Int = 4) -> String {
        guard let value else { return "" }
        return String(format: "%.\(decimals)f", value)
    }
}

extension Storage {
    var sensorStartNotes: [SensorStartHistoryEntry] {
        get {
            guard let storedData = UserDefaults.standard.data(forKey: "sensorStartNotes") else {
                return []
            }
            do {
                let decodedNotes = try JSONDecoder().decode([SensorStartHistoryEntry].self, from: storedData)
                return decodedNotes
            } catch {
                LogManager.shared.log(category: .bluetooth, message: "Failed to decode sensorStartNotes, resetting to empty array: \(error)")
                UserDefaults.standard.removeObject(forKey: "sensorStartNotes")
                return []
            }
        }
        set {
            do {
                let encodedData = try JSONEncoder().encode(newValue)
                UserDefaults.standard.set(encodedData, forKey: "sensorStartNotes")
            } catch {
                LogManager.shared.log(category: .bluetooth, message: "Failed to encode sensorStartNotes: \(error)")
            }
        }
    }
    
    var pumpChangeHistory: [PumpChangeHistoryEntry] {
        get {
            guard let storedData = UserDefaults.standard.data(forKey: "pumpChangeHistory") else {
                return []
            }
            do {
                let decoded = try JSONDecoder().decode([PumpChangeHistoryEntry].self, from: storedData)
                return decoded
            } catch {
                LogManager.shared.log(
                    category: .treatments,
                    message: "Failed to decode pumpChangeHistory, resetting to empty array: \(error)"
                )
                UserDefaults.standard.removeObject(forKey: "pumpChangeHistory")
                return []
            }
        }
        set {
            do {
                let encoded = try JSONEncoder().encode(newValue)
                UserDefaults.standard.set(encoded, forKey: "pumpChangeHistory")
            } catch {
                LogManager.shared.log(
                    category: .treatments,
                    message: "Failed to encode pumpChangeHistory: \(error)"
                )
            }
        }
    }
    
    // MARK: - Alarm history (for visualization / analytics)

    var alarmHistory: [AlarmHistoryEntry] {
        get {
            guard let storedData = UserDefaults.standard.data(forKey: "alarmHistory") else {
                return []
            }
            do {
                return try JSONDecoder().decode([AlarmHistoryEntry].self, from: storedData)
            } catch {
                LogManager.shared.log(category: .alarm, message: "Failed to decode alarmHistory, resetting to empty array: \(error)")
                UserDefaults.standard.removeObject(forKey: "alarmHistory")
                return []
            }
        }
        set {
            do {
                let encoded = try JSONEncoder().encode(newValue)
                UserDefaults.standard.set(encoded, forKey: "alarmHistory")
            } catch {
                LogManager.shared.log(category: .alarm, message: "Failed to encode alarmHistory: \(error)")
            }
        }
    }

    /// Appends an alarm history entry and keeps the history bounded.
    func appendAlarmHistory(
        alarmLabel: String?,
        message: String,
        date: TimeInterval = Date().timeIntervalSince1970,
        maxEntries: Int = 9000
    ) {
        var history = alarmHistory
        history.append(AlarmHistoryEntry(date: date, message: message, alarmLabel: alarmLabel))

        // Keep only the newest N entries
        if history.count > maxEntries {
            history = Array(history.suffix(maxEntries))
        }

        alarmHistory = history
    }
    
    // MARK: - Dexcom sensorfel outage cache (for reklamationer)

    var dexcomSensorErrorOutagesCache: [DexcomSensorErrorOutageCacheItem] {
        get {
            guard let storedData = UserDefaults.standard.data(forKey: "dexcomSensorErrorOutagesCache") else {
                return []
            }
            do {
                return try JSONDecoder().decode([DexcomSensorErrorOutageCacheItem].self, from: storedData)
            } catch {
                LogManager.shared.log(category: .dexcom, message: "Failed to decode dexcomSensorErrorOutagesCache, resetting: \(error)")
                UserDefaults.standard.removeObject(forKey: "dexcomSensorErrorOutagesCache")
                return []
            }
        }
        set {
            do {
                let encodedData = try JSONEncoder().encode(newValue)
                UserDefaults.standard.set(encodedData, forKey: "dexcomSensorErrorOutagesCache")
            } catch {
                LogManager.shared.log(category: .dexcom, message: "Failed to encode dexcomSensorErrorOutagesCache: \(error)")
            }
        }
    }

    var dexcomSensorErrorOutagesRefreshedAt: Date? {
        get { UserDefaults.standard.object(forKey: "dexcomSensorErrorOutagesRefreshedAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "dexcomSensorErrorOutagesRefreshedAt") }
    }
    
    // MARK: - User profile history

    var userProfiles: [UserProfileEntry] {
        get {
            guard let storedData = UserDefaults.standard.data(forKey: "userProfiles") else {
                return []
            }
            do {
                return try JSONDecoder().decode([UserProfileEntry].self, from: storedData)
            } catch {
                LogManager.shared.log(
                    category: .treatments,
                    message: "Failed to decode userProfiles, resetting to empty array: \(error)"
                )
                UserDefaults.standard.removeObject(forKey: "userProfiles")
                return []
            }
        }
        set {
            do {
                let encoded = try JSONEncoder().encode(newValue)
                UserDefaults.standard.set(encoded, forKey: "userProfiles")
            } catch {
                LogManager.shared.log(
                    category: .treatments,
                    message: "Failed to encode userProfiles: \(error)"
                )
            }
        }
    }

    /// Exports all userProfiles as CSV text.
    /// Columns: updatedAt,name,birthDate,t1dSince,heightCm,weightKg,tdd,hbA1c,actualBasal,actualMorningCR,actualDayCR,actualAverageISF,insulinPerKg,walsh500CR,walsh300CR,walshWeightCR,walsh100ISF,walshTDD,walshBasal,walshBasalPerHour,actualBasalPerHour
    func exportUserProfilesCSV() -> String {
        let header = [
            "updatedAt",
            "name",
            "birthDate",
            "t1dSince",
            "heightCm",
            "weightKg",
            "tdd",
            "hbA1c",
            "actualBasal",
            "actualMorningCR",
            "actualDayCR",
            "actualAverageISF",
            "insulinPerKg",
            "walsh500CR",
            "walsh300CR",
            "walshWeightCR",
            "walsh100ISF",
            "walshTDD",
            "walshBasal",
            "walshBasalPerHour",
            "actualBasalPerHour"
        ].joined(separator: ",")

        let sortedProfiles = userProfiles.sorted { $0.updatedAt < $1.updatedAt }

        let rows: [String] = sortedProfiles.map { entry in
            let cols: [String] = [
                UserProfileEntry.csvString(from: entry.updatedAt),
                entry.name,
                UserProfileEntry.csvString(from: entry.birthDate),
                UserProfileEntry.csvString(from: entry.t1dSince),
                UserProfileEntry.csvString(from: entry.heightCm, decimals: 2),
                UserProfileEntry.csvString(from: entry.weightKg, decimals: 2),
                UserProfileEntry.csvString(from: entry.tdd, decimals: 2),
                UserProfileEntry.csvString(from: entry.hbA1c, decimals: 2),
                UserProfileEntry.csvString(from: entry.actualBasal, decimals: 2),
                UserProfileEntry.csvString(from: entry.actualMorningCR, decimals: 2),
                UserProfileEntry.csvString(from: entry.actualDayCR, decimals: 2),
                UserProfileEntry.csvString(from: entry.actualAverageISF, decimals: 2),
                UserProfileEntry.csvString(from: entry.insulinPerKg, decimals: 4),
                UserProfileEntry.csvString(from: entry.walsh500CR, decimals: 2),
                UserProfileEntry.csvString(from: entry.walsh300CR, decimals: 2),
                UserProfileEntry.csvString(from: entry.walshWeightCR, decimals: 2),
                UserProfileEntry.csvString(from: entry.walsh100ISF, decimals: 2),
                UserProfileEntry.csvString(from: entry.walshTDD, decimals: 2),
                UserProfileEntry.csvString(from: entry.walshBasal, decimals: 2),
                UserProfileEntry.csvString(from: entry.walshBasalPerHour, decimals: 4),
                UserProfileEntry.csvString(from: entry.actualBasalPerHour, decimals: 4)
            ]
            return cols.joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n")
    }

    /// Imports user profile data from CSV text.
    /// Rows must match the header produced by exportUserProfilesCSV().
    /// When merging, we de-duplicate by updatedAt calendar day and keep the *latest* entry for each day.
    func importUserProfilesCSV(from csv: String) {
        let lines = csv
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return }

        // Assume first non-empty line is header and ignore it.
        let dataLines = Array(lines.dropFirst())

        let dateFormatter = UserProfileEntry.csvDateFormatter

        var imported: [UserProfileEntry] = []
        imported.reserveCapacity(dataLines.count)

        for line in dataLines {
            let columns = line.components(separatedBy: ",")
            // Expect at least the 21 columns we write out
            guard columns.count >= 21 else { continue }

            func parseDate(_ s: String) -> Date? {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return dateFormatter.date(from: trimmed)
            }

            func parseDouble(_ s: String) -> Double? {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                // Force dot as decimal separator regardless of locale
                let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
                return Double(normalized)
            }

            let updatedAtString = columns[0]
            guard let updatedAt = parseDate(updatedAtString) else { continue }

            let name = columns[1]

            let birthDate = parseDate(columns[2])
            let t1dSince = parseDate(columns[3])
            let heightCm = parseDouble(columns[4])
            let weightKg = parseDouble(columns[5])
            let tdd = parseDouble(columns[6])
            let hbA1c = parseDouble(columns[7])
            let actualBasal = parseDouble(columns[8])
            let actualMorningCR = parseDouble(columns[9])
            let actualDayCR = parseDouble(columns[10])
            let actualAverageISF = parseDouble(columns[11])
            let insulinPerKg = parseDouble(columns[12])
            let walsh500CR = parseDouble(columns[13])
            let walsh300CR = parseDouble(columns[14])
            let walshWeightCR = parseDouble(columns[15])
            let walsh100ISF = parseDouble(columns[16])
            let walshTDD = parseDouble(columns[17])
            let walshBasal = parseDouble(columns[18])
            let walshBasalPerHour = parseDouble(columns[19])
            let actualBasalPerHour = parseDouble(columns[20])

            let entry = UserProfileEntry(
                name: name,
                birthDate: birthDate,
                t1dSince: t1dSince,
                heightCm: heightCm,
                weightKg: weightKg,
                tdd: tdd,
                hbA1c: hbA1c,
                actualBasal: actualBasal,
                actualMorningCR: actualMorningCR,
                actualDayCR: actualDayCR,
                actualAverageISF: actualAverageISF,
                updatedAt: updatedAt,
                insulinPerKg: insulinPerKg,
                walsh500CR: walsh500CR,
                walsh300CR: walsh300CR,
                walshWeightCR: walshWeightCR,
                walsh100ISF: walsh100ISF,
                walshTDD: walshTDD,
                walshBasal: walshBasal,
                walshBasalPerHour: walshBasalPerHour,
                actualBasalPerHour: actualBasalPerHour
            )

            imported.append(entry)
        }

        guard !imported.isEmpty else { return }

        // Merge with existing, then de-duplicate by calendar day (local time)
        let calendar = Calendar.current
        let existing = userProfiles

        var mergedByDay: [String: UserProfileEntry] = [:]

        func dayKey(for date: Date) -> String {
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            let y = comps.year ?? 0
            let m = comps.month ?? 0
            let d = comps.day ?? 0
            return String(format: "%04d-%02d-%02d", y, m, d)
        }

        for entry in existing + imported {
            let key = dayKey(for: entry.updatedAt)
            if let current = mergedByDay[key] {
                // Keep the latest updatedAt for that day
                if entry.updatedAt > current.updatedAt {
                    mergedByDay[key] = entry
                }
            } else {
                mergedByDay[key] = entry
            }
        }

        let mergedArray = mergedByDay.values.sorted { $0.updatedAt > $1.updatedAt }
        userProfiles = mergedArray

        // Notify listeners (UserDataViewController, etc.) that profiles have changed
        NotificationCenter.default.post(name: .userProfileUpdated, object: nil)
    }
}

extension Storage {
    /// Finds the most recent activation date for a given sensor ID.
    func latestActivationDate(for sensorID: String) -> String? {
        let sensorNotes = sensorStartNotes
        let matchingNotes = sensorNotes.compactMap { entry -> String? in
            if let extracted = entry.extractedSensorInfo, extracted.id == sensorID {
                return extracted.activationDate
            }
            return nil
        }

        return matchingNotes.sorted().last // Return the latest activation date if found.
    }
}
