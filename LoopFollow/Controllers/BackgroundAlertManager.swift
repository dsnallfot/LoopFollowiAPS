//
//  BackgroundAlertManager.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-06-22.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import Foundation
import UserNotifications

/// Enum representing different background alert durations.
enum BackgroundAlertDuration: TimeInterval, CaseIterable {
    case sixMinutes = 360 // 6 minutes in seconds
    case twelveMinutes = 720 // 12 minutes in seconds
    case eighteenMinutes = 1080 // 18 minutes in seconds
}

/// Enum representing unique identifiers for each background alert.
enum BackgroundAlertIdentifier: String, CaseIterable {
    case sixMin = "loopfollow.background.alert.6min"
    case twelveMin = "loopfollow.background.alert.12min"
    case eighteenMin = "loopfollow.background.alert.18min"
}

class BackgroundAlertManager {
    static let shared = BackgroundAlertManager()
    
    private init() {}
    
    /// Flag indicating whether background alerts are currently scheduled.
    private var isAlertScheduled: Bool = false
    
    /// Title prefix for all background refresh notifications.
    private let notificationTitlePrefix = "LoopFollow Background Refresh"
    
    /// Timestamp of the last scheduled background alert.
    private var lastScheduleDate: Date?
    
    /// Start scheduling background alerts.
    func startBackgroundAlert() {
        LogManager.shared.log(category: .backgroundAlerts, message: "BackgroundAlertManager: startBackgroundAlert called. isAlertScheduled was \(isAlertScheduled)", isDebug: true)
        isAlertScheduled = true
        // Force execution to bypass throttle when starting
        scheduleBackgroundAlert(force: true)
    }
    
    /// Stop all scheduled background alerts.
    func stopBackgroundAlert() {
        LogManager.shared.log(category: .backgroundAlerts, message: "BackgroundAlertManager: stopBackgroundAlert called. Cancelling alerts and removing notifications.", isDebug: true)
        isAlertScheduled = false
        removeDeliveredNotifications()
        cancelBackgroundAlerts()
    }
    
