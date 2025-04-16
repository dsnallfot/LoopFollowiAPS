// DeviceStatusOpenAPS.swift
// LoopFollow
// Created by Jonas Björkert on 2024-05-19.
// Copyright © 2024 Jon Fawcett. All rights reserved.

import Foundation
import UIKit
import HealthKit

var sharedCRValue: String = ""
var sharedRawEvBG: String = ""
var sharedRawMinPredBG: String = ""
var sharedMinPredBG: Double = 0.0
var sharedLatestIOB: String = ""
var sharedLatestCOB: String = ""
var sharedLatestISF: String = ""
var sharedLatestSens: String = ""
var sharedLatestCarbReq: String = ""
var sharedLatestInsulinReq: String = ""
var sharedLatestMinMax: String = ""
var sharedLatestEvBG: String = ""

extension MainViewController {
    func DeviceStatusOpenAPS(formatter: ISO8601DateFormatter, lastDeviceStatus: [String: AnyObject]?, lastLoopRecord: [String: AnyObject]) {
        ObservableUserDefaults.shared.device.value = lastDeviceStatus?["device"] as? String ?? ""
        
        if lastLoopRecord["failureReason"] != nil {
            LoopStatusLabel.text = "X"
            latestLoopStatusString = "X"
            return
        }

        guard let enactedOrSuggested = lastLoopRecord["suggested"] as? [String: AnyObject] ?? lastLoopRecord["enacted"] as? [String: AnyObject] else {
            return
        }

        //var wasEnacted: Bool
        var lastLoopTime: TimeInterval = UserDefaultsRepository.alertLastLoopTime.value // Default to the stored value
/*
        if let enacted = lastLoopRecord["enacted"] as? [String: AnyObject] {
            //wasEnacted = true
            if let timestampString = enacted["timestamp"] as? String,
               let parsedLoopTime = formatter.date(from: timestampString)?.timeIntervalSince1970 {
                lastLoopTime = parsedLoopTime
                UserDefaultsRepository.alertLastLoopTime.value = lastLoopTime
                
                latestLoopTime = lastLoopTime
                
                // Format the `lastLoopTime` as HH.mm:ss
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "HH.mm:ss"
                let formattedLastLoopTime = dateFormatter.string(from: Date(timeIntervalSince1970: lastLoopTime))
                
                LogManager.shared.log(category: .deviceStatus, message: "New LastLoopTime: \(formattedLastLoopTime)", isDebug: true)
            }
        } else {
            //wasEnacted = false
            LogManager.shared.log(category: .deviceStatus, message: "Last devicestatus is missing enacted")
            
            // Format the `lastLoopTime` as HH.mm:ss
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH.mm:ss"
            let formattedLastLoopTime = dateFormatter.string(from: Date(timeIntervalSince1970: lastLoopTime))
            
            LoopStatusLabel.text = " ᮰"
            LoopStatusLabel.textColor = UIColor.gray
            latestLoopStatusString = "᮰"
            LogManager.shared.log(category: .deviceStatus, message: "Loop status 🔘 (\(formattedLastLoopTime))")
        }

        // Evaluate loop status based on `lastLoopTime`
        let timeDifferenceMinutes = (TimeInterval(Date().timeIntervalSince1970) - lastLoopTime) / 60
        
        // Format the `lastLoopTime` as HH.mm:ss
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH.mm:ss"
        let formattedLastLoopTime = dateFormatter.string(from: Date(timeIntervalSince1970: lastLoopTime))
        
        if timeDifferenceMinutes > 16 {
            LoopStatusLabel.text = " ᮰"
            LoopStatusLabel.textColor = UIColor(named: "LoopRed")
            latestLoopStatusString = "᮰"
            LogManager.shared.log(category: .deviceStatus, message: "Loop status 🔴 (\(formattedLastLoopTime))")
        } else if timeDifferenceMinutes > 11 {
            LoopStatusLabel.text = " ᮰"
            LoopStatusLabel.textColor = UIColor(named: "LoopYellow")
            latestLoopStatusString = "᮰"
            LogManager.shared.log(category: .deviceStatus, message: "Loop status 🟡 (\(formattedLastLoopTime))")
        } else {
            LoopStatusLabel.text = " ᮰"
            LoopStatusLabel.textColor = UIColor(named: "LoopGreen")
            latestLoopStatusString = "᮰"
            LogManager.shared.log(category: .deviceStatus, message: "Loop status 🟢 (\(formattedLastLoopTime))", isDebug: true)
        }
 */
        if let enacted = lastLoopRecord["enacted"] as? [String: AnyObject] {
            if let timestampString = enacted["timestamp"] as? String,
               let parsedLoopTime = formatter.date(from: timestampString)?.timeIntervalSince1970 {
                lastLoopTime = parsedLoopTime
                UserDefaultsRepository.alertLastLoopTime.value = lastLoopTime
                latestLoopTime = lastLoopTime
                
                let formattedLastLoopTime = formatTime(lastLoopTime)
                LogManager.shared.log(category: .deviceStatus, message: "New LastLoopTime: \(formattedLastLoopTime)", isDebug: true)
/*
                // Daniel: Set the timestamp directly for infoManager.updateInfoData**
                let formattedTime = Localizer.formatTimestampToLocalString(parsedLoopTime)
                infoManager.updateInfoData(type: .updated, value: formattedTime)
*/
            }
        } else {
            LogManager.shared.log(category: .deviceStatus, message: "Last devicestatus is missing enacted")

            let formattedLastLoopTime = formatTime(lastLoopTime)
            LoopStatusLabel.text = " ᮰"
            LoopStatusLabel.textColor = UIColor.gray
            latestLoopStatusString = "᮰"
            LogManager.shared.log(category: .deviceStatus, message: "Loop status ⚫️ (\(formattedLastLoopTime))")
        }

        // Evaluate loop status based on `lastLoopTime`
        let timeDifferenceMinutes = (TimeInterval(Date().timeIntervalSince1970) - lastLoopTime) / 60

        let formattedLastLoopTime = formatTime(lastLoopTime) // Reuse the function

        if timeDifferenceMinutes > 16 {
            LoopStatusLabel.text = " ᮰"
            LoopStatusLabel.textColor = UIColor(named: "LoopRed")
            latestLoopStatusString = "᮰"
            LogManager.shared.log(category: .deviceStatus, message: "Loop status 🔴 (\(formattedLastLoopTime))")
        } else if timeDifferenceMinutes > 11 {
            LoopStatusLabel.text = " ᮰"
            LoopStatusLabel.textColor = UIColor(named: "LoopYellow")
            latestLoopStatusString = "᮰"
            LogManager.shared.log(category: .deviceStatus, message: "Loop status 🟡 (\(formattedLastLoopTime))")
        } else {
            LoopStatusLabel.text = " ᮰"
            LoopStatusLabel.textColor = UIColor(named: "LoopGreen")
            latestLoopStatusString = "᮰"
            LogManager.shared.log(category: .deviceStatus, message: "Loop status 🟢 (\(formattedLastLoopTime))", isDebug: true)
        }

/*
            var updatedTime: TimeInterval?

            if let timestamp = enactedOrSuggested["timestamp"] as? String,
               let parsedTime = formatter.date(from: timestamp)?.timeIntervalSince1970 {
                updatedTime = parsedTime
                let formattedTime = Localizer.formatTimestampToLocalString(parsedTime)
                infoManager.updateInfoData(type: .updated, value: formattedTime)
            }
*/

        // ISF
        let profileISF = profileManager.currentISF()
        var enactedISF: HKQuantity?
        if let enactedISFValue = enactedOrSuggested["ISF"] as? Double {
            let isfInMmol = enactedISFValue * 0.0555 // Conversion factor for mmol/L
            let isfUnit = "mmol/L"
            sharedLatestISF = String(format: "%.1f %@", isfInMmol, isfUnit)

            var determinedISFUnit: HKUnit = .milligramsPerDeciliter
            if enactedISFValue < 25 {
                determinedISFUnit = .millimolesPerLiter
            }
            enactedISF = HKQuantity(unit: determinedISFUnit, doubleValue: enactedISFValue)
        }
        
        // Use mmol/L as the display unit
        let displayUnit: HKUnit = .millimolesPerLiter
        if let profileISF = profileISF, let enactedISF = enactedISF {
            let profileISFValue = profileISF.doubleValue(for: displayUnit)
            let enactedISFValue = enactedISF.doubleValue(for: displayUnit)
            var isfString = ""
            if sharedOverrideFactor != 1.0 {
                // Calculate an override ISF based on the sharedOverrideFactor
                let overrideISFValue = profileISFValue / sharedOverrideFactor
                isfString = String(format: "%.1f → %.1f → %.1f", profileISFValue, overrideISFValue, enactedISFValue)
            } else {
                isfString = String(format: "%.1f → %.1f", profileISFValue, enactedISFValue)
            }
            infoManager.updateInfoData(type: .isf, value: isfString, unit: "mmol/L/E")
            print("ISF updated: \(isfString)")
        } else if let profileISF = profileISF {
            let profileISFValue = profileISF.doubleValue(for: displayUnit)
            let isfString = String(format: "%.1f", profileISFValue)
            infoManager.updateInfoData(type: .isf, value: isfString, unit: "mmol/L/E")
            print("ISF updated: \(isfString)")
        }
            
            // MinPredBG
            if let reasonString = enactedOrSuggested["reason"] as? String {
                let pattern = "minPredBG: (-?\\d+(?:\\.\\d+)?)"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: reasonString, range: NSRange(location: 0, length: reasonString.utf16.count)) {
                    let nsString = reasonString as NSString
                    let minPredBGString = nsString.substring(with: match.range(at: 1))
                    if let minPredBG = Double(minPredBGString) {
                        let formattedMinPredBGString = String(format: "%.1f", minPredBG)
                        sharedMinPredBG = minPredBG
                        sharedRawMinPredBG = formattedMinPredBGString
                        print("Extracted MinPredBG from reason: \(formattedMinPredBGString)")
                    } else {
                        print("Failed to convert extracted MinPredBG to Double: \(minPredBGString)")
                    }
                } else {
                    print("MinPredBG not found in reason string.")
                }
            } else {
                // Fallback: Use UserDefaultsRepository.lowLine (already in correct units)
                let fallbackMinPredBG = Double(UserDefaultsRepository.lowLine.value)  * 0.0555
                let formattedFallbackMinPredBG = String(format: "%.1f", fallbackMinPredBG)
                sharedMinPredBG = fallbackMinPredBG
                sharedRawMinPredBG = formattedFallbackMinPredBG
                print("Reason string not available, using fallback MinPredBG: \(formattedFallbackMinPredBG)")
            }

