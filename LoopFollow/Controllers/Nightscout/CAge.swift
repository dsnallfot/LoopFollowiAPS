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
                print("Error: \(error.localizedDescription)")
            }
        }
    }
    
    // NS Cage Response Processor
    func updateCage(data: [cageData]) {
        self.clearLastInfoData(index: 7)
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: CAGE") }
        if data.count == 0 {
            return
        }
        
        currentCage = data[0]
        let lastCageString = data[0].created_at
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate,
                                   .withTime,
                                   .withDashSeparatorInDate,
                                   .withColonSeparatorInTime]
        if let cageTime = formatter.date(from: lastCageString)?.timeIntervalSince1970 {
            UserDefaultsRepository.alertCageInsertTime.value = cageTime
            
            let now = dateTimeUtils.getNowTimeIntervalUTC()
            let secondsAgo = now - cageTime
            
            let oldFormatter = DateComponentsFormatter()
            oldFormatter.unitsStyle = .positional
            oldFormatter.allowedUnits = [.day, .hour]
            oldFormatter.zeroFormattingBehavior = [.pad]
            oldFormatter.maximumUnitCount = 0
            
            if let formattedDuration = oldFormatter.string(from: secondsAgo) {
                let spacedDuration = formattedDuration
                    .replacingOccurrences(of: "d", with: " d")
                    .replacingOccurrences(of: "h", with: " h")

                //tableData[7].value = spacedDuration
            }
            
            // Add 3 days to cageTime
            let threeDaysLater = cageTime + 3 * 24 * 60 * 60
            
            // Calculate the remaining time
            let timeRemaining = threeDaysLater - now
            
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
            // Update tableData[70].value with the remaining duration
            tableData[7].value = spacedRemainingDuration
        }
        infoTable.reloadData()
    }
}
