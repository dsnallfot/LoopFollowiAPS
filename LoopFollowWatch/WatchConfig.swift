// LoopFollow
// WatchConfig.swift


import Foundation

struct WatchComboPreset: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let carbsGrams: Int
    let proteinGrams: Int
    let fatGrams: Int
    let bolusUnits: Double
    let notes: String
    let overrideName: String?

    init(from dict: [String: Any]) {
        id = dict["id"] as? String ?? UUID().uuidString
        name = dict["name"] as? String ?? "Snabbval"
        carbsGrams = WatchComboPreset.intValue(dict["carbsGrams"])
        proteinGrams = WatchComboPreset.intValue(dict["proteinGrams"])
        fatGrams = WatchComboPreset.intValue(dict["fatGrams"])
        bolusUnits = WatchComboPreset.doubleValue(dict["bolusUnits"])
        notes = dict["notes"] as? String ?? ""

        let rawOverrideName = dict["overrideName"] as? String ?? ""
        let trimmedOverrideName = rawOverrideName.trimmingCharacters(in: .whitespacesAndNewlines)
        overrideName = trimmedOverrideName.isEmpty ? nil : trimmedOverrideName
    }

    func toDictionary() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "carbsGrams": carbsGrams,
            "proteinGrams": proteinGrams,
            "fatGrams": fatGrams,
            "bolusUnits": bolusUnits,
            "notes": notes,
            "overrideName": overrideName ?? "",
        ]
    }

    private static func intValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    private static func doubleValue(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) ?? 0 }
        return 0
    }
}

struct WatchConfig: Equatable {
    var nsURL: String
    var nsToken: String
    var dexUsername: String
    var dexPassword: String
    var dexServer: String // "US" or "NON_US"
    var units: String // "mg/dL" or "mmol/L"
    var lowLine: Double
    var highLine: Double

    // Remote control fields
    var remoteType: String // "None", "Nightscout", "Trio Remote Control", "Loop APNS"
    var maxBolus: Double
    var maxCarbs: Double

    // TRC APNS credentials
    var trcDeviceToken: String
    var trcSharedSecret: String
    var trcApnsKey: String
    var trcKeyId: String
    var trcTeamId: String
    var trcBundleId: String
    var trcProductionEnv: Bool
    var trcUser: String

    // Nightscout write auth
    var nsWriteAuth: Bool

    // Meal settings (synced from iPhone)
    var mealWithFatProtein: Bool
    var maxProtein: Double
    var maxFat: Double

    // Combo presets synced from iPhone
    var comboPresets: [WatchComboPreset]

    var hasDexcomCredentials: Bool {
        !dexUsername.isEmpty && !dexPassword.isEmpty
    }

    var hasNightscoutURL: Bool {
        !nsURL.isEmpty
    }

    var hasAnySource: Bool {
        hasDexcomCredentials || hasNightscoutURL
    }

    var remoteEnabled: Bool {
        remoteType != "None"
    }

    var dexServerURL: String {
        dexServer == "US"
            ? "https://share2.dexcom.com"
            : "https://shareous1.dexcom.com"
    }

    func toDictionary() -> [String: Any] {
        [
            "nsURL": nsURL,
            "nsToken": nsToken,
            "dexUsername": dexUsername,
            "dexPassword": dexPassword,
            "dexServer": dexServer,
            "units": units,
            "lowLine": lowLine,
            "highLine": highLine,
            "remoteType": remoteType,
            "maxBolus": maxBolus,
            "maxCarbs": maxCarbs,
            "trcDeviceToken": trcDeviceToken,
            "trcSharedSecret": trcSharedSecret,
            "trcApnsKey": trcApnsKey,
            "trcKeyId": trcKeyId,
            "trcTeamId": trcTeamId,
            "trcBundleId": trcBundleId,
            "trcProductionEnv": trcProductionEnv,
            "trcUser": trcUser,
            "nsWriteAuth": nsWriteAuth,
            "mealWithFatProtein": mealWithFatProtein,
            "maxProtein": maxProtein,
            "maxFat": maxFat,
            "comboPresets": comboPresets.map { $0.toDictionary() },
        ]
    }