            // Carb Ratio (CR)
            let profileCR = profileManager.currentCarbRatio()
            var enactedCR: Double?
            if let reasonString = enactedOrSuggested["reason"] as? String {
                let pattern = "CR: (\\d+(?:\\.\\d+)?)"
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let nsString = reasonString as NSString
                    if let match = regex.firstMatch(in: reasonString, range: NSRange(location: 0, length: nsString.length)) {
                        let crString = nsString.substring(with: match.range(at: 1))
                        enactedCR = Double(crString)
                    }
                }
            }

            if let profileCR = profileCR, let enactedCR = enactedCR, profileCR != enactedCR {
                infoManager.updateInfoData(type: .carbRatio, value: profileCR, enactedValue: enactedCR, separator: .arrow, unit: " g/E")
                sharedCRValue = String(format: "%.1f", enactedCR)
            } else if let profileCR = profileCR {
                infoManager.updateInfoData(type: .carbRatio, value: profileCR, unit: "g/E")
                sharedCRValue = String(format: "%.1f", profileCR)
            }

            // IOB
            if let iobMetric = InsulinMetric(from: lastLoopRecord["iob"], key: "iob") {
                infoManager.updateInfoData(type: .iob, value: iobMetric, unit: "E")
                latestIOB = iobMetric
                // Convert `latestIOB` to a string
                sharedLatestIOB = String(format: "%.2f E", latestIOB?.value ?? 0.00)
            }

            // COB
            if let cobMetric = CarbMetric(from: enactedOrSuggested, key: "COB") {
                infoManager.updateInfoData(type: .cob, value: cobMetric, unit: "g")
                latestCOB = cobMetric
                sharedLatestCOB = String(format: "%.0f g", latestCOB?.value ?? 0)
            } else if let reasonString = enactedOrSuggested["reason"] as? String {
                // Fallback: Extract COB from reason string
                let cobPattern = "COB: (\\d+(?:\\.\\d+)?)"
                if let cobRegex = try? NSRegularExpression(pattern: cobPattern),
                   let cobMatch = cobRegex.firstMatch(in: reasonString, range: NSRange(location: 0, length: reasonString.utf16.count)) {
                    let cobValueString = (reasonString as NSString).substring(with: cobMatch.range(at: 1))
                    if let cobValue = Double(cobValueString) {
                        let tempDict: [String: AnyObject] = ["COB": cobValue as AnyObject]
                        if let fallbackCobMetric = CarbMetric(from: tempDict, key: "COB") {
                            infoManager.updateInfoData(type: .cob, value: fallbackCobMetric, unit: "g")
                            latestCOB = fallbackCobMetric
                        } else {
                            print("Failed to create CarbMetric from extracted COB value: \(cobValue)")
                        }
                    } else {
                        print("Invalid COB value extracted from reason string: \(cobValueString)")
                    }
                } else {
                    print("COB pattern not found in reason string.")
                }
            }
        
        // BGI
        if let reasonString = enactedOrSuggested["reason"] as? String {
            let pattern = "BGI:\\s([-+]?[0-9]*\\.?[0-9])"

            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: reasonString, range: NSRange(location: 0, length: reasonString.utf16.count)) {

                let bgiValueString = (reasonString as NSString).substring(with: match.range(at: 1))

                if let bgiValue = Double(bgiValueString) {
                    let formattedBGI = String(format: "%@%.1f", bgiValue > 0 ? "+" : "", bgiValue)
                    let bgiString = "\(formattedBGI)"
                    
                    infoManager.updateInfoData(type: .bgi, value: bgiString, unit: "mmol/L")
                    print("Extracted BGI: \(bgiString)")
                } else {
                    print("Failed to convert BGI value to Double.")
                }
            } else {
                print("BGI pattern not found in reason string.")
            }
        }

        // Dev
        if let reasonString = enactedOrSuggested["reason"] as? String {
            let pattern = "Dev:\\s([-+]?[0-9]*\\.?[0-9])"

            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: reasonString, range: NSRange(location: 0, length: reasonString.utf16.count)) {

                let devValueString = (reasonString as NSString).substring(with: match.range(at: 1))

                if let devValue = Double(devValueString) {
                    let formattedDev = String(format: "%@%.1f", devValue > 0 ? "+" : "", devValue)
                    let devString = "\(formattedDev)"

                    infoManager.updateInfoData(type: .dev, value: devString, unit: "mmol/L")
                    print("Extracted Dev: \(devString)")
                } else {
                    print("Failed to convert Dev value to Double.")
                }
            } else {
                print("Dev pattern not found in reason string.")
            }
        }
        
        // AF (Adjustment Factor)
        if let reasonString = enactedOrSuggested["reason"] as? String {
            let afPattern = "AF:\\s(\\d+\\.\\d{1,2})" // Matches "AF: x.x" or "AF: x.xx"
            
            if let afRegex = try? NSRegularExpression(pattern: afPattern),
               let afMatch = afRegex.firstMatch(in: reasonString, range: NSRange(location: 0, length: reasonString.utf16.count)) {
                
                let afValueString = (reasonString as NSString).substring(with: afMatch.range(at: 1))
                
                if let afValue = Double(afValueString) {
                    infoManager.updateInfoDataForAF(value: afValue)
                    print("Extracted AF: \(afValue)")
                } else {
                    print("Invalid AF value extracted from reason string: \(afValueString)")
                }
            } else {
                print("AF pattern not found in reason string.")
            }
        }
        
        // SMB Ratio
        if let reasonString = enactedOrSuggested["reason"] as? String {
            let smbRatioPattern = "SMB Ratio:\\s(\\d+\\.\\d{1,2})" // Matches "SMB Ratio: x.x" or "SMB Ratio: x.xx"
            
            if let smbRatioRegex = try? NSRegularExpression(pattern: smbRatioPattern),
               let smbRatioMatch = smbRatioRegex.firstMatch(in: reasonString, range: NSRange(location: 0, length: reasonString.utf16.count)) {
                
                let smbRatioValueString = (reasonString as NSString).substring(with: smbRatioMatch.range(at: 1))
                
                if let smbRatioValue = Double(smbRatioValueString) {
                    infoManager.updateInfoDataForSMBRatio(value: smbRatioValue)
                    print("Extracted SMB Ratio: \(smbRatioValue)")
                } else {
                    print("Invalid SMB Ratio value extracted from reason string: \(smbRatioValueString)")
                    infoManager.updateInfoDataForSMBRatio(value: 0.50) // Default to 0.50 if parsing fails
                }
            } else {
                print("SMB Ratio pattern not found in reason string. Using default value: 0.50")
                infoManager.updateInfoDataForSMBRatio(value: 0.50) // Default to 0.50 if pattern is not found
            }
        }
        
        // Max SMB
        if let reasonString = enactedOrSuggested["reason"] as? String {
            let maxSmbPattern = "MaxSMB:\\s(\\d+\\.\\d{1,2})" // Matches "MaxSMB: x.x" or "MaxSMB: x.xx"
            
            if let maxSmbRegex = try? NSRegularExpression(pattern: maxSmbPattern),
               let maxSmbMatch = maxSmbRegex.firstMatch(in: reasonString, range: NSRange(location: 0, length: reasonString.utf16.count)) {
                
                let maxSmbValueString = (reasonString as NSString).substring(with: maxSmbMatch.range(at: 1))
                
                if let maxSmbValue = Double(maxSmbValueString) {
                    let formattedValue = String(format: "%.2f", maxSmbValue)  // Ensures two decimals e.g. "0.25"
                    infoManager.updateInfoData(type: .maxSMB, value: formattedValue, unit: "E")
                    print("Extracted MaxSMB: \(formattedValue)")
                } else {
                    print("Invalid MaxSMB value extracted from reason string: \(maxSmbValueString)")
                    infoManager.updateInfoData(type: .maxSMB, value: "0.00", unit: "E") // Default to 0 if parsing fails
                }
            } else {
                print("MaxSMB pattern not found in reason string. Using default value: 0.00")
                infoManager.updateInfoData(type: .maxSMB, value: "0.00", unit: "E") // Default to 0.50 if pattern is not found
            }
        }
        
        // SMB Status
        if let reasonString = enactedOrSuggested["reason"] as? String {
            let smbInactivePattern = "SMB INAKTIVERADE" // Matches exactly "SMB INAKTIVERADE"
            
            if let smbInactiveRegex = try? NSRegularExpression(pattern: smbInactivePattern) {
                let smbInactiveMatch = smbInactiveRegex.firstMatch(in: reasonString, range: NSRange(location: 0, length: reasonString.utf16.count))
                
                let smbInactive = (smbInactiveMatch != nil) // True if match is found, false otherwise
                
                let smbStatusString = smbInactive ? "Inaktiv 🚫" : "Aktiv 🟢"
                
                infoManager.updateInfoData(type: .smbStatus, value: smbStatusString)
                
                print("SMB Status Updated: \(smbStatusString)")
            }
        }
        
        // Insulin Required
        if let insulinReqMetric = InsulinMetric(from: enactedOrSuggested, key: "insulinReq") {
            infoManager.updateInfoData(type: .recBolus, value: insulinReqMetric, unit: "E")
            UserDefaultsRepository.deviceRecBolus.value = insulinReqMetric.value
            sharedLatestInsulinReq = String(format: "%.2f E", insulinReqMetric.value)
        } else {
            UserDefaultsRepository.deviceRecBolus.value = 0
            sharedLatestInsulinReq = "0 E"
        }
        
        // Daniel: Carbs Required
        if let carbsReq = enactedOrSuggested["carbsReq"] as? Double {
            let latestCarbReq = String(format: "%.0f g", carbsReq)
            sharedLatestCarbReq = latestCarbReq // Keep this unchanged
            
            let displayCarbReq = carbsReq > 0 ? "\(latestCarbReq) 🟡" : latestCarbReq
            infoManager.updateInfoData(type: .carbReq, value: displayCarbReq, unit: "g")
            
            print("Carbs Required updated: \(displayCarbReq)")
        } else {
            let defaultCarbReq = "0"
            sharedLatestCarbReq = defaultCarbReq // Keep this unchanged
            infoManager.updateInfoData(type: .carbReq, value: defaultCarbReq, unit: "g")
            
            print("Carbs Required not available, using default: \(defaultCarbReq)")
        }
        
        // Autosens
        if let sens = enactedOrSuggested["sensitivityRatio"] as? Double {
            let formattedSens = String(format: "%.0f", sens * 100.0) + " %"
            sharedLatestSens = formattedSens
 
            var formattedSensLimit: String?
 
            if let reasonString = enactedOrSuggested["reason"] as? String {
                let sensLimitPattern = "Autosens limit: ([0-9]+(?:\\.[0-9]{1,2})?) \\(([0-9]+(?:\\.[0-9]{1,2})?)\\)"
                if let regex = try? NSRegularExpression(pattern: sensLimitPattern),
                   let match = regex.firstMatch(in: reasonString, range: NSRange(location: 0, length: reasonString.utf16.count)) {
                    
                    let nsReasonString = reasonString as NSString
                    let xString = nsReasonString.substring(with: match.range(at: 1))
                    let yString = nsReasonString.substring(with: match.range(at: 2))
 
                    if let xValue = Double(xString), let yValue = Double(yString) {
                        formattedSensLimit = String(format: "%.0f% % → %.0f% %", yValue * 100.0, xValue * 100.0)
                    }
                }
            }
 
            if let formattedSensLimit = formattedSensLimit {
                infoManager.updateInfoData(type: .autosens, value: formattedSensLimit)
                print("Sensitivity Ratio (limit) updated: \(formattedSensLimit)")
            } else {
                infoManager.updateInfoData(type: .autosens, value: formattedSens)
                print("Sensitivity Ratio updated: \(formattedSens)")
            }
        } else {
            print("Missing or invalid sensitivityRatio in enactedOrSuggested.")
        }
        
        var predictionColor = UIColor.systemGray
        
        // Eventual BG Handling
        if let eventualBGValue = enactedOrSuggested["eventualBG"] as? Double {
            
            // Convert eventualBGValue to necessary formats
            let eventualBGFloatValue = Float(eventualBGValue) // Convert Double to Float for compatibility
            let eventualBGStringValue = String(describing: eventualBGValue) // Convert to String
            let formattedBGString = Localizer.toDisplayUnits(eventualBGStringValue).replacingOccurrences(of: ",", with: ".") // Format for display

            // Update visualization for remote meal info popup
            latestEvBG = formattedBGString + " mmol/L"
            sharedRawEvBG = formattedBGString
            sharedLatestEvBG = latestEvBG

            // Check if loop is inactive
            if ((TimeInterval(Date().timeIntervalSince1970) - lastLoopTime) / 60) > 16 {
                PredictionLabel.text = "  ❌  Loop ej aktiv!"
                predictionColor = UIColor.systemRed
                
            } else {
                // Use setBGColor(_:) if UserDefaultsRepository.colorBGText.value is enabled
                if UserDefaultsRepository.colorBGText.value {
                    predictionColor = setBGColor(Int(eventualBGValue))
                } else {
                    // Fallback to predefined colors
                    if let loopYellow = UIColor(named: "LoopYellow"),
                       let loopRed = UIColor(named: "LoopRed"),
                       let loopGreen = UIColor(named: "LoopGreen") {
                        
                        if eventualBGFloatValue >= UserDefaultsRepository.highLine.value {
                            predictionColor = loopYellow
                        } else if eventualBGFloatValue <= UserDefaultsRepository.lowLine.value {
                            predictionColor = loopRed
                        } else {
                            predictionColor = loopGreen
                        }
                    }
                }
                
                PredictionLabel.text = "    Prognos ⇢ \(formattedBGString)"
            }
        }

        // Ensure the color is updated on the main thread
        DispatchQueue.main.async {
            self.PredictionLabel.textColor = predictionColor
        }

            // Target
            let profileTargetHigh = profileManager.currentTargetHigh()
            var enactedTarget: HKQuantity?
            if let enactedTargetValue = enactedOrSuggested["current_target"] as? Double {
                var targetUnit = HKUnit.milligramsPerDeciliter
                if enactedTargetValue < 40 {
                    targetUnit = .millimolesPerLiter
                }
                enactedTarget = HKQuantity(unit: targetUnit, doubleValue: enactedTargetValue)
            }

            if let profileTargetHigh = profileTargetHigh, let enactedTarget = enactedTarget {
                let profileTargetHighFormatted = Localizer.formatQuantity(profileTargetHigh)
                let enactedTargetFormatted = Localizer.formatQuantity(enactedTarget)

                // Compare using formatted strings to avoid floating-point issues
                if profileTargetHighFormatted != enactedTargetFormatted {
                    infoManager.updateInfoData(type: .target, firstValue: profileTargetHigh, secondValue: enactedTarget, separator: .arrow, unit: "mmol/L")
                } else {
                    infoManager.updateInfoData(type: .target, value: profileTargetHigh, unit: "mmol/L")
                }
            }

            // TDD
            if let tddMetric = InsulinMetric(from: enactedOrSuggested, key: "TDD") {
                infoManager.updateInfoData(type: .tdd, value: tddMetric, unit: "E")
            }
        
        let predictioncolor = UIColor.systemGray
        PredictionLabel.textColor = predictioncolor
        topPredictionBG = UserDefaultsRepository.minBGScale.value
        
        if let predbgdata = enactedOrSuggested["predBGs"] as? [String: AnyObject] {
            let predictionTypes: [(type: String, colorName: String, dataIndex: Int)] = [
                ("ZT", "ZT", 12),
                ("IOB", "Insulin", 13),
                ("COB", "LoopYellow", 14),
                ("UAM", "UAM", 15)
            ]
            
            var minPredBG = Double.infinity
            var maxPredBG = -Double.infinity
            
            // Extract deliverAt and convert to TimeInterval, fallback to alertLastLoopTime
            var basePredictionTime = UserDefaultsRepository.alertLastLoopTime.value
            if let deliverAtString = enactedOrSuggested["deliverAt"] as? String {
                //print("📅 Raw deliverAt string: \(deliverAtString)")
                
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds] // Ensure it handles milliseconds
                
                if let deliverAtDate = formatter.date(from: deliverAtString) {
                    basePredictionTime = deliverAtDate.timeIntervalSince1970
                    //print("✅ Successfully parsed deliverAt: \(deliverAtString), converted to \(basePredictionTime)")
                } else {
                    print("❌ Failed to parse deliverAt: \(deliverAtString), falling back to alertLastLoopTime: \(basePredictionTime)")
                }
            } else {
                print("⚠️ No deliverAt found in enactedOrSuggested, using alertLastLoopTime: \(basePredictionTime)")
            }
            
            for (type, colorName, dataIndex) in predictionTypes {
                var predictionData = [ShareGlucoseData]()
                
                // Reset predictionTime for each dataset so they all start at the same time
                var predictionTime = basePredictionTime
                
                if let graphdata = predbgdata[type] as? [Double] {
                    let toLoad = Int(UserDefaultsRepository.predictionToLoad.value * 12)
                    
                    //print("📊 Processing prediction type: \(type), data count: \(graphdata.count), starting at \(predictionTime)")
                    
                    for i in 0...toLoad {
                        if i < graphdata.count {
                            let predictionValue = graphdata[i]
                            minPredBG = min(minPredBG, predictionValue)
                            maxPredBG = max(maxPredBG, predictionValue)
                            
                            let prediction = ShareGlucoseData(sgv: Int(round(predictionValue)), date: predictionTime, direction: "flat")
                            predictionData.append(prediction)
                            predictionTime += 300
                        }
                    }
                }
                
                let color = UIColor(named: colorName) ?? UIColor.systemPurple
                updatePredictionGraphGeneric(
                    dataIndex: dataIndex,
                    predictionData: predictionData,
                    chartLabel: type,
                    color: color
                )
            }
            
            if minPredBG != Double.infinity && maxPredBG != -Double.infinity {
                let value = "\(Localizer.toDisplayUnits(String(minPredBG)))/\(Localizer.toDisplayUnits(String(maxPredBG)))"
                infoManager.updateInfoData(type: .minMax, value: value, unit: "mmol/L")
                sharedLatestMinMax = "\(value) mmol/L"
            } else {
                infoManager.updateInfoData(type: .minMax, value: "N/A", unit: "mmol/L")
                sharedLatestMinMax = "N/A"
            }
        }
    }
    
    private func formatTime(_ timestamp: TimeInterval) -> String {
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH.mm:ss"
            return formatter
        }()
        return dateFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
