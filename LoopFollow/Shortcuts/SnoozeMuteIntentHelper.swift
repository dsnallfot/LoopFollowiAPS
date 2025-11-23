//
//  SnoozeMuteIntentHelper.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-11-23.
//

import Foundation

@MainActor
enum SnoozeMuteIntentHelper {

    static func enableSnoozeAll(minutes: Int) {
        let alarms = ViewControllerManager.shared.alarmViewController
        let targetDate = Date().addingTimeInterval(TimeInterval(minutes * 60))

        UserDefaultsRepository.alertSnoozeAllTime.value = targetDate
        UserDefaultsRepository.alertSnoozeAllIsSnoozed.value = true

        alarms?.reloadSnoozeTime(key: "alertSnoozeAllTime", setNil: false, value: targetDate)
        alarms?.reloadIsSnoozed(key: "alertSnoozeAllIsSnoozed", value: true)
    }

    static func disableSnoozeAll() {
        let alarms = ViewControllerManager.shared.alarmViewController

        UserDefaults.standard.removeObject(forKey: "alertSnoozeAllTime")
        UserDefaultsRepository.alertSnoozeAllIsSnoozed.value = false

        alarms?.reloadSnoozeTime(key: "alertSnoozeAllTime", setNil: true, value: Date())
        alarms?.reloadIsSnoozed(key: "alertSnoozeAllIsSnoozed", value: false)
    }

    static func enableMuteAll(minutes: Int) {
        let alarms = ViewControllerManager.shared.alarmViewController
        let targetDate = Date().addingTimeInterval(TimeInterval(minutes * 60))

        UserDefaultsRepository.alertMuteAllTime.value = targetDate
        UserDefaultsRepository.alertMuteAllIsMuted.value = true

        alarms?.reloadSnoozeTime(key: "alertMuteAllTime", setNil: false, value: targetDate)
        alarms?.reloadIsSnoozed(key: "alertMuteAllIsMuted", value: true)
    }

    static func disableMuteAll() {
        let alarms = ViewControllerManager.shared.alarmViewController

        UserDefaults.standard.removeObject(forKey: "alertMuteAllTime")
        UserDefaultsRepository.alertMuteAllIsMuted.value = false

        alarms?.reloadSnoozeTime(key: "alertMuteAllTime", setNil: true, value: Date())
        alarms?.reloadIsSnoozed(key: "alertMuteAllIsMuted", value: false)
    }
}
