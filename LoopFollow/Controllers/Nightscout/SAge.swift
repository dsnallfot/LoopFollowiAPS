import Foundation

fileprivate var isSageFetchInProgress = false
fileprivate var sageFetchStartedAt: Date? = nil

extension MainViewController {
    // NS Sage Web Call
    func webLoadNSSage() {
        let now = Date()
        
        if isSageFetchInProgress {
            let elapsed = now.timeIntervalSince(sageFetchStartedAt ?? now)
            
            if elapsed > 60 {
                // En pågående fetch verkar ha hängt → släpp låset och börja om.
                LogManager.shared.log(
                    category: .nightscout,
                    message: "[Sage] Detected stale in-progress Sage fetch (\(Int(elapsed)) s). Forcing reset and starting a new request.",
                    isDebug: false
                )
                isSageFetchInProgress = false
                sageFetchStartedAt = nil
            } else {
                // Normal “in progress” → logga och hoppa över.
                LogManager.shared.log(
                    category: .nightscout,
                    message: "[Sage] webLoadNSSage skipped: fetch already in progress (\(Int(elapsed)) s).",
                    isDebug: false
                )
                return
            }
        }
        isSageFetchInProgress = true
        sageFetchStartedAt = now

        let lastDateString = dateTimeUtils.getDateTimeString(addingDays: -60)
        let currentTimeString = dateTimeUtils.getDateTimeString()

        let parameters: [String: String] = [
            "find[eventType]": NightscoutUtils.EventType.sage.rawValue,
            "find[created_at][$gte]": lastDateString,
            "find[created_at][$lte]": currentTimeString,
            "count": "1"
        ]

        NightscoutUtils.executeRequest(eventType: .sage, parameters: parameters) { (result: Result<[sageData], Error>) in
            switch result {
            case .success(let data):
                DispatchQueue.main.async {
                    self.updateSage(data: data)
                }
                isSageFetchInProgress = false
                sageFetchStartedAt = nil
            case .failure(let error):
                LogManager.shared.log(category: .nightscout, message: "webLoadNSSage error, failed to fetch data: \(error.localizedDescription)")
                isSageFetchInProgress = false
                sageFetchStartedAt = nil
            }
        }
    }

    // NS Sage Response Processor
    func updateSage(data: [sageData]) {
        infoManager.clearInfoData(type: .sage)

        guard let firstSageData = data.first else { return }

        currentSage = firstSageData
        let lastSageString = firstSageData.created_at

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate,
                                   .withTime,
                                   .withDashSeparatorInDate,
                                   .withColonSeparatorInTime]

        if let sageTime = formatter.date(from: lastSageString)?.timeIntervalSince1970 {
            UserDefaultsRepository.alertSageInsertTime.value = sageTime

            if UserDefaultsRepository.alertAutoSnoozeCGMStart.value && (dateTimeUtils.getNowTimeIntervalUTC() - sageTime < 7200) {
                let snoozeTime = Date(timeIntervalSince1970: sageTime + 7200)
                UserDefaultsRepository.alertSnoozeAllTime.value = snoozeTime
                UserDefaultsRepository.alertSnoozeAllIsSnoozed.value = true
                guard let alarms = ViewControllerManager.shared.alarmViewController else { return }
                alarms.reloadIsSnoozed(key: "alertSnoozeAllIsSnoozed", value: true)
                alarms.reloadSnoozeTime(key: "alertSnoozeAllTime", setNil: false, value: snoozeTime)
            }

            let now = dateTimeUtils.getNowTimeIntervalUTC()
            let elapsedSeconds = now - sageTime

            // Calculate remaining time (10 days = 864,000 seconds)
            let maxUsageSeconds: TimeInterval = 864_000
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

                if remainingSeconds < 0 {
                    statusDot = "🔴"
                    infoManager.setPriority(true, for: .sage)
                } else if remainingSeconds <= 86400 {
                    statusDot = "🟡"
                    infoManager.setPriority(true, for: .sage)
                } else {
                    statusDot = "🟢"
                    infoManager.setPriority(false, for: .sage)
                }

                let countdown = remainingSeconds < 0 ? "-\(formattedDuration) \(statusDot)" : "\(formattedDuration) \(statusDot)"

                infoManager.updateInfoData(type: .sage, value: countdown)
            }
        }
    }
}
