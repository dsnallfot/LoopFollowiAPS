//
//  WarningEvent.swift
//  LoopFollow
//
//

import Foundation
extension MainViewController {
    // NS Warning Response Processor
    func processWarning(entries: [[String:AnyObject]]) {
        warningGraphData.removeAll()
        
        var lastFoundIndex = 0
        
        entries.reversed().forEach { currentEntry in
            guard let dateStr = currentEntry["timestamp"] as? String ?? currentEntry["created_at"] as? String else { return }
            
            guard let parsedDate = NightscoutUtils.parseDate(dateStr) else {
                return
            }
            
            let dateTimeStamp = parsedDate.timeIntervalSince1970
            let sgv = findNearestBGbyTime(needle: dateTimeStamp, haystack: bgData, startingIndex: lastFoundIndex)
            lastFoundIndex = sgv.foundIndex
            
            guard let thisNote = currentEntry["notes"] as? String else { return }
            
            if dateTimeStamp < (dateTimeUtils.getNowTimeIntervalUTC() + (60 * 60)) {
                let dot = DataStructs.noteStruct(date: Double(dateTimeStamp), sgv: Int(18), note: thisNote)
                warningGraphData.append(dot)
            }
        }
        
        if UserDefaultsRepository.graphOtherTreatments.value {
            updateWarningGraph()
        }
    }
}
