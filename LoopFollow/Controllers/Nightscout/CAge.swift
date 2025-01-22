//
//  CAge.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2023-10-05.
//  Copyright © 2023 Jon Fawcett. All rights reserved.
//

import Foundation

extension MainViewController {
    // NS Cage Web Call
    func webLoadNSCage() {
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
            case .failure(let error):
                LogManager.shared.log(category: .nightscout, message: "webLoadNSCage, error: \(error.localizedDescription)")
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
            formatter.unitsStyle = .positional
            formatter.allowedUnits = [.day, .hour]
            formatter.zeroFormattingBehavior = [.pad]

            if let formattedDuration = formatter.string(from: abs(remainingSeconds)) {
                let spacedDuration = formattedDuration
                    .replacingOccurrences(of: "d", with: " d")
                    .replacingOccurrences(of: "h", with: " h")

                // Add a negative sign for overdue time
                let countdown = remainingSeconds < 0 ? "-\(formattedDuration)" : formattedDuration

                infoManager.updateInfoData(type: .cage, value: countdown)
            }
        }
    }
}
