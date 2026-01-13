//
//  Overrides.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2023-10-04.

//

import Foundation
import UIKit

var sharedOverrideFactor: Double = 1.0

extension MainViewController {
    // NS Override Response Processor
    func processNSOverrides(entries: [[String:AnyObject]]) {
        overrideGraphData.removeAll()
        var activeOverrideNote: String? = nil

        let now = Date().timeIntervalSince1970
        let predictionLoadHours = UserDefaultsRepository.predictionToLoad.value
        let predictionLoadSeconds = predictionLoadHours * 3600
        let maxEndDate = now + predictionLoadSeconds

        var persistentNote: String? = nil
        let notePersistenceInterval: TimeInterval = 60 // Persist the note for 1 minute

        entries.reversed().enumerated().forEach { (index, currentEntry) in
            guard let dateStr = currentEntry["timestamp"] as? String ?? currentEntry["created_at"] as? String else { return }
            guard let parsedDate = NightscoutUtils.parseDate(dateStr) else { return }

            var dateTimeStamp = parsedDate.timeIntervalSince1970
            let graphHours = 24 * UserDefaultsRepository.downloadDays.value
            if dateTimeStamp < dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours) {
                dateTimeStamp = dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours)
            }
            
            let multiplier = currentEntry["insulinNeedsScaleFactor"] as? Double ?? 1.0
            
            var duration: Double = 5.0
            if let _ = currentEntry["durationType"] as? String, index == entries.count - 1 {
                duration = dateTimeUtils.getNowTimeIntervalUTC() - dateTimeStamp + (60 * 60)
            } else {
                duration = (currentEntry["duration"] as? Double ?? 5.0) * 60
            }
            
            if duration < 60 { return }

            let reason = currentEntry["reason"] as? String ?? ""
            let notes = currentEntry["notes"] as? String ?? ""

            guard let enteredBy = currentEntry["enteredBy"] as? String else {
                return
            }

            var range: [Int] = []
            if let ranges = currentEntry["correctionRange"] as? [Int], ranges.count == 2 {
                range = ranges
            } else {
                let low = currentEntry["targetBottom"] as? Int
                let high = currentEntry["targetTop"] as? Int
                if (low == nil && high != nil) || (low != nil && high == nil) { return }
                range = [low ?? 0, high ?? 0]
            }
            
            let currentTimestamp = Date().timeIntervalSince1970
            let predictionHoursFromNow = currentTimestamp + UserDefaultsRepository.predictionToLoad.value * 3600
            
            var endDate: Double

            if dateTimeStamp + duration > predictionHoursFromNow {
                endDate = predictionHoursFromNow
            } else {
                endDate = dateTimeStamp + duration
            }
            
            if dateTimeStamp <= now && now < endDate {
                activeOverrideNote = currentEntry["notes"] as? String
            }
            
            if let note = activeOverrideNote, persistentNote == nil || (now - dateTimeStamp < notePersistenceInterval) {
                persistentNote = note
            }

            let dot = DataStructs.overrideStruct(insulNeedsScaleFactor: multiplier, date: dateTimeStamp, endDate: endDate, duration: duration, correctionRange: range, enteredBy: enteredBy, notes: notes, reason: currentEntry["reason"] as? String ?? "", sgv: -20)
            overrideGraphData.append(dot)
        }
        
        Observable.shared.override.value = persistentNote

        if ObservableUserDefaults.shared.device.value == "Trio" {
            if let note = persistentNote {
                infoManager.updateInfoData(type: .override, value: note)
                infoManager.setPriority(true, for: .override)
                LogManager.shared.log(category: .general, message: "Override \(note) presented in infotable", isDebug: true)
            } else {
                let note = "Normal profil"
                infoManager.updateInfoData(type: .override, value: note)
                infoManager.setPriority(false, for: .override)
                LogManager.shared.log(category: .general, message: "\(note) presented in infotable", isDebug: true)
            }
        }
        
        // Add override percentage update:
        var percentageString = "100 %"
        var foundOverride = false

        if let note = persistentNote {
            for trio in ProfileManager.shared.trioOverrides {
                // Check if the persistent note contains the trio's name
                if note.contains(trio.name) {
                    if let perc = trio.percentage {
                        // Determine the arrow to display based on the percentage
                        let arrow: String
                        if perc > 100.0 {
                            arrow = "🔺"
                        } else if perc < 100.0 {
                            arrow = "🔻"
                        } else {
                            arrow = ""
                        }
                        percentageString = "\(Int(perc)) %" + (arrow.isEmpty ? "" : " \(arrow)")
                        // Directly set the shared override factor using the double value from trio.percentage (converted to a factor)
                        sharedOverrideFactor = perc / 100.0
                        foundOverride = true
                        break
                    }
                }
            }
        }

        // If no override was found (or note was nil), reset to 1.0
        if !foundOverride {
            sharedOverrideFactor = 1.0
            percentageString = "100 %"
        }

        infoManager.updateInfoData(type: .overridePercentage, value: percentageString)
        LogManager.shared.log(category: .general, message: "Override percentage updated: \(percentageString)", isDebug: true)
        //LogManager.shared.log(category: .general, message: "Override factor updated: \(sharedOverrideFactor)", isDebug: true)
        
        if UserDefaultsRepository.graphOtherTreatments.value {
            updateOverrideGraph()
        }
    }

}
