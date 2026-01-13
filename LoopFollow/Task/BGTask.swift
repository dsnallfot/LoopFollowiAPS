//
//  BGTask.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-11.

//

import Foundation

extension MainViewController {
    func scheduleBGTask(initialDelay: TimeInterval = 2) {
        let firstRun = Date().addingTimeInterval(initialDelay)
        TaskScheduler.shared.scheduleTask(id: .fetchBG, nextRun: firstRun) { [weak self] in
            guard let self = self else { return }
            self.bgTaskAction()
        }
    }

    func bgTaskAction() {
        LogManager.shared.log(category: .temporaryDebug, message: "[BGTask] bgTaskAction start", isDebug: true)

        TaskScheduler.shared.rescheduleTask(
            id: .fetchBG,
            to: Date().addingTimeInterval(60)
        )

        LogManager.shared.log(category: .temporaryDebug, message: "[BGTask] after reschedule, NS enabled = \(IsNightscoutEnabled()), shareUser = \(UserDefaultsRepository.shareUserName.value.isEmpty ? "EMPTY" : "SET")", isDebug: true)

        if UserDefaultsRepository.shareUserName.value == "",
           UserDefaultsRepository.sharePassword.value == "",
           UserDefaultsRepository.dexAdhocOnly.value,
           !IsNightscoutEnabled()
        {
            LogManager.shared.log(category: .temporaryDebug, message: "[BGTask] abort: no Dexcom and NS disabled", isDebug: true)
            return
        }

        if UserDefaultsRepository.shareUserName.value != "" &&
            UserDefaultsRepository.sharePassword.value != "" &&
            !UserDefaultsRepository.dexAdhocOnly.value
        {
            LogManager.shared.log(category: .temporaryDebug, message: "[BGTask] calling webLoadDexShare()", isDebug: true)
            self.webLoadDexShare()
        } else {
            LogManager.shared.log(category: .temporaryDebug, message: "[BGTask] calling webLoadNSBGData()", isDebug: true)
            self.webLoadNSBGData()
        }
    }
}
