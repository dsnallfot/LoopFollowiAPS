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

struct UserProfileEntry: Codable, Equatable {
    var name: String
    var birthDate: Date?
    var t1dSince: Date?
    var heightCm: Double?
    var weightKg: Double?
    var tdd: Double?
    var hbA1c: Double?
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
