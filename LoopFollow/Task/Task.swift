//
//  Task.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-12.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import Foundation

extension MainViewController {

    func scheduleAllTasks() {
        scheduleBGTask()
        scheduleProfileTask()
        scheduleDeviceStatusTask()
        scheduleTreatmentsTask()
        scheduleMinAgoTask()
        scheduleCalendarTask()
        scheduleAlarmTask()
        scheduleCacheTask()
        scheduleStatsPrefetchTask()
    }

    /// Schedules a nightly stats prefetch using StatsDataService.
    /// The task is scheduled around 02:00 local time and will be executed
    /// when the app is awake (e.g. via Bluetooth heartbeats).
    func scheduleStatsPrefetchTask() {
        let calendar = Calendar.current
        let now = Date()

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 2
        components.minute = 0
        components.second = 0

        let todayAtTwo = calendar.date(from: components) ?? now
        let nextRun: Date

        if todayAtTwo <= now {
            // If we've already passed 03:00 today, schedule for tomorrow.
            nextRun = calendar.date(byAdding: .day, value: 1, to: todayAtTwo) ?? now
        } else {
            // Otherwise, schedule for 03:00 today.
            nextRun = todayAtTwo
        }

        TaskScheduler.shared.scheduleTask(id: .statsPrefetch, nextRun: nextRun) { [weak self] in
            guard let self = self else { return }

            LogManager.shared.log(
                category: .taskScheduler,
                message: "StatsPrefetch task running (nightly stats prefetch)",
                isDebug: true
            )

            // Create a temporary StatsDataService bound to this MainViewController.
            let statsService = StatsDataService(mainViewController: self)

            // Använd samma logik som vid öppning av statistik: säkerställ att det finns färska data,
            // och fyll upp till 90 dagar endast om det saknas eller är "stale".
            statsService.ensureDataAvailable(onProgress: {
                // We keep this empty for now; could log progress if needed.
            }, completion: {
                LogManager.shared.log(
                    category: .taskScheduler,
                    message: "StatsPrefetch task completed, scheduling next run",
                    isDebug: true
                )

                // När vi är klara schemalägger vi nästa natt.
                DispatchQueue.main.async {
                    self.scheduleStatsPrefetchTask()
                }
            })        }
    }
}
