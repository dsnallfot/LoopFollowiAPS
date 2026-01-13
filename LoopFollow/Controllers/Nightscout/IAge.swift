//
//  IAge.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-08-05.

//

import Foundation
fileprivate var isIageFetchInProgress = false
extension MainViewController {
    // NS Iage Web Call
    func webLoadNSIage() {
        if isIageFetchInProgress { return }
        isIageFetchInProgress = true

        let lastDateString = dateTimeUtils.getDateTimeString(addingDays: -60)
        let currentTimeString = dateTimeUtils.getDateTimeString()

        let parameters: [String: String] = [
            "find[eventType]": NightscoutUtils.EventType.iage.rawValue,
            "find[created_at][$gte]": lastDateString,
            "find[created_at][$lte]": currentTimeString,
            "count": "1"
        ]

        NightscoutUtils.executeRequest(eventType: .iage, parameters: parameters) { (result: Result<[iageData], Error>) in
            switch result {
            case .success(let data):
                DispatchQueue.main.async {
                    self.updateIage(data: data)
                }
                isIageFetchInProgress = false
            case .failure(let error):
                LogManager.shared.log(category: .nightscout, message: "webLoadNSIage, failed to fetch data: \(error.localizedDescription)")
                isIageFetchInProgress = false
            }
        }
    }

    // NS Sage Response Processor
    func updateIage(data: [iageData]) {
        infoManager.clearInfoData(type: .iage)

        if data.isEmpty {
            return
        }
        
        currentIage = data[0]
        let lastIageString = data[0].created_at

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate,
                                   .withTime,
                                   .withDashSeparatorInDate,
                                   .withColonSeparatorInTime]

        if let iageTime = formatter.date(from: lastIageString )?.timeIntervalSince1970 {
            let now = dateTimeUtils.getNowTimeIntervalUTC()
            let secondsAgo = now - iageTime
            let daysAgo = secondsAgo / 86400 // Convert seconds to days

            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .positional
            formatter.allowedUnits = [ .day, .hour]
            formatter.zeroFormattingBehavior = [ .pad ]

            if let formattedDuration = formatter.string(from: secondsAgo) {
                let statusDot: String

                if daysAgo >= 14 {
                    statusDot = "🔴"
                    infoManager.setPriority(true, for: .iage)
                } else if daysAgo >= 9 {
                    statusDot = "🟡"
                    infoManager.setPriority(true, for: .iage)
                } else {
                    statusDot = "🟢"
                    infoManager.setPriority(false, for: .iage)
                }

                let displayValue = formattedDuration + " " + statusDot
                infoManager.updateInfoData(type: .iage, value: displayValue.trimmingCharacters(in: .whitespaces))
            }
        }
    }
}
