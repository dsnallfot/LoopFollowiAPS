//
//  SiteChange.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2023-10-06.

//

import Foundation
extension MainViewController {
    func processCage(entries: [cageData]) {
        if !entries.isEmpty {
            updateCage(data: entries)
        } else if let cage = currentCage {
            updateCage(data: [cage])
        } else {
            webLoadNSCage()
        }
    }
    
    // NS Pump Change Response Processor
    func processPumpChange(entries: [cageData]) {
        pumpChangeGraphData.removeAll()
        
        // Load existing pump change history
        var pumpChangeHistory = Storage.shared.pumpChangeHistory
        
        var lastFoundIndex = 0
        for entry in entries {
            let date = entry.created_at
            
            if let parsedDate = NightscoutUtils.parseDate(date) {
                let dateTimeStamp = parsedDate.timeIntervalSince1970
                let sgv = findNearestBGbyTime(needle: dateTimeStamp, haystack: bgData, startingIndex: lastFoundIndex)
                lastFoundIndex = sgv.foundIndex
                
                if dateTimeStamp < (dateTimeUtils.getNowTimeIntervalUTC() + (60 * 60)) {
                    let dot = DataStructs.timestampOnlyStruct(date: Double(dateTimeStamp), sgv: Int(18))
                    pumpChangeGraphData.append(dot)
                    
                    let newEntry = PumpChangeHistoryEntry(date: dateTimeStamp)
                    
                    // Prevent duplicates before saving
                    if !pumpChangeHistory.contains(where: { $0.date == newEntry.date }) {
                        pumpChangeHistory.append(newEntry)
                    }
                }
            } else {
                LogManager.shared.log(category: .nightscout, message: "Failed to parse date for site change", isDebug: true)
            }
        }
        
        // Save back to persistent storage if we have entries
        if !pumpChangeHistory.isEmpty {
            Storage.shared.pumpChangeHistory = pumpChangeHistory
        }
        
        if UserDefaultsRepository.graphOtherTreatments.value {
            updatePumpChange()
        }
    }
}
