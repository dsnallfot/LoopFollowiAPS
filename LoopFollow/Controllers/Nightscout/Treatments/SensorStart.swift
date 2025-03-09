//
//  SensorStart.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2023-10-04.
//  Copyright © 2023 Jon Fawcett. All rights reserved.
//

import Foundation
extension MainViewController {
    func processSage(entries: [sageData]) {
        if !entries.isEmpty {
            updateSage(data: entries)
        } else if let sage = currentSage {
            updateSage(data: [sage])
        } else {
            webLoadNSSage()
        }
    }
    
    // NS Sensor Start Response Processor
    func processSensorStart(entries: [sageData]) {
        sensorStartGraphData.removeAll()
        var lastFoundIndex = 0

        // Load existing sensor start history
        var sensorStartHistory = Storage.shared.sensorStartNotes

        for entry in entries {
            let date = entry.created_at

            if let parsedDate = NightscoutUtils.parseDate(date) {
                let dateTimeStamp = parsedDate.timeIntervalSince1970
                let sgv = findNearestBGbyTime(needle: dateTimeStamp, haystack: bgData, startingIndex: lastFoundIndex)
                lastFoundIndex = sgv.foundIndex

                let thisNote = entry.notes ?? ""

                if dateTimeStamp < (dateTimeUtils.getNowTimeIntervalUTC() + (60 * 60)) {
                    let dot = DataStructs.sensorStartStruct(date: Double(dateTimeStamp), sgv: Int(18), note: thisNote)
                    sensorStartGraphData.append(dot)

                    let newEntry = SensorStartHistoryEntry(date: dateTimeStamp, note: thisNote)

                    // Prevent duplicates before saving
                    if !sensorStartHistory.contains(where: { $0.date == newEntry.date }) {
                        sensorStartHistory.append(newEntry)
                    }
                }
            } else {
                print("Failed to parse date")
            }
        }

        // 🔹 Save back to persistent storage only if it's an array
        if !sensorStartHistory.isEmpty {
            Storage.shared.sensorStartNotes = sensorStartHistory
        }
        
        if UserDefaultsRepository.graphOtherTreatments.value {
            updateSensorStart()
        }
    }
}
