
import Foundation
import HealthKit
import WatchConnectivity

class PhoneSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()

    private override init() {
        super.init()
    }

    func startSession() {
        guard ObservableUserDefaults.shared.watchCommunicationEnabled.value else { return }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func buildConfig() -> [String: Any] {
        let comboPresets = Storage.shared.comboPresets.map { preset in
            [
                "id": preset.id.uuidString,
                "name": preset.name,
                "carbsGrams": preset.carbsGrams,
                "proteinGrams": preset.proteinGrams,
                "fatGrams": preset.fatGrams,
                "bolusUnits": preset.bolusUnits,
                "notes": preset.notes,
                "overrideName": preset.overrideName ?? "",
            ] as [String: Any]
        }
        return [
            "nsURL": ObservableUserDefaults.shared.url.value,
            "nsToken": UserDefaultsRepository.token.value,
            "dexUsername": UserDefaultsRepository.shareUserName.value,
            "dexPassword": UserDefaultsRepository.sharePassword.value,
            "dexServer": UserDefaultsRepository.shareServer.value,
            "units": UserDefaultsRepository.units.value,
            "lowLine": UserDefaultsRepository.lowLine.value,
            "highLine": UserDefaultsRepository.highLine.value,
            "remoteType": Storage.shared.remoteType.value.rawValue,
            "maxBolus": Storage.shared.maxBolus.value.doubleValue(for: .internationalUnit()),
            "maxCarbs": Storage.shared.maxCarbs.value.doubleValue(for: .gram()),
            "trcDeviceToken": Storage.shared.deviceToken.value,
            "trcSharedSecret": Storage.shared.sharedSecret.value,
            "trcApnsKey": Storage.shared.apnsKey.value,
            "trcKeyId": Storage.shared.keyId.value,
            "trcTeamId": Storage.shared.teamId.value ?? "",
            "trcBundleId": Storage.shared.bundleId.value,
            "trcProductionEnv": Storage.shared.productionEnvironment.value,
            "trcUser": Storage.shared.user.value,
            "nsWriteAuth": ObservableUserDefaults.shared.nsWriteAuth.value,
            "mealWithFatProtein": Storage.shared.mealWithFatProtein.value,
            "maxProtein": Storage.shared.maxProtein.value.doubleValue(for: .gram()),
            "maxFat": Storage.shared.maxFat.value.doubleValue(for: .gram()),
            "comboPresets": comboPresets,
            "bgComplicationEnabled": Storage.shared.bgComplicationEnabled.value,
        ]
    }

    func sendConfig() {
        guard ObservableUserDefaults.shared.watchCommunicationEnabled.value else { return }
        guard WCSession.default.activationState == .activated else { return }
        let config = buildConfig()
        try? WCSession.default.updateApplicationContext(config)

        // Also send via message for immediate delivery if Watch is reachable
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(config, replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated, ObservableUserDefaults.shared.watchCommunicationEnabled.value {
            sendConfig()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        if ObservableUserDefaults.shared.watchCommunicationEnabled.value {
            WCSession.default.activate()
        }
    }

    // Re-send config when Watch becomes reachable (handles fresh install)
    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable, ObservableUserDefaults.shared.watchCommunicationEnabled.value {
            sendConfig()
        }
    }

    // Handle Watch requesting config via applicationContext
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if applicationContext["requestConfig"] != nil, ObservableUserDefaults.shared.watchCommunicationEnabled.value {
            sendConfig()
        }
    }

    // Handle Watch requesting config via sendMessage (with reply)
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard ObservableUserDefaults.shared.watchCommunicationEnabled.value else {
            replyHandler([:])
            return
        }

        if message["requestConfig"] != nil {
            let config = buildConfig()
            replyHandler(config)
            // Also update application context so it's cached
            try? WCSession.default.updateApplicationContext(config)
        } else {
            replyHandler([:])
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["requestConfig"] != nil, ObservableUserDefaults.shared.watchCommunicationEnabled.value {
            sendConfig()
        }
    }

    // Handle Watch requesting config via transferUserInfo
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if userInfo["requestConfig"] != nil, ObservableUserDefaults.shared.watchCommunicationEnabled.value {
            sendConfig()
        }
    }
}
