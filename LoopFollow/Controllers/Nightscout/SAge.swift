import Foundation

extension MainViewController {
    // NS Sage Web Call
    func webLoadNSSage() {
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
            case .failure(let error):
                print("Failed to fetch data: \(error.localizedDescription)")
            }
        }
    }
    
    // NS Sage Response Processor
    func updateSage(data: [sageData]) {
        self.clearLastInfoData(index: 6)
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process/Display: SAGE") }
        if data.count == 0 {
            return
        }
        currentSage = data[0]
        let lastSageString = data[0].created_at
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate,
                                   .withTime,
                                   .withDashSeparatorInDate,
                                   .withColonSeparatorInTime]
        if let sageTime = formatter.date(from: lastSageString)?.timeIntervalSince1970 {
            UserDefaultsRepository.alertSageInsertTime.value = sageTime
            
            if UserDefaultsRepository.alertAutoSnoozeCGMStart.value && (dateTimeUtils.getNowTimeIntervalUTC() - UserDefaultsRepository.alertSageInsertTime.value < 7200) {
                let snoozeTime = Date(timeIntervalSince1970: UserDefaultsRepository.alertSageInsertTime.value + 7200)
                UserDefaultsRepository.alertSnoozeAllTime.value = snoozeTime
                UserDefaultsRepository.alertSnoozeAllIsSnoozed.value = true
                guard let alarms = self.tabBarController!.viewControllers?[1] as? AlarmViewController else { return }
                alarms.reloadIsSnoozed(key: "alertSnoozeAllIsSnoozed", value: true)
                alarms.reloadSnoozeTime(key: "alertSnoozeAllTime", setNil: false, value: snoozeTime)
            }
            
            let now = dateTimeUtils.getNowTimeIntervalUTC()
            let secondsAgo = now - sageTime
            let days = 24 * 60 * 60
            
            let oldFormatter = DateComponentsFormatter()
            oldFormatter.unitsStyle = .positional // Use the appropriate positioning for the current locale
            oldFormatter.allowedUnits = [ .day, .hour] // Units to display in the formatted string
            oldFormatter.zeroFormattingBehavior = [ .pad ] // Pad with zeroes where appropriate for the locale

            // Set maximumUnitCount to 0 to include all available units
            oldFormatter.maximumUnitCount = 0
            
            if let formattedDuration = oldFormatter.string(from: secondsAgo) {
               // Manually add spaces between the number and units
                let spacedDuration = formattedDuration
                    .replacingOccurrences(of: "d", with: " d")
                    .replacingOccurrences(of: "h", with: " h")

                //tableData[6].value = spacedDuration
            }
            
            // Add 10 days to sageTime
            let tenDaysLater = sageTime + 10 * 24 * 60 * 60
            
            // Calculate the remaining time
            let timeRemaining = tenDaysLater - now
            
            // Extract the components
            let daysRemaining = Int(timeRemaining / (24 * 60 * 60))
            let hoursRemaining = Int((timeRemaining.truncatingRemainder(dividingBy: 24 * 60 * 60)) / (60 * 60))
            let minutesRemaining = Int((timeRemaining.truncatingRemainder(dividingBy: 60 * 60)) / 60)
            
            // Construct the string manually
            var spacedRemainingDuration = ""
            if daysRemaining > 0 {
                spacedRemainingDuration += "\(daysRemaining)d "
            }
            if hoursRemaining > 0 || daysRemaining > 0 {
                spacedRemainingDuration += "\(hoursRemaining)h "
            }
            if daysRemaining == 0 {
                spacedRemainingDuration += "\(minutesRemaining)m"
            }
            // Update tableData[60].value with the remaining duration
            tableData[6].value = spacedRemainingDuration
        }
        infoTable.reloadData()
    }
}
