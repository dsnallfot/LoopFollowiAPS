// NSProfile.swift
// LoopFollow
// Created by Jonas Björkert on 2024-07-12.
// Copyright © 2024 Jon Fawcett. All rights reserved.

import Foundation

struct NSProfile: Decodable {
    struct Store: Decodable {
        struct BasalEntry: Decodable {
            let value: Double
            let time: String
            let timeAsSeconds: Double
        }
        struct SensEntry: Decodable {
            let value: Double
            let time: String
            let timeAsSeconds: Double
        }
        struct CarbRatioEntry: Decodable {
            let value: Double
            let time: String
            let timeAsSeconds: Double
        }
        struct OverrideEntry: Decodable {
            let name: String?
            let targetRange: [Double]?
            let duration: Int?
            let insulinNeedsScaleFactor: Double?
            let symbol: String?
        }
        struct TargetEntry: Decodable {
            let value: Double
            let time: String
            let timeAsSeconds: Double
        }

        let basal: [BasalEntry]
        let sens: [SensEntry]
        let carbratio: [CarbRatioEntry]
        let overrides: [OverrideEntry]?
        let target_high: [TargetEntry]?
        let target_low: [TargetEntry]?
        let timezone: String
        let units: String
    }
    
    // New nested struct to decode preferences
        struct NSProfilePreferences: Decodable {
            let report: String
            let preferences: [String: String]
            
            private enum CodingKeys: String, CodingKey {
                case report
                case preferences
            }
            
            // Custom decoding to convert any value (number, boolean, etc.) to a String
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                report = try container.decode(String.self, forKey: .report)
                let prefsContainer = try container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: .preferences)
                var tempPrefs: [String: String] = [:]
                for key in prefsContainer.allKeys {
                    if let value = try? prefsContainer.decode(String.self, forKey: key) {
                        tempPrefs[key.stringValue] = value
                    } else if let value = try? prefsContainer.decode(Double.self, forKey: key) {
                        tempPrefs[key.stringValue] = String(value)
                    } else if let value = try? prefsContainer.decode(Bool.self, forKey: key) {
                        tempPrefs[key.stringValue] = String(value)
                    } else {
                        tempPrefs[key.stringValue] = "unknown"
                    }
                }
                preferences = tempPrefs
            }
            
            // DynamicCodingKeys to iterate through the keys of the preferences dictionary
            struct DynamicCodingKeys: CodingKey {
                var stringValue: String
                init?(stringValue: String) {
                    self.stringValue = stringValue
                }
                var intValue: Int? { nil }
                init?(intValue: Int) {
                    return nil
                }
            }
        }

    let store: [String: Store]
    let defaultProfile: String
    let units: String

    let bundleIdentifier: String?
    let isAPNSProduction: Bool?
    let deviceToken: String?
    let teamID: String?

    // Updated TrioOverrideEntry to include the extra properties
        struct TrioOverrideEntry: Decodable {
            let name: String
            let duration: Double?
            let percentage: Double?
            let target: Double?
            let smbMinutes: Double?
            let uamMinutes: Double?
            let smbIsOff: Bool?
        }
    
    let trioOverrides: [TrioOverrideEntry]?
    
    // New property for the preferences object
    let nsPreferences: NSProfilePreferences?
        
    // New properties for expiration date
    let trioExpirationDateString: String?
    let trioExpirationDate: Date?
    let trioExpirationFormatted: String?

    enum CodingKeys: String, CodingKey {
        case store
        case defaultProfile
        case units
        case bundleIdentifier
        case isAPNSProduction
        case deviceToken
        case trioOverrides = "overridePresets"
        case teamID
        case nsPreferences = "preferences"
        case trioExpirationDateString = "expirationDate" // Maps JSON key "expirationDate"
    }
    
    // Custom initializer to parse expiration date
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            store = try container.decode([String: Store].self, forKey: .store)
            defaultProfile = try container.decode(String.self, forKey: .defaultProfile)
            units = try container.decode(String.self, forKey: .units)
            bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
            isAPNSProduction = try container.decodeIfPresent(Bool.self, forKey: .isAPNSProduction)
            deviceToken = try container.decodeIfPresent(String.self, forKey: .deviceToken)
            teamID = try container.decodeIfPresent(String.self, forKey: .teamID)
            trioOverrides = try container.decodeIfPresent([TrioOverrideEntry].self, forKey: .trioOverrides)
            nsPreferences = try container.decodeIfPresent(NSProfilePreferences.self, forKey: .nsPreferences)

            // Decode Trio expiration date
            trioExpirationDateString = try container.decodeIfPresent(String.self, forKey: .trioExpirationDateString)

            if let expirationString = trioExpirationDateString {
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                
                if let parsedDate = isoFormatter.date(from: expirationString) {
                    trioExpirationDate = parsedDate
                    
                    // Format it into "YYYY-MM-DD, HH:mm"
                    let displayFormatter = DateFormatter()
                    displayFormatter.dateFormat = "yyyy-MM-dd, HH:mm"
                    displayFormatter.locale = Locale(identifier: "en_US_POSIX")
                    displayFormatter.timeZone = TimeZone.current  // Adjust to the user's local time zone
                    
                    trioExpirationFormatted = displayFormatter.string(from: parsedDate)
                } else {
                    trioExpirationDate = nil
                    trioExpirationFormatted = "Unknown"
                }
            } else {
                trioExpirationDate = nil
                trioExpirationFormatted = "Unknown"
            }
        }
}
