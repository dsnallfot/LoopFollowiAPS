//
//  PushNotificationManager.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-08-27.

//

import Foundation
import SwiftJWT
import HealthKit
import UserNotifications

enum MealBolusReminder {
    static let identifier = "loopfollow.meal-bolus-reminder"

    // Called only after APNs accepts a remote registration. A new qualifying
    // meal replaces the pending reminder, measured from sending (not meal time).
    static func registrationSent(_ message: PushMessage) {
        let center = UNUserNotificationCenter.current()
        if let bolus = message.bolusAmount, bolus != 0 {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        guard message.commandType == .meal || message.commandType == .combo,
              [message.carbs, message.fat, message.protein].contains(where: { ($0 ?? 0) > 0 }),
              message.notes?.contains("🍬") != true else { return }

        let content = UNMutableNotificationContent()
        content.title = "Läge för mer bolus?"
        content.body = "Det är 30 minuter sedan en måltid registrerades utan bolus, om sockret börjat stiga nu så kanske en extra bolus behövs?"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error {
                LogManager.shared.log(category: .remote, message: "Failed to schedule meal bolus reminder: \(error.localizedDescription)")
            }
        }
    }
}

struct APNsJWTClaims: Claims {
    let iss: String
    let iat: Date
}

class PushNotificationManager {
    private var deviceToken: String
    private var sharedSecret: String
    private var productionEnvironment: Bool
    private var apnsKey: String
    private var teamId: String
    private var keyId: String
    private var user: String
    private var bundleId: String

    init() {
        self.deviceToken = Storage.shared.deviceToken.value
        self.sharedSecret = Storage.shared.sharedSecret.value
        self.productionEnvironment = Storage.shared.productionEnvironment.value
        self.apnsKey = Storage.shared.apnsKey.value
        self.teamId = Storage.shared.teamId.value ?? ""
        self.keyId = Storage.shared.keyId.value
        self.user = Storage.shared.user.value
        self.bundleId = Storage.shared.bundleId.value
    }

    func sendOverridePushNotification(override: ProfileManager.TrioOverride, completion: @escaping (Bool, String?) -> Void) {
        var alertString = "Remote Override"
        alertString += "\(override.name)"
        alertString += "\nInlagt av: \(user)"
        if alertString.count > 200 {
            alertString = String(alertString.prefix(200)) + "…"
        }
        let message = PushMessage(
            aps: .init(alert: alertString),
            user: user,
            commandType: .startOverride,
            sharedSecret: sharedSecret,
            timestamp: Date().timeIntervalSince1970,
            overrideName: override.name
        )

        sendPushNotification(message: message, completion: completion)
    }

    func sendCancelOverridePushNotification(completion: @escaping (Bool, String?) -> Void) {
        let message = PushMessage(
            aps: .init(alert: "Remote avbryt override mottagen"),
            user: user,
            commandType: .cancelOverride,
            sharedSecret: sharedSecret,
            timestamp: Date().timeIntervalSince1970,
            overrideName: nil
        )

        sendPushNotification(message: message, completion: completion)
    }

    func sendBolusPushNotification(bolusAmount: HKQuantity, completion: @escaping (Bool, String?) -> Void) {
        let bolusAmountDecimal = Decimal(bolusAmount.doubleValue(for: .internationalUnit()))
        let bolusValue = bolusAmount.doubleValue(for: .internationalUnit())
        var alertString = "Remote bolus"
        alertString += "\nBolus: \(String(format: "%.2f", bolusValue)) E"
        alertString += "\nInlagt av: \(user)"
        if alertString.count > 200 {
            alertString = String(alertString.prefix(200)) + "…"
        }
        let message = PushMessage(
            aps: .init(alert: alertString),
            user: user,
            commandType: .bolus,
            bolusAmount: bolusAmountDecimal,
            sharedSecret: sharedSecret,
            timestamp: Date().timeIntervalSince1970
        )

        sendPushNotification(message: message, completion: completion)
    }
    
