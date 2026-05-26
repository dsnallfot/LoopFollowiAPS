//
//  AlarmTask.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-12.

//


import Foundation

enum AlarmCheckReason {
    case scheduled
    case bg
    case treatments
    case deviceStatus
}

extension MainViewController {
    func scheduleAlarmTask(initialDelay: TimeInterval = 30) {
        let firstRun = Date().addingTimeInterval(initialDelay)
        TaskScheduler.shared.scheduleTask(id: .alarmCheck, nextRun: firstRun) { [weak self] in
            guard let self = self else { return }
            self.alarmTaskAction(reason: .scheduled)
        }
    }

    func alarmTaskAction(reason: AlarmCheckReason = .scheduled) {
        DispatchQueue.main.async {
            LogManager.shared.log(
                category: .taskScheduler,
                message: "alarmTaskAction ran with reason: \(reason)",
                isDebug: true,
                isTempDebug: true
            )

            switch reason {
            case .bg:
                if self.bgData.count > 0 {
                    self.checkBGAlarms(bgs: self.bgData)
                }

            case .treatments:
                self.checkTreatmentAlarms()

            case .deviceStatus:
                self.checkDeviceStatusAlarms()

            case .scheduled:
                if self.bgData.count > 0 {
                    self.checkBGAlarms(bgs: self.bgData)
                }
                self.checkDeviceStatusAlarms()
                self.checkTreatmentAlarms()
            }

            if self.overrideGraphData.count > 0 {
                self.checkOverrideAlarms()
            }
            if self.tempTargetGraphData.count > 0 {
                self.checkTempTargetAlarms()
            }

            if reason == .scheduled {
                TaskScheduler.shared.rescheduleTask(id: .alarmCheck, to: Date().addingTimeInterval(30))
            }
        }
    }
}
