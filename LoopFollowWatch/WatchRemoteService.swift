// LoopFollow
// WatchRemoteService.swift

import Foundation
import UserNotifications
import WatchKit
import CryptoKit

class WatchRemoteService {

    // MARK: - Local Notification Helper

    static func postLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        WKInterfaceDevice.current().play(.notification)
    }

    // MARK: - Public API

    static func sendBolus(amount: Double, config: WatchConfig, completion: @escaping (Bool, String?) -> Void) {
        switch config.remoteType {
        case "Trio Remote Control":
            let alertString = Self.truncatedAlertString([
                "Remote bolus",
                String(format: "Bolus: %.2f E", amount),
                "Inlagt av: \(config.trcUser)",
            ])
            let payload = TRCPayload(
                aps: APSPayload(alert: alertString),
                user: config.trcUser,
                commandType: "bolus",
                bolusAmount: amount,
                sharedSecret: config.trcSharedSecret,
                timestamp: Date().timeIntervalSince1970
            )
            sendTRCCommand(payload: payload, config: config, completion: completion)
        case "Nightscout":
            let body: [String: Any] = [
                "enteredBy": "LoopFollow Watch",
                "eventType": "Correction Bolus",
                "insulin": amount,
                "created_at": ISO8601DateFormatter().string(from: Date()),
            ]
            postNightscoutTreatment(body: body, config: config, completion: completion)
        default:
            completion(false, "Remote type not supported")
        }
    }


    static func sendMeal(
        carbs: Int,
        protein: Int? = nil,
        fat: Int? = nil,
        notes: String? = "⌚️",
        entryTime: Date? = nil,
        config: WatchConfig,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let timestamp = entryTime ?? Date()
        switch config.remoteType {
        case "Trio Remote Control":
            let mealNotes = (notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? notes : "⌚️"
            let scheduledTime = entryTime?.timeIntervalSince1970

            var alertLines = ["Remote måltid"]
            if let mealNotes = mealNotes {
                alertLines.append(mealNotes)
            }
            alertLines.append("Kolhydrater: \(carbs) g")
            if let fat = fat {
                alertLines.append("Fett: \(fat) g")
            }
            if let protein = protein {
                alertLines.append("Protein: \(protein) g")
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            alertLines.append("Tid: \(formatter.string(from: timestamp))")
            alertLines.append("Inlagt av: \(config.trcUser)")
            let alertString = Self.truncatedAlertString(alertLines)
            let payload = TRCPayload(
                aps: APSPayload(alert: alertString),
                user: config.trcUser,
                commandType: "meal",
                carbs: carbs,
                protein: protein,
                fat: fat,
                notes: mealNotes,
                sharedSecret: config.trcSharedSecret,
                timestamp: Date().timeIntervalSince1970,
                scheduledTime: scheduledTime
            )
            sendTRCCommand(payload: payload, config: config, completion: completion)
        case "Nightscout":
            var body: [String: Any] = [
                "enteredBy": "LoopFollow Watch",
                "eventType": "Meal Bolus",
                "carbs": carbs,
                "created_at": ISO8601DateFormatter().string(from: timestamp),
            ]
            if let protein = protein { body["protein"] = protein }
            if let fat = fat { body["fat"] = fat }
            postNightscoutTreatment(body: body, config: config, completion: completion)
        default:
            completion(false, "Remote type not supported")
        }
    }

    static func sendCombo(
        carbs: Int? = nil,
        protein: Int? = nil,
        fat: Int? = nil,
        bolusAmount: Double? = nil,
        notes: String? = "⌚️",
        entryTime: Date? = nil,
        overrideName: String? = nil,
        config: WatchConfig,
        completion: @escaping (Bool, String?) -> Void
    ) {
        switch config.remoteType {
        case "Trio Remote Control":
            let hasNutrients = (carbs ?? 0) > 0 || (protein ?? 0) > 0 || (fat ?? 0) > 0
            let hasBolus = (bolusAmount ?? 0) > 0
            let hasOverride = overrideName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

            guard hasNutrients || hasBolus || hasOverride else {
                completion(false, "No combo data provided. At least one of carbs, fat, protein, bolus, or override must be provided.")
                return
            }

            let timestamp = entryTime ?? Date()
            let scheduledTime = entryTime?.timeIntervalSince1970
            let comboNotes = (notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? notes : "⌚️"
            let trimmedOverrideName = overrideName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalOverrideName = (trimmedOverrideName?.isEmpty == false) ? trimmedOverrideName : nil
            let finalCarbs = (carbs ?? 0) > 0 ? carbs : nil
            let finalProtein = (protein ?? 0) > 0 ? protein : nil
            let finalFat = (fat ?? 0) > 0 ? fat : nil
            let finalBolusAmount = (bolusAmount ?? 0) > 0 ? bolusAmount : nil

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"

            var alertLines = ["Remote snabbval"]
            if let comboNotes = comboNotes {
                alertLines.append(comboNotes)
            }
            if let finalCarbs = finalCarbs {
                alertLines.append("Kolhydrater: \(finalCarbs) g")
            }
            if let finalFat = finalFat {
                alertLines.append("Fett: \(finalFat) g")
            }
            if let finalProtein = finalProtein {
                alertLines.append("Protein: \(finalProtein) g")
            }
            if let finalBolusAmount = finalBolusAmount {
                alertLines.append(String(format: "Bolus: %.2f E", finalBolusAmount))
            }
            if let finalOverrideName = finalOverrideName {
                alertLines.append("Override: \(finalOverrideName)")
            }
            alertLines.append("Tid: \(formatter.string(from: timestamp))")
            alertLines.append("Inlagt av: \(config.trcUser)")

            let alertString = Self.truncatedAlertString(alertLines)
            let payload = TRCPayload(
                aps: APSPayload(alert: alertString),
                user: config.trcUser,
                commandType: "combo",
                bolusAmount: finalBolusAmount,
                carbs: finalCarbs,
                protein: finalProtein,
                fat: finalFat,
                notes: comboNotes,
                sharedSecret: config.trcSharedSecret,
                timestamp: Date().timeIntervalSince1970,
                overrideName: finalOverrideName,
                scheduledTime: scheduledTime
            )
            sendTRCCommand(payload: payload, config: config, completion: completion)
        default:
            completion(false, "Remote type not supported for combo")
        }
    }

    static func sendTempTarget(target: Int, duration: Int, config: WatchConfig, completion: @escaping (Bool, String?) -> Void) {
        switch config.remoteType {
        case "Trio Remote Control":
            let targetValueMmol = Double(target) / 18.018
            let alertString = Self.truncatedAlertString([
                "Remote temp target",
                String(format: "Mål: %.1f mmol/L", targetValueMmol),
                "Varaktighet: \(duration) min",
                "Inlagt av: \(config.trcUser)",
            ])
            let payload = TRCPayload(
                aps: APSPayload(alert: alertString),
                user: config.trcUser,
                commandType: "temp_target",
                target: target,
                duration: duration,
                sharedSecret: config.trcSharedSecret,
                timestamp: Date().timeIntervalSince1970
            )
            sendTRCCommand(payload: payload, config: config, completion: completion)
        case "Nightscout":
            let body: [String: Any] = [
                "enteredBy": "LoopFollow Watch",
                "eventType": "Temporary Target",
                "reason": "Manual",
                "targetTop": Double(target),
                "targetBottom": Double(target),
                "duration": duration,
                "created_at": ISO8601DateFormatter().string(from: Date()),
            ]
            postNightscoutTreatment(body: body, config: config, completion: completion)
        default:
            completion(false, "Remote type not supported")
        }
    }

    static func cancelTempTarget(config: WatchConfig, completion: @escaping (Bool, String?) -> Void) {
        switch config.remoteType {
        case "Trio Remote Control":
            let alertString = Self.truncatedAlertString([
                "Remote avbryt temp target mottagen",
                "Inlagt av: \(config.trcUser)",
            ])
            let payload = TRCPayload(
                aps: APSPayload(alert: alertString),
                user: config.trcUser,
                commandType: "cancel_temp_target",
                sharedSecret: config.trcSharedSecret,
                timestamp: Date().timeIntervalSince1970
            )
            sendTRCCommand(payload: payload, config: config, completion: completion)
        case "Nightscout":
            let body: [String: Any] = [
                "enteredBy": "LoopFollow Watch",
                "eventType": "Temporary Target",
                "reason": "Manual",
                "duration": 0,
                "created_at": ISO8601DateFormatter().string(from: Date()),
            ]
            postNightscoutTreatment(body: body, config: config, completion: completion)
        default:
            completion(false, "Remote type not supported")
        }
    }

    static func sendOverride(name: String, config: WatchConfig, completion: @escaping (Bool, String?) -> Void) {
        switch config.remoteType {
        case "Trio Remote Control":
            let alertString = Self.truncatedAlertString([
                "Remote Override",
                name,
                "Inlagt av: \(config.trcUser)",
            ])
            let payload = TRCPayload(
                aps: APSPayload(alert: alertString),
                user: config.trcUser,
                commandType: "start_override",
                sharedSecret: config.trcSharedSecret,
                timestamp: Date().timeIntervalSince1970,
                overrideName: name
            )
            sendTRCCommand(payload: payload, config: config, completion: completion)
        default:
            completion(false, "Remote type not supported for overrides")
        }
    }

    static func cancelOverride(config: WatchConfig, completion: @escaping (Bool, String?) -> Void) {
        switch config.remoteType {
        case "Trio Remote Control":
            let alertString = Self.truncatedAlertString([
                "Remote avbryt override mottagen",
                "Inlagt av: \(config.trcUser)",
            ])
            let payload = TRCPayload(
                aps: APSPayload(alert: alertString),
                user: config.trcUser,
                commandType: "cancel_override",
                sharedSecret: config.trcSharedSecret,
                timestamp: Date().timeIntervalSince1970
            )
            sendTRCCommand(payload: payload, config: config, completion: completion)
        default:
            completion(false, "Remote type not supported for overrides")
        }
    }

    // MARK: - TRC (Trio Remote Control) via APNS

    private struct APSPayload: Encodable {
        let alert: String
        let contentAvailable: Int = 1
        let interruptionLevel: String = "time-sensitive"

        enum CodingKeys: String, CodingKey {
            case alert
            case contentAvailable = "content-available"
            case interruptionLevel = "interruption-level"
        }
    }
    private struct TRCPayload: Encodable {
        var aps: APSPayload
        var user: String
        var commandType: String
        var bolusAmount: Double?
        var target: Int?
        var duration: Int?
        var carbs: Int?
        var protein: Int?
        var fat: Int?
        var notes: String?
        var sharedSecret: String
        var timestamp: TimeInterval
        var overrideName: String?
        var scheduledTime: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case aps
            case user
            case commandType = "command_type"
            case bolusAmount = "bolus_amount"
            case target
            case duration
            case carbs
            case protein
            case fat
            case notes
            case sharedSecret = "shared_secret"
            case timestamp
            case overrideName
            case scheduledTime = "scheduled_time"
        }
    }

    private static func truncatedAlertString(_ lines: [String]) -> String {
        let alertString = lines.joined(separator: "\n")
        if alertString.count > 200 {
            return String(alertString.prefix(200)) + "…"
        }
        return alertString
    }

    private static func sendTRCCommand(payload: TRCPayload, config: WatchConfig, completion: @escaping (Bool, String?) -> Void) {
        guard !config.trcSharedSecret.isEmpty,
              !config.trcApnsKey.isEmpty,
              !config.trcKeyId.isEmpty,
              !config.trcTeamId.isEmpty,
              !config.trcDeviceToken.isEmpty,
              !config.trcBundleId.isEmpty
        else {
            completion(false, "Missing TRC credentials")
            return
        }

        // Sign JWT
        guard let jwt = signJWT(keyId: config.trcKeyId, teamId: config.trcTeamId, apnsKey: config.trcApnsKey) else {
            completion(false, "JWT signing failed")
            return
        }

        // Build APNS request
        let host = config.trcProductionEnv ? "api.push.apple.com" : "api.sandbox.push.apple.com"
        guard let url = URL(string: "https://\(host)/3/device/\(config.trcDeviceToken)") else {
            completion(false, "Invalid APNS URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        request.setValue("300", forHTTPHeaderField: "apns-expiration")
        request.setValue(config.trcBundleId, forHTTPHeaderField: "apns-topic")
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")
        request.httpBody = try? JSONEncoder().encode(payload)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    completion(true, nil)
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    completion(false, "APNS error: \(code)")
                }
            }
        }.resume()
    }

    // MARK: - CryptoKit P256 JWT Signing

    private static func signJWT(keyId: String, teamId: String, apnsKey: String) -> String? {
        // Extract raw key data from PEM
        let lines = apnsKey.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let base64Key = lines.joined()
        guard let keyData = Data(base64Encoded: base64Key) else { return nil }

        guard let privateKey = try? P256.Signing.PrivateKey(derRepresentation: keyData) else { return nil }

        // Header
        let header = #"{"alg":"ES256","kid":"\#(keyId)"}"#
        // Claims
        let claims = #"{"iss":"\#(teamId)","iat":\#(Int(Date().timeIntervalSince1970))}"#

        guard let headerData = header.data(using: .utf8),
              let claimsData = claims.data(using: .utf8)
        else { return nil }

        let headerB64 = base64URLEncode(headerData)
        let claimsB64 = base64URLEncode(claimsData)
        let signingInput = "\(headerB64).\(claimsB64)"

        guard let signingData = signingInput.data(using: .utf8),
              let signature = try? privateKey.signature(for: signingData)
        else { return nil }

        let signatureB64 = base64URLEncode(signature.rawRepresentation)
        return "\(signingInput).\(signatureB64)"
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Nightscout Treatments POST

    private static func postNightscoutTreatment(body: [String: Any], config: WatchConfig, completion: @escaping (Bool, String?) -> Void) {
        guard config.nsWriteAuth else {
            completion(false, "Nightscout write auth not enabled")
            return
        }

        // First get JWT token from status endpoint
        fetchNightscoutJWT(config: config) { jwt in
            guard let jwt = jwt else {
                completion(false, "Failed to get Nightscout auth token")
                return
            }

            var components = URLComponents(string: config.nsURL)
            components?.path = "/api/v1/treatments.json"

            guard let url = components?.url else {
                completion(false, "Invalid Nightscout URL")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            URLSession.shared.dataTask(with: request) { _, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(false, error.localizedDescription)
                        return
                    }
                    if let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) {
                        completion(true, nil)
                    } else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        completion(false, "Nightscout error: \(code)")
                    }
                }
            }.resume()
        }
    }

    private static func fetchNightscoutJWT(config: WatchConfig, completion: @escaping (String?) -> Void) {
        var components = URLComponents(string: config.nsURL)
        components?.path = "/api/v1/status.json"
        if !config.nsToken.isEmpty {
            components?.queryItems = [URLQueryItem(name: "token", value: config.nsToken)]
        }

        guard let url = components?.url else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard error == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let jwt = json["token"] as? String
            else {
                // Fallback: use token directly as API secret hash
                completion(config.nsToken)
                return
            }
            completion(jwt)
        }.resume()
    }
}
