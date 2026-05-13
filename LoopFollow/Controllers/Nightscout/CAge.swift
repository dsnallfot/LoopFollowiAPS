//
//  CAge.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2023-10-05.

//

import Foundation

fileprivate var isCageFetchInProgress = false
fileprivate var cageFetchStartedAt: Date? = nil

extension MainViewController {
    // NS Cage Web Call
    func webLoadNSCage() {
        let now = Date()
        
        if isCageFetchInProgress {
            let elapsed = now.timeIntervalSince(cageFetchStartedAt ?? now)
            
            if elapsed > 60 {
                LogManager.shared.log(
                    category: .nightscout,
                    message: "[Cage] Detected stale in-progress Cage fetch (\(Int(elapsed)) s). Forcing reset and starting a new request.",
                    isDebug: false
                )
                isCageFetchInProgress = false
                cageFetchStartedAt = nil
            } else {
                LogManager.shared.log(
                    category: .nightscout,
                    message: "[Cage] webLoadNSCage skipped: fetch already in progress (\(Int(elapsed)) s).",
                    isDebug: false
                )
                return
            }
        }
        isCageFetchInProgress = true
        cageFetchStartedAt = now

        let currentTimeString = dateTimeUtils.getDateTimeString()

        let parameters: [String: String] = [
            "find[eventType]": NightscoutUtils.EventType.cage.rawValue,
            "find[created_at][$lte]": currentTimeString,
            "count": "1"
        ]

        NightscoutUtils.executeRequest(eventType: .cage, parameters: parameters) { (result: Result<[cageData], Error>) in
            switch result {
            case .success(let data):
                self.updateCage(data: data)
                isCageFetchInProgress = false
                cageFetchStartedAt = nil
            case .failure(let error):
                LogManager.shared.log(category: .nightscout, message: "webLoadNSCage, error: \(error.localizedDescription)")
                isCageFetchInProgress = false
                cageFetchStartedAt = nil
            }
        }
    }

    // NS Cage Response Processor
    func updateCage(data: [cageData]) {
        infoManager.clearInfoData(type: .cage)
        guard let firstCageData = data.first else { return }

        currentCage = firstCageData
        let lastCageString = firstCageData.created_at

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate,
                                   .withTime,
                                   .withDashSeparatorInDate,
                                   .withColonSeparatorInTime]

        if let cageTime = formatter.date(from: lastCageString)?.timeIntervalSince1970 {
            UserDefaultsRepository.alertCageInsertTime.value = cageTime
            let now = dateTimeUtils.getNowTimeIntervalUTC()
            let elapsedSeconds = now - cageTime

            // Calculate remaining time (72 hours = 259,200 seconds)
            let maxUsageSeconds: TimeInterval = 259_200
            let remainingSeconds = maxUsageSeconds - elapsedSeconds

            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated // Use abbreviated for better control of output
            formatter.zeroFormattingBehavior = [] // Disable padding with leading zeros

            if abs(remainingSeconds) < 86_400 { // Less than 24 hours
                formatter.allowedUnits = [.hour]
            } else {
                formatter.allowedUnits = [.day, .hour]
            }

            if let formattedDuration = formatter.string(from: abs(remainingSeconds)) {

                // Add a negative sign for overdue time and set the status dot
                let statusDot: String

                if remainingSeconds < 43200 { //When 12h remains, indicate red, for saftey margin due to 203 errors
                    statusDot = "🔴"
                    infoManager.setPriority(true, for: .cage)
                } else if remainingSeconds <= 86400 {
                    statusDot = "🟡"
                    infoManager.setPriority(true, for: .cage)
                } else {
                    statusDot = "🟢"
                    infoManager.setPriority(false, for: .cage)
                }

                let countdown = remainingSeconds < 0 ? "-\(formattedDuration) \(statusDot)" : "\(formattedDuration) \(statusDot)"

                infoManager.updateInfoData(type: .cage, value: countdown)
            }
        }
    }
}
