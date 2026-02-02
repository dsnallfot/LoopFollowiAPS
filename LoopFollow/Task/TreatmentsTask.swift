//
//  TreatmentsTask.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-11.

//

import Foundation

extension MainViewController {
    func scheduleTreatmentsTask(initialDelay: TimeInterval = 5) {
        LogManager.shared.log(
            category: .taskScheduler,
            message: "scheduleTreatmentsTask(initialDelay=\(initialDelay))", isDebug: true, isTempDebug: true
        )
        let firstRun = Date().addingTimeInterval(initialDelay)
        TaskScheduler.shared.scheduleTask(id: .treatments, nextRun: firstRun) { [weak self] in
            guard let self = self else { return }
            self.treatmentsTaskAction()
        }
    }

    func treatmentsTaskAction() {
        // If Nightscout not enabled, wait 60s and try again
        guard IsNightscoutEnabled(), UserDefaultsRepository.downloadTreatments.value else {
            LogManager.shared.log(
                category: .taskScheduler,
                message: "treatmentsTaskAction(): NS disabled or downloadTreatments=false, rescheduling in 60s", isDebug: true, isTempDebug: true
            )
            TaskScheduler.shared.rescheduleTask(id: .treatments, to: Date().addingTimeInterval(60))
            return
        }

        WebLoadNSTreatments()

        TaskScheduler.shared.rescheduleTask(id: .treatments, to: Date().addingTimeInterval(60))//2 * 60))
    }
}