    /// (Re)schedule all background alerts based on predefined durations.
    /// - Parameter force: When true, the scheduling is executed regardless of throttle constraints.
    func scheduleBackgroundAlert(force: Bool = false) {
        //LogManager.shared.log(category: .backgroundAlerts, message: "BackgroundAlertManager: scheduleBackgroundAlert called. force=\(force), isAlertScheduled=\(isAlertScheduled), backgroundRefreshType=\(Storage.shared.backgroundRefreshType.value)", isDebug: true)

        guard isAlertScheduled, Storage.shared.backgroundRefreshType.value != .none else {
            //LogManager.shared.log(category: .backgroundAlerts, message: "BackgroundAlertManager: scheduleBackgroundAlert aborted. isAlertScheduled=\(isAlertScheduled), backgroundRefreshType=\(Storage.shared.backgroundRefreshType.value)", isDebug: true)
            return
        }

        // Throttle execution if not forced: only run once every 10 seconds (to avoid rapid duplicate scheduling).
        if !force {
            let now = Date()
            if let lastDate = lastScheduleDate {
                let delta = now.timeIntervalSince(lastDate)
                if delta < 10 {
                    //LogManager.shared.log(category: .backgroundAlerts, message: "BackgroundAlertManager: scheduleBackgroundAlert throttled (delta=\(delta) < 10s)", isDebug: true)
                    return
                }
            }
            lastScheduleDate = now
        } else {
            lastScheduleDate = Date()
        }

        //LogManager.shared.log(category: .backgroundAlerts, message: "BackgroundAlertManager: proceeding with scheduling. lastScheduleDate=\(String(describing: lastScheduleDate))", isDebug: true)

        // IMPORTANT: cancel any previously scheduled background alerts so that we only have one set active at a time.
        cancelBackgroundAlerts()

        // Remove any previously delivered notifications for these identifiers.
        removeDeliveredNotifications()

        let isBluetoothActive = Storage.shared.backgroundRefreshType.value.isBluetooth
        let expectedHeartbeat = BLEManager.shared.expectedHeartbeatInterval()
        //LogManager.shared.log(category: .backgroundAlerts, message: "BackgroundAlertManager: isBluetoothActive=\(isBluetoothActive), expectedHeartbeat=\(expectedHeartbeat != nil ? String(expectedHeartbeat!) : "nil")", isDebug: true)

        // Define alerts
        let alerts: [BackgroundAlert] = [
            BackgroundAlert(
                identifier: BackgroundAlertIdentifier.sixMin.rawValue,
                timeInterval: BackgroundAlertDuration.sixMinutes.rawValue,
                body: isBluetoothActive
                ? "App inactive for 6 minutes. Verify Bluetooth connectivity."
                : "App inactive for 6 minutes. Open to resume."
            ),
            BackgroundAlert(
                identifier: BackgroundAlertIdentifier.twelveMin.rawValue,
                timeInterval: BackgroundAlertDuration.twelveMinutes.rawValue,
                body: isBluetoothActive
                ? "App inactive for 12 minutes. Verify Bluetooth connectivity."
                : "App inactive for 12 minutes. Open to resume."
            ),
            BackgroundAlert(
                identifier: BackgroundAlertIdentifier.eighteenMin.rawValue,
                timeInterval: BackgroundAlertDuration.eighteenMinutes.rawValue,
                body: isBluetoothActive
                ? "App inactive for 18 minutes. Verify Bluetooth connectivity."
                : "App inactive for 18 minutes. Open to resume."
            )
        ]

        for alert in alerts {
            if let heartbeat = expectedHeartbeat {
                let threshold = heartbeat * 1.2
                if threshold >= alert.timeInterval {
                    //LogManager.shared.log(category: .backgroundAlerts, message: "BackgroundAlertManager: skipping alert id=\(alert.identifier) because threshold=\(threshold) >= timeInterval=\(alert.timeInterval)", isDebug: true)
                    continue
                }
            }

            let content = createNotificationContent(for: notificationTitlePrefix, body: alert.body)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: alert.timeInterval, repeats: false)
            let request = UNNotificationRequest(identifier: alert.identifier, content: content, trigger: trigger)

            //LogManager.shared.log(category: .backgroundAlerts, message: "BackgroundAlertManager: scheduling alert id=\(alert.identifier) in \(alert.timeInterval) seconds (\(alert.timeInterval / 60) minutes). body=\(alert.body)", isDebug: true)

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    LogManager.shared.log(category: .backgroundAlerts, message: "BackgroundAlertManager: error scheduling background alert id=\(alert.identifier) (\(alert.timeInterval / 60) minutes): \(error)", isDebug: true)
                } else {
                    LogManager.shared.log(category: .backgroundAlerts, message: "BackgroundAlertManager: successfully scheduled background alert id=\(alert.identifier) (\(alert.timeInterval / 60) minutes)", isDebug: true)
                }
            }
        }
    }

    /// Create notification content with a given title and body.
    /// - Parameters:
    ///   - title: The title of the notification.
    ///   - body: The body text of the notification.
    /// - Returns: Configured `UNMutableNotificationContent` object.
    private func createNotificationContent(for title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .defaultCritical
        content.categoryIdentifier = "loopfollow.background.alert"
        return content
    }

    /// Cancel all scheduled background alerts.
    private func cancelBackgroundAlerts() {
        let identifiers = BackgroundAlertIdentifier.allCases.map { $0.rawValue }
        //LogManager.shared.log(category: .backgroundAlerts, message: "BackgroundAlertManager: cancelBackgroundAlerts removing pending requests for identifiers: \(identifiers.joined(separator: ", "))", isDebug: true)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Remove all delivered notifications
    private func removeDeliveredNotifications() {
        let identifiers = BackgroundAlertIdentifier.allCases.map { $0.rawValue }
        //LogManager.shared.log(category: .backgroundAlerts, message: "BackgroundAlertManager: removeDeliveredNotifications removing delivered notifications for identifiers: \(identifiers.joined(separator: ", "))", isDebug: true)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

/// Struct representing a single background alert.
struct BackgroundAlert {
    let identifier: String
    let timeInterval: TimeInterval
    let body: String
}
