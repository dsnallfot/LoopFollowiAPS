//
//  Treatments.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2023-10-05.

//

import Foundation

extension Notification.Name {
    static let treatmentsUpdated = Notification.Name("TreatmentsUpdated")
}
fileprivate var isTreatmentsFetchInProgress = false
extension MainViewController {
    // NS Treatments Web Call
    // Downloads Basal, Bolus, Carbs, BG Check, Notes, Overrides
    func WebLoadNSTreatments() {
        if !UserDefaultsRepository.downloadTreatments.value { return }

        if isTreatmentsFetchInProgress {
            LogManager.shared.log(
                category: .nightscout,
                message: "WebLoadNSTreatments skipped: fetch already in progress",
                isDebug: true,
                isTempDebug: true
            )
            return
        }
        isTreatmentsFetchInProgress = true
        
        let startTimeString = dateTimeUtils.getDateTimeString(addingDays: -1 * UserDefaultsRepository.downloadDays.value)
        
        //let currentTimeString = dateTimeUtils.getDateTimeString(addingHours: 6)
        let currentTimeString = dateTimeUtils.getDateTimeString() //TEST
        let estimatedCount = max(UserDefaultsRepository.downloadDays.value * 100, 5000)//TEST
        
        let parameters: [String: String] = [
            "find[created_at][$gte]": startTimeString,
            "find[created_at][$lte]": currentTimeString,
            "count": "\(estimatedCount)",//TEST
        ]
        NightscoutUtils.executeDynamicRequest(eventType: .treatments, parameters: parameters) { (result: Result<Any, Error>) in
            switch result {
            case .success(let data):
                if let entries = data as? [[String: AnyObject]] {
                    // Uppdatera appens behandlingstillstånd på main-tråden som tidigare
                    DispatchQueue.main.async {
                        self.updateTreatments(entries: entries)
                    }
                    
                    // Skriv samma behandlingsdata till NightscoutCache i bakgrunden.
                    // Detta gör att TreatmentsTableView (och andra vyer som läser via NightscoutCache)
                    // får löpande uppdaterade 90-dagarsfiler utan extra nattliga fetchar.
                    DispatchQueue.global(qos: .utility).async {
                        if let startDate = NightscoutUtils.parseDate(startTimeString),
                           let endDate = NightscoutUtils.parseDate(currentTimeString) {

                            // Always overwrite the latest 24 hours in cache so edited/deleted/reposted
                            // treatments (same timestamp, changed duration/notes, etc.) never linger.
                            let last24hStart = max(startDate, endDate.addingTimeInterval(-24 * 60 * 60))

                            // 1) Hard refresh (delete + replace) for last 24 hours
                            NightscoutCache.refreshTreatmentsWindow(
                                from: last24hStart,
                                to: endDate,
                                entries: entries.map { $0 as [String: Any] }
                            )

                            // 2) Best-effort upsert for older treatments (do NOT delete older cache content)
                            // This prevents accidental data loss if Nightscout doesn't return the full window.
                            for entry in entries {
                                if let iso = entry["created_at"] as? String,
                                   let createdAt = NightscoutUtils.parseDate(iso),
                                   createdAt < last24hStart {
                                    NightscoutCache.upsertTreatment(from: entry as [String: Any])
                                }
                            }

                            NightscoutCache.purgeOldFiles()
                        } else {
                            // Fallback: if parsing fails, keep previous behavior (best-effort upsert)
                            for entry in entries {
                                NightscoutCache.upsertTreatment(from: entry as [String: Any])
                            }
                            NightscoutCache.purgeOldFiles()
                        }
                    }
                } else {
                    LogManager.shared.log(category: .nightscout, message: "WebLoadNSTreatments, Unexpected data structure")
                }
                isTreatmentsFetchInProgress = false
            case .failure(let error):
                LogManager.shared.log(category: .nightscout, message: "WebLoadNSTreatments, error \(error.localizedDescription)")
                isTreatmentsFetchInProgress = false
            }
        }
    }
    
