//
//  DeviceStatus.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2023-10-05.
//  Copyright © 2023 Jon Fawcett. All rights reserved.
//

import Foundation
import UIKit
import Charts

extension MainViewController {
    // NS Device Status Web Call
    func webLoadNSDeviceStatus() {
        let parameters: [String: String] = ["count": "1"]
        
        NightscoutUtils.executeDynamicRequest(eventType: .deviceStatus, parameters: parameters) { result in
            switch result {
            case .success(let json):
                if let jsonDeviceStatus = json as? [[String: AnyObject]] {
                    DispatchQueue.main.async {
                        self.updateDeviceStatusDisplay(jsonDeviceStatus: jsonDeviceStatus)
                    }
                } else {
                    self.handleDeviceStatusError()
                }
                
            case .failure:
                self.handleDeviceStatusError()
            }
        }
    }
    
    private func handleDeviceStatusError() {
        LogManager.shared.log(category: .deviceStatus, message: "Device status fetch failed!")
        DispatchQueue.main.async {
            TaskScheduler.shared.rescheduleTask(id: .deviceStatus, to: Date().addingTimeInterval(10))
        }
    }
    
    func evaluateNotLooping(lastLoopTime: TimeInterval) {
        if let statusStackView = LoopStatusLabel.superview as? UIStackView {
            if ((TimeInterval(Date().timeIntervalSince1970) - lastLoopTime) / 60) > 16 {
                IsNotLooping = true
            } else {
                IsNotLooping = false
            }
        }
        latestLoopTime = lastLoopTime
    }
        
    // NS Device Status Response Processor
    func updateDeviceStatusDisplay(jsonDeviceStatus: [[String:AnyObject]]) {
        infoManager.clearInfoData(types: [.iob, .cob, .override, .battery, .pump, .target, .isf, .carbRatio, .updated, .recBolus, .tdd])

        if jsonDeviceStatus.count == 0 {
            LogManager.shared.log(category: .deviceStatus, message: "Device status is empty")
            return
        }
        
        //Process the current data first
        let lastDeviceStatus = jsonDeviceStatus[0] as [String : AnyObject]?
       
        // pump and uploader
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate,
                                   .withTime,
                                   .withDashSeparatorInDate,
                                   .withColonSeparatorInTime]

        if let lastPumpRecord = lastDeviceStatus?["pump"] as? [String: AnyObject] {
            // Parse the pump time from the "clock" field.
            if let clockString = lastPumpRecord["clock"] as? String,
               let lastPumpDate = formatter.date(from: clockString) {

                // Update reservoir data (if available)
                if let reservoirData = lastPumpRecord["reservoir"] as? Double {
                    latestPumpVolume = reservoirData
                    infoManager.updateInfoData(type: .pump, value: String(format: "%.0f", reservoirData) + " E")
                } else {
                    latestPumpVolume = 50.0
                    infoManager.updateInfoData(type: .pump, value: "50+E")
                }

                // Fetch pump status booleans from the nested "status" dictionary.
                var pumpSuspended = false
                var pumpBolusing = false
                if let pumpStatusRecord = lastPumpRecord["status"] as? [String: AnyObject] {
                    pumpSuspended = pumpStatusRecord["suspended"] as? Bool ?? false
                    pumpBolusing = pumpStatusRecord["bolusing"] as? Bool ?? false
                }
                
                // Calculate minutes elapsed since the last pump time (rounding up so it starts at 1).
                let currentTime = Date().timeIntervalSince1970
                let pumpStatusMinAgo = Int(ceil((currentTime - lastPumpDate.timeIntervalSince1970) / 60.0))
                
                // Determine the pump status indicator.
                // Default is green ("🟢"), but if suspended then red ("🔴"), if bolusing then blue ("🔷").
                var pumpStatus = "🟢"
                if pumpSuspended {
                    pumpStatus = "🔴"
                } else if pumpBolusing {
                    pumpStatus = "🔷"
                }
                
                // Update status for inactivity: if more than 30 minutes have passed.
                if pumpStatusMinAgo > 30 {
                    pumpStatus = "⏱️"
                }
                
                // Create a time formatter for HH:mm display.
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "HH:mm:ss"
                let formattedTime = timeFormatter.string(from: lastPumpDate)
                
                // Compose the final status string with the HH:mm:ss timestamp.
                let pumpStatusString = "\(pumpStatus) \(formattedTime)"
                infoManager.updateInfoData(type: .pumpStatus, value: pumpStatusString)
                
                // Update uploader battery status if available.
                if let uploader = lastDeviceStatus?["uploader"] as? [String: AnyObject],
                   let upbat = uploader["battery"] as? Double {
                    let isCharging = uploader["isCharging"] as? Bool ?? false
                    let batteryDisplay = (isCharging ? "⚡ " : "") + String(format: "%.0f", upbat) + " %"
                    infoManager.updateInfoData(type: .battery, value: batteryDisplay)
                    UserDefaultsRepository.deviceBatteryLevel.value = upbat
                }
            }
        }

