//
//  Carbs.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2023-10-05.

//

import Foundation
extension MainViewController {
    // NS Carb Bolus Response Processor
    func processNSCarbs(entries: [[String:AnyObject]]) {
        // Because it's a small array, we're going to destroy and reload every time.
        carbData.removeAll()
        var lastFoundIndex = 0
        var lastFoundBolus = 0
        
        entries.reversed().forEach { currentEntry in
            var carbDate: String
            if currentEntry["timestamp"] != nil {
                carbDate = currentEntry["timestamp"] as! String
            } else if currentEntry["created_at"] != nil {
                carbDate = currentEntry["created_at"] as! String
            } else {
                return
            }
            
            let absorptionTime = currentEntry["absorptionTime"] as? Int ?? 0
            
            let foodType = currentEntry["foodType"]
            let fat = currentEntry["fat"] as? Double
            let protein = currentEntry["protein"] as? Double
            
            guard let parsedDate = NightscoutUtils.parseDate(carbDate),
                  let carbs = currentEntry["carbs"] as? Double else { return }
            
            let dateTimeStamp = parsedDate.timeIntervalSince1970
            let sgv = findNearestBGbyTime(needle: dateTimeStamp, haystack: bgData, startingIndex: lastFoundIndex)
            lastFoundIndex = sgv.foundIndex
            
            var offset = -50
            if sgv.sgv < Double(calculateMaxBgGraphValue() - 100) {
                let bolusTime = findNearestBolusbyTime(timeWithin: 300, needle: dateTimeStamp, haystack: bolusData, startingIndex: lastFoundBolus)
                lastFoundBolus = bolusTime.foundIndex
                
                offset = bolusTime.offset ? 75 : 25
            }
            
            if dateTimeStamp < (dateTimeUtils.getNowTimeIntervalUTC() + (3600 * UserDefaultsRepository.predictionToLoad.value)) {
                // Make the dot
                let dot = carbGraphStruct(value: Double(carbs), date: Double(dateTimeStamp), sgv: Int(sgv.sgv + Double(offset)), absorptionTime: absorptionTime, foodType: foodType as? String, fat: Double(fat ?? 0), protein: Double(protein ?? 0))
                carbData.append(dot)
            }
        }
        
        if UserDefaultsRepository.graphCarbs.value {
            updateCarbGraph()
        }
    }
    
    func updateTodaysCarbsFromEntries(entries: [[String:AnyObject]]) {
        var totalCarbs: Double = 0.0
        
        let calendar = Calendar.current
        let now = Date()
        
        for entry in entries {
            var carbDate: String = ""
            
            if let timestamp = entry["timestamp"] as? String {
                carbDate = timestamp
            } else if let createdAt = entry["created_at"] as? String {
                carbDate = createdAt
            } else {
                LogManager.shared.log(category: .nightscout, message: "Skipping carbs entry with no timestamp or created_at", isDebug: true)
                continue
            }
            
            guard let date = NightscoutUtils.parseDate(carbDate) else {
                continue
            }
            
            if calendar.isDateInToday(date) {
                if let carbs = entry["carbs"] as? Double {
                    totalCarbs += carbs
                } else {
                    LogManager.shared.log(category: .nightscout, message: "Carbs not found for entry", isDebug: true)
                }
            }
        }
        
        let resultString = String(format: "%.0f", totalCarbs)
        infoManager.updateInfoData(type: .carbsToday, value: resultString, unit: "g")
        //infoTable.reloadData()
    }
}
