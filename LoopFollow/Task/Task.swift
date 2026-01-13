//
//  Task.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-12.

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
        scheduleNSOnlyGlucosePrefetchTask()
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
            })
        }
    }

        /// Schedules a nightly Trio→Nightscout glucose cache refresh
        /// (used by GlucoseView for gap analysis).
        func scheduleNSOnlyGlucosePrefetchTask() {
            let calendar = Calendar.current
            let now = Date()

            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = 1
            components.minute = 30
            components.second = 0

            let todayAt0130 = calendar.date(from: components) ?? now
            let nextRun: Date

            if todayAt0130 <= now {
                nextRun = calendar.date(byAdding: .day, value: 1, to: todayAt0130) ?? now
            } else {
                nextRun = todayAt0130
            }

            TaskScheduler.shared.scheduleTask(id: .nsOnlyGlucosePrefetch,
                                              nextRun: nextRun) { [weak self] in
                self?.nsOnlyGlucosePrefetchAction()
            }
        }

        /// Nightly refresh of Trio→NS glucose cache
        /// Fetches the last N days to fill late uploads & gaps.
        func nsOnlyGlucosePrefetchAction() {
            let cal = Calendar.current
            let now = Date()
            let today = cal.startOfDay(for: now)

            let daysToFetch = 7   // ⬅️ lagom: fyller sena hål utan att vara tungt

            LogManager.shared.log(
                category: .taskScheduler,
                message: "NS-only glucose prefetch task running (last \(daysToFetch) days)",
                isDebug: true
            )

            Task {
                let start = cal.date(byAdding: .day, value: -daysToFetch, to: today) ?? today
                let sgvBatch = await NightscoutUtils.fetchSGVWindow(from: start, to: now)

                if !sgvBatch.isEmpty {
                    GlucoseNSOnlyCache.mergeSGVBatch(sgvBatch)
                    GlucoseNSOnlyCache.purgeOldFiles()
                }

                LogManager.shared.log(
                    category: .taskScheduler,
                    message: "NS-only glucose prefetch completed, scheduling next run",
                    isDebug: true
                )

                // Reschedule next night
                DispatchQueue.main.async {
                    self.scheduleNSOnlyGlucosePrefetchTask()
                }
            }
        }
    }
