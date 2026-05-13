//
//  WarningEvent.swift
//  LoopFollow
//
//

import Foundation
extension MainViewController {
    private func linkCriticalPodFailureWarningToPumpChange(note: String, timestamp: TimeInterval) {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedNote.localizedCaseInsensitiveContains("Kritiskt poddfel") else { return }

        var history = Storage.shared.pumpChangeHistory
        guard !history.isEmpty else {
            LogManager.shared.log(
                category: .treatments,
                message: "Critical pod failure warning found, but pumpChangeHistory is empty. Will retry on next warning refresh: \(trimmedNote)",
                isDebug: true
            )
            return
        }

        // Poddfel-notisen hör normalt till sessionen som avslutades precis innan nästa pumpbyte.
        // Därför kopplas den till senaste pumpbyte som ligger före eller vid varningens timestamp.
        guard let targetIndex = history.indices
            .filter({ history[$0].date <= timestamp })
            .max(by: { history[$0].date < history[$1].date }) else {
            LogManager.shared.log(
                category: .treatments,
                message: "Critical pod failure warning found, but no pumpChangeHistory entry before noteDate=\(timestamp): \(trimmedNote)",
                isDebug: true
            )
            return
        }

        guard history[targetIndex].notes != trimmedNote || history[targetIndex].noteDate != timestamp else { return }

        history[targetIndex].notes = trimmedNote
        history[targetIndex].noteDate = timestamp
        Storage.shared.pumpChangeHistory = history.sorted { $0.date > $1.date }
        NotificationCenter.default.post(name: .pumpChangeHistoryUpdated, object: nil)

        LogManager.shared.log(
            category: .treatments,
            message: "Linked critical pod failure warning to pumpChangeHistory at \(history[targetIndex].date), noteDate=\(timestamp): \(trimmedNote)",
            isDebug: true
        )
    }
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

            linkCriticalPodFailureWarningToPumpChange(note: thisNote, timestamp: dateTimeStamp)
            
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