        /*
        //pump and uploader
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate,
                                   .withTime,
                                   .withDashSeparatorInDate,
                                   .withColonSeparatorInTime]
        if let lastPumpRecord = lastDeviceStatus?["pump"] as! [String : AnyObject]? {
            if let lastPumpTime = formatter.date(from: (lastPumpRecord["clock"] as! String))?.timeIntervalSince1970  {
                if let reservoirData = lastPumpRecord["reservoir"] as? Double {
                    latestPumpVolume = reservoirData
                    infoManager.updateInfoData(type: .pump, value: String(format: "%.0f", reservoirData) + " E")
                } else {
                    latestPumpVolume = 50.0
                    infoManager.updateInfoData(type: .pump, value: "50+E")
                }

                if let uploader = lastDeviceStatus?["uploader"] as? [String: AnyObject],
                   let upbat = uploader["battery"] as? Double {
                    // Check if isCharging exists and is true
                    let isCharging = uploader["isCharging"] as? Bool ?? false
                    
                    // Add ⚡ symbol if charging
                    let batteryDisplay = (isCharging ? "⚡ " : "") + String(format: "%.0f", upbat) + " %"
                    
                    // Update info manager
                    infoManager.updateInfoData(type: .battery, value: batteryDisplay)
                    UserDefaultsRepository.deviceBatteryLevel.value = upbat
                }
            }
        }
        */

        // Daniel: Extract `created_at` timestamp from `lastDeviceStatus`
        if let createdAtString = lastDeviceStatus?["created_at"] as? String,
               let createdAtTime = formatter.date(from: createdAtString)?.timeIntervalSince1970 {
                
                // Update infoManager with the created_at timestamp
                let formattedTime = Localizer.formatTimestampToLocalString(createdAtTime)
                infoManager.updateInfoData(type: .updated, value: formattedTime)
            } else {
                LogManager.shared.log(category: .deviceStatus, message: "Failed to parse created_at timestamp.")
            }
        
        // Loop - handle new data
        if let lastLoopRecord = lastDeviceStatus?["loop"] as! [String : AnyObject]? {
            DeviceStatusLoop(formatter: formatter, lastLoopRecord: lastLoopRecord)

            var oText = ""
            currentOverride = 1.0
            if let lastOverride = lastDeviceStatus?["override"] as? [String: AnyObject],
               let isActive = lastOverride["active"] as? Bool, isActive {
                if let lastCorrection = lastOverride["currentCorrectionRange"] as? [String: AnyObject],
                   let minValue = lastCorrection["minValue"] as? Double,
                   let maxValue = lastCorrection["maxValue"] as? Double {

                    if let multiplier = lastOverride["multiplier"] as? Double {
                        currentOverride = multiplier
                        oText += String(format: "%.0f%%", (multiplier * 100))
                    } else {
                        oText += "100%"
                    }

                    oText += " ("
                    oText += Localizer.toDisplayUnits(String(minValue)) + "-" + Localizer.toDisplayUnits(String(maxValue)) + ")"
                }

                infoManager.updateInfoData(type: .override, value: oText)
            } else {
                infoManager.clearInfoData(type: .override)
            }
        }

        // OpenAPS - handle new data
        if let lastLoopRecord = lastDeviceStatus?["openaps"] as! [String : AnyObject]? {
            DeviceStatusOpenAPS(formatter: formatter, lastDeviceStatus: lastDeviceStatus, lastLoopRecord: lastLoopRecord)
        }

        // Start the timer based on the timestamp
        let now = dateTimeUtils.getNowTimeIntervalUTC()
        let secondsAgo = now - latestLoopTime
        
        DispatchQueue.main.async {
            if secondsAgo >= (20 * 60) {
                TaskScheduler.shared.rescheduleTask(
                    id: .deviceStatus,
                    to: Date().addingTimeInterval(5 * 60)
                )

            } else if secondsAgo >= (10 * 60) {
                TaskScheduler.shared.rescheduleTask(
                    id: .deviceStatus,
                    to: Date().addingTimeInterval(60)
                )

            } else if secondsAgo >= (7 * 60) {
                TaskScheduler.shared.rescheduleTask(
                    id: .deviceStatus,
                    to: Date().addingTimeInterval(30)
                )

            } else if secondsAgo >= (5 * 60) {
                TaskScheduler.shared.rescheduleTask(
                    id: .deviceStatus,
                    to: Date().addingTimeInterval(10)
                )
            } else {
                let interval = (310 - secondsAgo)
                TaskScheduler.shared.rescheduleTask(
                    id: .deviceStatus,
                    to: Date().addingTimeInterval(interval)
                )
            }
        }
        LogManager.shared.log(category: .deviceStatus, message: "Update Device Status done", isDebug: true)
    }
}