    func sendManualGlucosePushNotification(
        glucose: HKQuantity,
        scheduledTime: Date? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let now = Date()
        if let scheduledTime = scheduledTime {
            guard scheduledTime >= Calendar.current.startOfDay(for: now),
                  scheduledTime <= now else {
                completion(false, "Välj en tid under dagens datum som inte ligger i framtiden.")
                return
            }
        }

        let mmolValue = glucose.doubleValue(
            for: HKUnit(from: "mmol/L")
        )

        let mgDlValue = mmolValue * GlucoseConversion.mmolToMgDl
        let glucoseDecimal = Decimal(mgDlValue)

        var alertString = "Remote blodsocker"
        alertString += "\nBlodsocker: \(String(format: "%.1f", mmolValue)) mmol/L"
        alertString += "\nInlagt av: \(user)"

        if alertString.count > 200 {
            alertString = String(alertString.prefix(200)) + "…"
        }

        let message = PushMessage(
            aps: .init(alert: alertString),
            user: user,
            commandType: .glucose,
            bolusAmount: nil,
            glucose: glucoseDecimal,
            sharedSecret: sharedSecret,
            timestamp: now.timeIntervalSince1970,
            scheduledTime: scheduledTime?.timeIntervalSince1970
        )

        sendPushNotification(
            message: message,
            completion: completion
        )
    }

    func sendTempTargetPushNotification(target: HKQuantity, duration: HKQuantity, completion: @escaping (Bool, String?) -> Void) {
        let targetValue = Int(target.doubleValue(for: HKUnit.milligramsPerDeciliter))
        let targetMgdl = target.doubleValue(for: HKUnit.milligramsPerDeciliter)
        let targetValueMmol = targetMgdl / 18.018
        let durationValue = Int(duration.doubleValue(for: HKUnit.minute()))

        var alertString = "Remote temp target"
        alertString += "\nMål: \(String(format: "%.1f", targetValueMmol)) mmol/L"
        alertString += "\nVaraktighet: \(durationValue) min"
        alertString += "\nInlagt av: \(user)"
        if alertString.count > 200 {
            alertString = String(alertString.prefix(200)) + "…"
        }
        let message = PushMessage(
            aps: .init(alert: alertString),
            user: user,
            commandType: .tempTarget,
            bolusAmount: nil,
            target: targetValue,
            duration: durationValue,
            sharedSecret: sharedSecret,
            timestamp: Date().timeIntervalSince1970
        )

        sendPushNotification(message: message, completion: completion)
    }

    func sendCancelTempTargetPushNotification(completion: @escaping (Bool, String?) -> Void) {
        let message = PushMessage(
            aps: .init(alert: "Remote avbryt temp target mottagen"),
            user: user,
            commandType: .cancelTempTarget,
            sharedSecret: sharedSecret,
            timestamp: Date().timeIntervalSince1970
        )

        sendPushNotification(message: message, completion: completion)
    }

    func sendDeleteMealPushNotification(
        mealDate: Date,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let message = PushMessage(
            aps: .init(alert: "Remote radera måltid mottagen"),
            user: user,
            commandType: .deleteMeal,
            sharedSecret: sharedSecret,
            timestamp: Date().timeIntervalSince1970,
            scheduledTime: mealDate.timeIntervalSince1970
        )

        sendPushNotification(message: message, completion: completion)
    }

    func sendDeleteGlucosePushNotification(
        glucoseDate: Date,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let message = PushMessage(
            aps: .init(alert: "Remote radera blodsockervärde mottagen"),
            user: user,
            commandType: .deleteGlucose,
            sharedSecret: sharedSecret,
            timestamp: Date().timeIntervalSince1970,
            scheduledTime: glucoseDate.timeIntervalSince1970
        )

        sendPushNotification(message: message, completion: completion)
    }

