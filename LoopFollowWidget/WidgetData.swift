// LoopFollow
// WidgetData.swift
// Shared data model between the watch app and widget extension.

import Foundation

struct WidgetBGPoint: Codable, Hashable {
    let value: Int      // mg/dL
    let timestamp: Date
}

struct WidgetData: Codable {
    let bgValue: Int        // current BG in mg/dL
    let direction: String   // trend arrow
    let delta: Int?         // signed delta from previous reading
    let bgTimestamp: Date   // when the current BG was recorded
    let iob: Double?
    let cob: Double?
    let basalRate: Double?      // current enacted rate
    let scheduledBasal: Double? // profile-based rate
    let history: [WidgetBGPoint] // last ~3 hours
    let units: String       // "mg/dL" or "mmol/L"
    let updatedAt: Date     // when this snapshot was written

    private static let storageKey = "widgetData"

    /// App Group shared between the watch app and widget extension.
    /// Both targets must have this App Group in their entitlements.
    static var appGroupID: String {
        guard let identifier = Bundle.main.object(
            forInfoDictionaryKey: "AppGroupIdentifier"
        ) as? String,
            !identifier.isEmpty
        else {
            assertionFailure("Missing AppGroupIdentifier in Info.plist")
            return "group.com.LoopFollow"
        }

        return identifier
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else {
            print("WidgetData.save encode failed")
            return
        }
        print("WidgetData.save appGroup=\(Self.appGroupID) bg=\(bgValue) history=\(history.count)")
        Self.sharedDefaults.set(data, forKey: Self.storageKey)
    }

    static func load() -> WidgetData? {
        guard let data = sharedDefaults.data(forKey: Self.storageKey) else {
            print("WidgetData.load no data in app group \(appGroupID)")
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(WidgetData.self, from: data) else {
            print("WidgetData.load decode failed")
            return nil
        }
        print("WidgetData.load success bg=\(decoded.bgValue) history=\(decoded.history.count)")
        return decoded
    }
}