    init(from dict: [String: Any]) {
        nsURL = dict["nsURL"] as? String ?? ""
        nsToken = dict["nsToken"] as? String ?? ""
        dexUsername = dict["dexUsername"] as? String ?? ""
        dexPassword = dict["dexPassword"] as? String ?? ""
        dexServer = dict["dexServer"] as? String ?? "US"
        units = dict["units"] as? String ?? "mg/dL"
        lowLine = dict["lowLine"] as? Double ?? 70.0
        highLine = dict["highLine"] as? Double ?? 180.0
        remoteType = dict["remoteType"] as? String ?? "None"
        maxBolus = dict["maxBolus"] as? Double ?? 10.0
        maxCarbs = dict["maxCarbs"] as? Double ?? 100.0
        trcDeviceToken = dict["trcDeviceToken"] as? String ?? ""
        trcSharedSecret = dict["trcSharedSecret"] as? String ?? ""
        trcApnsKey = dict["trcApnsKey"] as? String ?? ""
        trcKeyId = dict["trcKeyId"] as? String ?? ""
        trcTeamId = dict["trcTeamId"] as? String ?? ""
        trcBundleId = dict["trcBundleId"] as? String ?? ""
        trcProductionEnv = dict["trcProductionEnv"] as? Bool ?? false
        trcUser = dict["trcUser"] as? String ?? ""
        nsWriteAuth = dict["nsWriteAuth"] as? Bool ?? false
        mealWithFatProtein = dict["mealWithFatProtein"] as? Bool ?? false
        maxProtein = dict["maxProtein"] as? Double ?? 30.0
        maxFat = dict["maxFat"] as? Double ?? 30.0
        let comboPresetDictionaries = dict["comboPresets"] as? [[String: Any]] ?? []
        comboPresets = comboPresetDictionaries.map { WatchComboPreset(from: $0) }
    }
/*
    func saveToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(toDictionary(), forKey: "watchConfig")

        // Also mirror NS credentials to the App Group so the widget extension
        // (a separate process) can fetch BG directly from Nightscout.
        if let shared = UserDefaults(suiteName: WidgetData.appGroupID) {
            shared.set(nsURL, forKey: "nsURL")
            shared.set(nsToken, forKey: "nsToken")
        }
    }
    */
    func saveToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(toDictionary(), forKey: "watchConfig")
        defaults.set(nsURL, forKey: "nsURL")
        defaults.set(nsToken, forKey: "nsToken")

        if let shared = UserDefaults(suiteName: WidgetData.appGroupID) {
            shared.set(nsURL, forKey: "nsURL")
            shared.set(nsToken, forKey: "nsToken")
            shared.synchronize()

            print("Saved widget config to app group. nsURL empty: \(nsURL.isEmpty), token empty: \(nsToken.isEmpty)")
        } else {
            print("Failed to open app group defaults: \(WidgetData.appGroupID)")
        }
    }

    static func loadFromDefaults() -> WatchConfig? {
        if let dict = UserDefaults.standard.dictionary(forKey: "watchConfig") {
            return WatchConfig(from: dict)
        }

        let nsURL = UserDefaults.standard.string(forKey: "nsURL") ?? ""
        let nsToken = UserDefaults.standard.string(forKey: "nsToken") ?? ""

        if !nsURL.isEmpty || !nsToken.isEmpty {
            var dict: [String: Any] = [:]
            dict["nsURL"] = nsURL
            dict["nsToken"] = nsToken
            return WatchConfig(from: dict)
        }

        if let shared = UserDefaults(suiteName: WidgetData.appGroupID) {
            let sharedURL = shared.string(forKey: "nsURL") ?? ""
            let sharedToken = shared.string(forKey: "nsToken") ?? ""

            if !sharedURL.isEmpty || !sharedToken.isEmpty {
                var dict: [String: Any] = [:]
                dict["nsURL"] = sharedURL
                dict["nsToken"] = sharedToken
                return WatchConfig(from: dict)
            }
        }

        return nil
    }
}