    func sendMealPushNotification(
        carbs: HKQuantity,
        protein: HKQuantity,
        fat: HKQuantity,
        bolusAmount: HKQuantity,
        notes: String?,
        scheduledTime: Date?,
        completion: @escaping (Bool, String?) -> Void
    ) {
        func convertToOptionalInt(_ quantity: HKQuantity) -> Int? {
            let valueInGrams = quantity.doubleValue(for: .gram())
            return valueInGrams > 0 ? Int(valueInGrams) : nil
        }

        func convertToOptionalDecimal(_ quantity: HKQuantity?) -> Decimal? {
            guard let quantity = quantity else { return nil }
            let value = quantity.doubleValue(for: .internationalUnit())
            return value > 0 ? Decimal(value) : nil
        }

        let carbsValue = convertToOptionalInt(carbs)
        let proteinValue = convertToOptionalInt(protein)
        let fatValue = convertToOptionalInt(fat)
        let scheduledTimeInterval: TimeInterval? = scheduledTime?.timeIntervalSince1970
        let bolusAmountValue = convertToOptionalDecimal(bolusAmount)

        guard carbsValue != nil || proteinValue != nil || fatValue != nil else {
            completion(false, "No nutrient data provided. At least one of carbs, fat, or protein must be greater than 0.")
            return
        }

        // Build dynamic alert string
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let timeString: String = {
            if let scheduledTime = scheduledTime {
                return formatter.string(from: scheduledTime)
            } else {
                return formatter.string(from: Date())
            }
        }()

        let sender = user
        
        var alertString = "Remote måltid"
        if let notes = notes, !notes.isEmpty {
            alertString += "\n\(notes)"
        }

        if let carbs = carbsValue {
            alertString += "\nKolhydrater: \(carbs) g"
        }
        if let fat = fatValue {
            alertString += "\nFett: \(fat) g"
        }
        if let protein = proteinValue {
            alertString += "\nProtein: \(protein) g"
        }
        if let bolus = bolusAmountValue {
            alertString += "\nBolus: \(bolus) E"
        }

        alertString += "\nTid: \(timeString)"
        
        alertString += "\nInlagt av: \(sender)"

        if alertString.count > 200 {
            alertString = String(alertString.prefix(200)) + "…"
        }

        let message = PushMessage(
            aps: .init(alert: alertString),
            user: user,
            commandType: .meal,
            bolusAmount: bolusAmountValue,
            carbs: carbsValue,
            protein: proteinValue,
            fat: fatValue,
            notes: notes,
            sharedSecret: sharedSecret,
            timestamp: Date().timeIntervalSince1970,
            scheduledTime: scheduledTimeInterval
        )

        sendPushNotification(message: message, completion: completion)
    }
    