    // Process and split out treatments to individual tasks
    func updateTreatments(entries: [[String:AnyObject]]) {
        
        var tempBasal: [[String:AnyObject]] = []
        var bolus: [[String:AnyObject]] = []
        var smb: [[String:AnyObject]] = []
        var carbs: [[String:AnyObject]] = []
        var temporaryOverride: [[String:AnyObject]] = []
        var temporaryTarget: [[String:AnyObject]] = []
        var note: [[String:AnyObject]] = []
        var bgCheck: [[String:AnyObject]] = []
        var suspendPump: [[String:AnyObject]] = []
        var resumePump: [[String:AnyObject]] = []
        var pumpSiteChange: [cageData] = []
        var cgmSensorStart: [sageData] = []
        var insulinCartridge: [iageData] = []

        for entry in entries {
            guard let eventType = entry["eventType"] as? String else {
                continue
            }
            
            switch eventType {
            case "Temp Basal":
                tempBasal.append(entry)
            case "Correction Bolus", "Bolus", "Insulinpenna":
                if let automatic = entry["automatic"] as? Bool, automatic {
                    smb.append(entry)
                } else {
                    bolus.append(entry)
                }
            case "SMB":
                smb.append(entry)
            case "Meal Bolus":
                carbs.append(entry)
                bolus.append(entry)
            case "Carb Correction", "Kolhydrater", "Dextro", "Måltid":
                carbs.append(entry)
            case "Temporary Override", "Exercise", "Override":
                temporaryOverride.append(entry)
            case "Temporary Target":
                temporaryTarget.append(entry)
            case "Note", "Announcement":
                if let notesText = entry["notes"] as? String {
                    if notesText.contains("PumpSuspend") {
                        // Tolka denna note som en Pump Suspend, inte som vanlig note
                        suspendPump.append(entry)
                    } else if notesText.contains("PumpResume") {
                        // Tolka denna note som en Pump Resume, inte som vanlig note
                        resumePump.append(entry)
                    } else {
                        // Vanlig note/announcement
                        note.append(entry)
                    }
                } else {
                    // Saknar notes-text, behandla som vanlig note
                    note.append(entry)
                }
            case "BG Check":
                bgCheck.append(entry)
            case "Suspend Pump":
                suspendPump.append(entry)
            case "Resume Pump":
                resumePump.append(entry)
            case "Pump Site Change", "Site Change", "Pumpbyte":
                if let createdAt = entry["created_at"] as? String {
                    let newEntry = cageData(created_at: createdAt)
                    pumpSiteChange.append(newEntry)
                }
            case "Sensor Start", "Sensor Change", "Sensorbyte", "Sensorstart":
                if let createdAt = entry["created_at"] as? String {
                    let newEntry = sageData(created_at: createdAt, notes: entry["notes"] as? String)
                    cgmSensorStart.append(newEntry)
                }
            case "Insulin Change":
                if let createdAt = entry["created_at"] as? String {
                    let newEntry = iageData(created_at: createdAt)
                    insulinCartridge.append(newEntry)
                }
            default:
                LogManager.shared.log(category: .nightscout, message: "No treatment match: \(String(describing: entry))", isDebug: true)
            }
        }
        
        if tempBasal.count > 0 {
            processNSBasals(entries: tempBasal)
        } else {
            if basalData.count > 0 {
                clearOldTempBasal()
            }
        }
        if bolus.count > 0 {
            processNSBolus(entries: bolus)
        } else {
            if bolusData.count > 0 {
                clearOldBolus()
            }
        }
        if smb.count > 0 {
            processNSSmb(entries: smb)
        } else {
            if smbData.count > 0 {
                clearOldSmb()
            }
        }
        updateTodaysCarbsFromEntries(entries: carbs)
        if carbs.count > 0 {
            processNSCarbs(entries: carbs)
        } else {
            if carbData.count > 0 {
                clearOldCarb()
            }
        }
        if bgCheck.count > 0 {
            processNSBGCheck(entries: bgCheck)
        } else {
            if bgCheckData.count > 0 {
                clearOldBGCheck()
            }
        }
        if temporaryOverride.count == 0 && overrideGraphData.count > 0 {
            clearOldOverride()
        }
        if temporaryOverride.count > 0 {
            processNSOverrides(entries: temporaryOverride)
        } else {
            infoManager.updateInfoData(type: .overridePercentage, value: "100 %")
            LogManager.shared.log(category: .general, message: "No Overrides found: Override percentage updated to default 100 %", isDebug: true)
        }

        if temporaryTarget.count == 0 && tempTargetGraphData.count > 0 {
            clearOldTempTarget()
        }
        if temporaryTarget.count > 0 {
            processNSTemporaryTarget(entries: temporaryTarget)
        }
        if suspendPump.count > 0 {
            processSuspendPump(entries: suspendPump)
        } else {
            if suspendGraphData.count > 0 {
                clearOldSuspend()
            }
        }
        if resumePump.count > 0 {
            processResumePump(entries: resumePump)
        } else {
            if resumeGraphData.count > 0 {
                clearOldResume()
            }
        }
        processSage(entries: cgmSensorStart)
        if cgmSensorStart.count > 0 {
            processSensorStart(entries: cgmSensorStart)
        } else {
            if sensorStartGraphData.count > 0 {
                clearOldSensor()
            }
        }

        processIage(entries: insulinCartridge)

        if note.count > 0 {
            processNotes(entries: note)
        } else {
            if noteGraphData.count > 0 {
                clearOldNotes()
            }
        }
        processCage(entries: pumpSiteChange)
        if pumpSiteChange.count > 0 {
            processPumpChange(entries: pumpSiteChange)
        } else {
            if pumpChangeGraphData.count > 0 {
                clearOldPump()
            }
        }

        // Synka statistik-arrayerna med de senaste behandlingsdatan och spara cache
        self.stats_syncTreatmentsFromLive()
        self.updateStats()
        self.stats_saveToCache()
        NotificationCenter.default.post(name: .treatmentsUpdated, object: nil)
    }
}