    func sendComboPushNotification(
        carbs: HKQuantity,
        protein: HKQuantity,
        fat: HKQuantity,
        bolusAmount: HKQuantity,
        notes: String?,
        scheduledTime: Date?,
        override: ProfileManager.TrioOverride?,
        completion: @escaping (Bool, String?) -> Void
    ) {
        func convertToOptionalInt(_ quantity: HKQuantity) -> Int? {
            let valueInGrams = quantity.doubleValue(for: .gram())
            return valueInGrams > 0 ? Int(valueInGrams) : nil
        }

        func convertToOptionalDecimal(_ quantity: HKQuantity?) -> Decimal? {
            guard let quantity = quantity else { return nil }
            let value = quantity.doubleValue(for: .internationalUnit())
            return value > 0 ? Decimal(value) : nil
        }

        let carbsValue = convertToOptionalInt(carbs)
        let proteinValue = convertToOptionalInt(protein)
        let fatValue = convertToOptionalInt(fat)
        let scheduledTimeInterval: TimeInterval? = scheduledTime?.timeIntervalSince1970
        let bolusAmountValue = convertToOptionalDecimal(bolusAmount)

        guard carbsValue != nil || proteinValue != nil || fatValue != nil else {
            completion(false, "No nutrient data provided. At least one of carbs, fat, or protein must be greater than 0.")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let timeString: String = {
            if let scheduledTime = scheduledTime {
                return formatter.string(from: scheduledTime)
            } else {
                return formatter.string(from: Date())
            }
        }()

        var alertString = "Remote snabbval"
        if let notes = notes, !notes.isEmpty {
            alertString += "\n\(notes)"
        }

        if let carbs = carbsValue {
            alertString += "\nKolhydrater: \(carbs) g"
        }
        if let fat = fatValue {
            alertString += "\nFett: \(fat) g"
        }
        if let protein = proteinValue {
            alertString += "\nProtein: \(protein) g"
        }
        if let bolus = bolusAmountValue {
            alertString += "\nBolus: \(bolus) E"
        }
        if let overrideName = override?.name, !overrideName.isEmpty {
            alertString += "\nOverride: \(overrideName)"
        }

        alertString += "\nTid: \(timeString)"
        alertString += "\nInlagt av: \(user)"

        if alertString.count > 200 {
            alertString = String(alertString.prefix(200)) + "…"
        }

        let message = PushMessage(
            aps: .init(alert: alertString),
            user: user,
            commandType: .combo,
            bolusAmount: bolusAmountValue,
            carbs: carbsValue,
            protein: proteinValue,
            fat: fatValue,
            notes: notes,
            sharedSecret: sharedSecret,
            timestamp: Date().timeIntervalSince1970,
            overrideName: override?.name,
            scheduledTime: scheduledTimeInterval
        )

        sendPushNotification(message: message, completion: completion)
    }

    private func validateCredentials() -> [String]? {
        var errors = [String]()

        // Validate keyId (should be 10 alphanumeric characters)
        let keyIdPattern = "^[A-Z0-9]{10}$"
        if !matchesRegex(keyId, pattern: keyIdPattern) {
            errors.append("APNS Key ID (\(keyId)) must be 10 uppercase alphanumeric characters.")
        }

        // Validate teamId (should be 10 alphanumeric characters)
        let teamIdPattern = "^[A-Z0-9]{10}$"
        if !matchesRegex(teamId, pattern: teamIdPattern) {
            errors.append("Team ID (\(teamId)) must be 10 uppercase alphanumeric characters.")
        }

        // Validate apnsKey (should contain the BEGIN and END PRIVATE KEY markers)
        if !apnsKey.contains("-----BEGIN PRIVATE KEY-----") || !apnsKey.contains("-----END PRIVATE KEY-----") {
            errors.append("APNS Key must be a valid PEM-formatted private key.")
        } else {
            // Validate that the key data between the markers is valid Base64
            if let keyData = extractKeyData(from: apnsKey) {
                if Data(base64Encoded: keyData) == nil {
                    errors.append("APNS Key contains invalid Base64 key data.")
                }
            } else {
                errors.append("APNS Key has invalid formatting.")
            }
        }

        return errors.isEmpty ? nil : errors
    }

    private func matchesRegex(_ text: String, pattern: String) -> Bool {
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex?.firstMatch(in: text, options: [], range: range) != nil
    }

    private func extractKeyData(from pemString: String) -> String? {
        let lines = pemString.components(separatedBy: "\n")
        guard let startIndex = lines.firstIndex(of: "-----BEGIN PRIVATE KEY-----"),
              let endIndex = lines.firstIndex(of: "-----END PRIVATE KEY-----"),
              startIndex < endIndex else {
            return nil
        }
        let keyLines = lines[(startIndex + 1)..<endIndex]
        return keyLines.joined()
    }

    private func sendPushNotification(message: PushMessage, completion: @escaping (Bool, String?) -> Void) {
        LogManager.shared.log(category: .remote, message: "Push message to send: \(message)", isDebug: true)

        var missingFields = [String]()
        if sharedSecret.isEmpty { missingFields.append("sharedSecret") }
        if apnsKey.isEmpty { missingFields.append("token") }
        if keyId.isEmpty { missingFields.append("keyId") }
        if user.isEmpty { missingFields.append("user") }

        if !missingFields.isEmpty {
            let errorMessage = "Missing required fields, check your remote settings: \(missingFields.joined(separator: ", "))"
            LogManager.shared.log(category: .apns, message: errorMessage)
            completion(false, errorMessage)
            return
        }

        if deviceToken.isEmpty { missingFields.append("deviceToken") }
        if bundleId.isEmpty { missingFields.append("bundleId") }
        if teamId.isEmpty { missingFields.append("teamId") }

        if !missingFields.isEmpty {
            let errorMessage = "Missing required data, verify that you are using the latest version of Trio: \(missingFields.joined(separator: ", "))"
            LogManager.shared.log(category: .apns, message: errorMessage)
            completion(false, errorMessage)
            return
        }

        if let validationErrors = validateCredentials() {
            let errorMessage = "Credential validation failed: \(validationErrors.joined(separator: ", "))"
            LogManager.shared.log(category: .apns, message: errorMessage)
            completion(false, errorMessage)
            return
        }

        guard let url = constructAPNsURL() else {
            let errorMessage = "Failed to construct APNs URL"
            LogManager.shared.log(category: .apns, message: errorMessage)
            completion(false, errorMessage)
            return
        }

        guard let jwt = getOrGenerateJWT() else {
            let errorMessage = "Failed to generate JWT, please check that the token is correct."
            LogManager.shared.log(category: .apns, message: errorMessage)
            completion(false, errorMessage)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        request.setValue("300", forHTTPHeaderField: "apns-expiration")
        request.setValue(bundleId, forHTTPHeaderField: "apns-topic")
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")

        do {
            let jsonData = try JSONEncoder().encode(message)
            request.httpBody = jsonData

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    let errorMessage = "Failed to send push notification: \(error.localizedDescription)"
                    LogManager.shared.log(category: .apns, message: errorMessage)
                    completion(false, errorMessage)
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    LogManager.shared.log(category: .remote, message: "Push notification sent.", isDebug: true)
                    LogManager.shared.log(category: .remote, message: "Status code: \(httpResponse.statusCode)", isDebug: true)
                    LogManager.shared.log(category: .apns, message: "Response headers:", isDebug: true)
                    for (key, value) in httpResponse.allHeaderFields {
                        LogManager.shared.log(category: .apns, message: "\(key): \(value)", isDebug: true)
                    }

                    var responseBodyMessage = ""
                    if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                        LogManager.shared.log(category: .apns, message: "Response body: \(responseBody)", isDebug: true)

                            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                           let reason = json["reason"] as? String {
                            responseBodyMessage = reason
                        }
                    } else {
                        LogManager.shared.log(category: .apns, message: "No response body", isDebug: true)
                    }

                    switch httpResponse.statusCode {
                    case 200:
                        MealBolusReminder.registrationSent(message)
                        completion(true, nil)
                    case 400:
                        completion(false, "Bad request. The request was invalid or malformed. \(responseBodyMessage)")
                    case 403:
                        completion(false, "Authentication error. Check your certificate or authentication token. \(responseBodyMessage)")
                    case 404:
                        completion(false, "Invalid request: The :path value was incorrect. \(responseBodyMessage)")
                    case 405:
                        completion(false, "Invalid request: Only POST requests are supported. \(responseBodyMessage)")
                    case 410:
                        completion(false, "The device token is no longer active for the topic. \(responseBodyMessage)")
                    case 413:
                        completion(false, "Payload too large. The notification payload exceeded the size limit. \(responseBodyMessage)")
                    case 429:
                        completion(false, "Too many requests. \(responseBodyMessage)")
                    case 500:
                        completion(false, "Internal server error at APNs. \(responseBodyMessage)")
                    case 503:
                        completion(false, "Service unavailable. The server is temporarily unavailable. Try again later. \(responseBodyMessage)")
                    default:
                        completion(false, "Unexpected status code: \(httpResponse.statusCode). \(responseBodyMessage)")
                    }
                } else {
                    completion(false, "Failed to get a valid HTTP response.")
                }
            }
            task.resume()

        } catch {
            let errorMessage = "Failed to encode push message: \(error.localizedDescription)"
            LogManager.shared.log(category: .apns, message: "\(errorMessage)", isDebug: true)
            completion(false, errorMessage)
        }
    }

    private func constructAPNsURL() -> URL? {
        let host = productionEnvironment ? "api.push.apple.com" : "api.sandbox.push.apple.com"
        let urlString = "https://\(host)/3/device/\(deviceToken)"
        return URL(string: urlString)
    }


    private func getOrGenerateJWT() -> String? {
        if let cachedJWT = Storage.shared.cachedJWT.value, let expirationDate = Storage.shared.jwtExpirationDate.value {
            if Date() < expirationDate {
                return cachedJWT
            }
        }

        let header = Header(kid: keyId)
        let claims = APNsJWTClaims(iss: teamId, iat: Date())

        var jwt = JWT(header: header, claims: claims)

        do {
            let privateKey = Data(apnsKey.utf8)
            let jwtSigner = JWTSigner.es256(privateKey: privateKey)
            let signedJWT = try jwt.sign(using: jwtSigner)

            Storage.shared.cachedJWT.value = signedJWT
            Storage.shared.jwtExpirationDate.value = Date().addingTimeInterval(3600)

            return signedJWT
        } catch {
            LogManager.shared.log(category: .apns, message: "Failed to sign JWT: \(error.localizedDescription)", isDebug: true)
            return nil
        }
    }
}
