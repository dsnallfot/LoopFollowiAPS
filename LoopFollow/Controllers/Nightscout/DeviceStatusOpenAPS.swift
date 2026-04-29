// DeviceStatusOpenAPS.swift
// LoopFollow
// Created by Jonas Björkert on 2024-05-19.
// Copyright © 2024 Jon Fawcett. All rights reserved.

import Foundation
import UIKit
import HealthKit

extension MainViewController {
    func DeviceStatusOpenAPS(formatter: ISO8601DateFormatter, lastDeviceStatus: [String: AnyObject]?, lastLoopRecord: [String: AnyObject]) {
        ObservableUserDefaults.shared.device.value = lastDeviceStatus?["device"] as? String ?? ""
        let storage = Storage.shared
        
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
            storage.sharedLatestISF.value = String(format: "%.1f %@", isfInMmol, isfUnit)
            storage.sharedRawISF.value = isfInMmol

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
            LogManager.shared.log(category: .deviceStatus, message: "ISF updated: \(isfString)", isDebug: true)
        } else if let profileISF = profileISF {
            let profileISFValue = profileISF.doubleValue(for: displayUnit)
            let isfString = String(format: "%.1f", profileISFValue)
            infoManager.updateInfoData(type: .isf, value: isfString, unit: "mmol/L/E")
            LogManager.shared.log(category: .deviceStatus, message: "ISF updated: \(isfString)", isDebug: true)
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
                        storage.sharedMinPredBG.value = minPredBG
                        storage.sharedRawMinPredBG.value = formattedMinPredBGString
                        //LogManager.shared.log(category: .deviceStatus, message: "Extracted MinPredBG from reason: \(formattedMinPredBGString)", isDebug: true)
                    } else {
                        LogManager.shared.log(category: .deviceStatus, message: "Failed to convert extracted MinPredBG to Double: \(minPredBGString)", isDebug: true)
                    }
                } else {
                    LogManager.shared.log(category: .deviceStatus, message: "MinPredBG not found in reason string.", isDebug: true)
                }
            } else {
                // Fallback: Use UserDefaultsRepository.lowLine (already in correct units)
                let fallbackMinPredBG = Double(UserDefaultsRepository.lowLine.value)  * 0.0555
                let formattedFallbackMinPredBG = String(format: "%.1f", fallbackMinPredBG)
                storage.sharedMinPredBG.value = fallbackMinPredBG
                storage.sharedRawMinPredBG.value = formattedFallbackMinPredBG
                LogManager.shared.log(category: .deviceStatus, message: "Reason string not available, using fallback MinPredBG: \(formattedFallbackMinPredBG)", isDebug: true)
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
                storage.sharedCRValue.value = String(format: "%.1f", enactedCR)
            } else if let profileCR = profileCR {
                infoManager.updateInfoData(type: .carbRatio, value: profileCR, unit: "g/E")
                storage.sharedCRValue.value = String(format: "%.1f", profileCR)
            }

        // IOB
        if let iobMetric = InsulinMetric(from: lastLoopRecord["iob"], key: "iob") {
            // Klassisk Loop/OpenAPS-IOB (dvs över profilbasal)
            infoManager.updateInfoData(type: .iob, value: iobMetric, unit: "E")
            // Till kontakttrick och notiser
            latestIOB = iobMetric
            storage.sharedLatestIOB.value = String(format: "%.2f E", iobMetric.value)
            storage.sharedRawIOB.value = iobMetric.value

            // Beräkna teoretisk basal-IOB för nuvarande klockslag
            let profile = ProfileManager.shared
            let basalIOBNow = BasalIOBCalculator.basalIOBNow(from: profile.basalSchedule)

            // Total IOB = Basal IOB + Loop/OpenAPS IOB
            let loopIOBValue = iobMetric.value
            let totalIOBValue = loopIOBValue + basalIOBNow
            let totalIOBString = String(format: "%.2f", totalIOBValue)

            infoManager.updateInfoData(type: .totIob, value: totalIOBString, unit: "E")

            LogManager.shared.log(
                category: .deviceStatus,
                message: String(
                    format: "Total IOB updated: LoopIOB=%.2f, BasalIOB=%.2f, Total=%.2f",
                    loopIOBValue, basalIOBNow, totalIOBValue
                ),
                isDebug: true
            )
        }

            // COB
            if let cobMetric = CarbMetric(from: enactedOrSuggested, key: "COB") {
                infoManager.updateInfoData(type: .cob, value: cobMetric, unit: "g")
                // Till kontakttrick och notiser
                latestCOB = cobMetric
                storage.sharedLatestCOB.value = String(format: "%.0f g", cobMetric.value)
                storage.sharedRawCOB.value = cobMetric.value
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
                            LogManager.shared.log(category: .deviceStatus, message: "Failed to create CarbMetric from extracted COB value: \(cobValue)", isDebug: true)
                        }
                    } else {
                        LogManager.shared.log(category: .deviceStatus, message: "Invalid COB value extracted from reason string: \(cobValueString)", isDebug: true)
                    }
                } else {
                    LogManager.shared.log(category: .deviceStatus, message: "COB pattern not found in reason string.", isDebug: true)
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
                    //LogManager.shared.log(category: .deviceStatus, message: "Extracted BGI: \(bgiString)", isDebug: true)
                } else {
                    LogManager.shared.log(category: .deviceStatus, message: "Failed to convert BGI value to Double.", isDebug: true)
                }
            } else {
                LogManager.shared.log(category: .deviceStatus, message: "BGI pattern not found in reason string.", isDebug: true)
            }
        }
/*
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
                    //LogManager.shared.log(category: .deviceStatus, message: "Extracted Dev: \(devString)", isDebug: true)
                } else {
                    LogManager.shared.log(category: .deviceStatus, message: "Failed to convert Dev value to Double.", isDebug: true)
                }
            } else {
                LogManager.shared.log(category: .deviceStatus, message: "Dev pattern not found in reason string.", isDebug: true)
            }
        }
*/
        
        // Dev
        if let reasonString = enactedOrSuggested["reason"] as? String {

            // Lite robustare: tillåter flera siffror + decimals (och ev utan decimal)
            let pattern = #"Dev:\s*([-+]?\d+(?:\.\d+)?)"#

            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: reasonString,
                                            range: NSRange(location: 0, length: reasonString.utf16.count)) {

                let devValueString = (reasonString as NSString).substring(with: match.range(at: 1))

                if let devValue = Double(devValueString) {
                    let formattedDev = String(format: "%@%.1f", devValue > 0 ? "+" : "", devValue)

                    // 🟡 + priority när |dev| > 5.0 (byt till devValue > 5.0 om du bara menar positiva)
                    let isDevHigh = abs(devValue) > 5.0
                    let unitForInfo = isDevHigh ? "mmol/L 🟡" : "mmol/L"

                    infoManager.setPriority(isDevHigh, for: .dev)
                    infoManager.updateInfoData(type: .dev, value: formattedDev, unit: unitForInfo)

                    LogManager.shared.log(
                        category: .deviceStatus,
                        message: "Dev updated: value=\(formattedDev), priority=\(isDevHigh)",
                        isDebug: true
                    )
                } else {
                    infoManager.setPriority(false, for: .dev)
                    infoManager.updateInfoData(type: .dev, value: "--", unit: "mmol/L")

                    LogManager.shared.log(
                        category: .deviceStatus,
                        message: "Failed to convert Dev value '\(devValueString)' to Double. Using default --",
                        isDebug: true
                    )
                }

            } else {
                infoManager.setPriority(false, for: .dev)
                infoManager.updateInfoData(type: .dev, value: "0.0", unit: "mmol/L")

                LogManager.shared.log(
                    category: .deviceStatus,
                    message: "Dev pattern not found in reason string. Using default 0.0",
                    isDebug: true
                )
            }

        } else {
            infoManager.setPriority(false, for: .dev)
            infoManager.updateInfoData(type: .dev, value: "0.0", unit: "mmol/L")

            LogManager.shared.log(
                category: .deviceStatus,
                message: "Reason string missing. Dev not available, using default 0.0",
                isDebug: true
            )
        }
        // AF (Adjustment Factor)
        if let reasonString = enactedOrSuggested["reason"] as? String {
            let afPattern = "AF:\\s(\\d+\\.\\d{1,2})" // Matches "AF: x.x" or "AF: x.xx"
            
            if let afRegex = try? NSRegularExpression(pattern: afPattern),
               let afMatch = afRegex.firstMatch(in: reasonString, range: NSRange(location: 0, length: reasonString.utf16.count)) {
                
                let afValueString = (reasonString as NSString).substring(with: afMatch.range(at: 1))
                
                if let afValue = Double(afValueString) {
                    infoManager.updateInfoDataForAF(value: afValue)
                    //LogManager.shared.log(category: .deviceStatus, message: "Extracted AF: \(afValue)", isDebug: true)
                } else {
                    LogManager.shared.log(category: .deviceStatus, message: "Invalid AF value extracted from reason string: \(afValueString)", isDebug: true)
                }
            } else {
                LogManager.shared.log(category: .deviceStatus, message: "AF pattern not found in reason string.", isDebug: true)
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
                    //LogManager.shared.log(category: .deviceStatus, message: "Extracted SMB Ratio: \(smbRatioValue)", isDebug: true)
                } else {
                    LogManager.shared.log(category: .deviceStatus, message: "Invalid SMB Ratio value extracted from reason string: \(smbRatioValueString)", isDebug: true)
                    infoManager.updateInfoDataForSMBRatio(value: 0.50) // Default to 0.50 if parsing fails
                }
            } else {
                LogManager.shared.log(category: .deviceStatus, message: "SMB Ratio pattern not found in reason string. Using default value: 0.50", isDebug: true)
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
                    let formattedValue = String(format: "%.2f", maxSmbValue)  // e.g. "0.00" or "1.25"
                    // append 🚫 if zero
                    let unitForInfo = maxSmbValue == 0 ? "E 🚫" : "E 🔵"
                    
                    infoManager.updateInfoData(
                        type: .maxSMB,
                        value: formattedValue,
                        unit: unitForInfo
                    )
                    //LogManager.shared.log(category: .deviceStatus, message: "Extracted MaxSMB: \(formattedValue) \(unitForInfo)", isDebug: true)
                } else {
                    LogManager.shared.log(category: .deviceStatus, message: "Invalid MaxSMB value extracted: \(maxSmbValueString), defaulting to N/A", isDebug: true)
                    infoManager.updateInfoData(
                        type: .maxSMB,
                        value: "--",
                        unit: "E ⚫️"
                    )
                }
            } else {
                LogManager.shared.log(category: .deviceStatus, message: "MaxSMB pattern not found. Using default 0.00", isDebug: true)
                infoManager.updateInfoData(
                    type: .maxSMB,
                    value: "0.00",
                    unit: "E 🚫"
                )
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
                
                //LogManager.shared.log(category: .deviceStatus, message: "SMB Status Updated: \(smbStatusString)", isDebug: true)
            }
        }
        
        // Insulin Required
        if let insulinReqMetric = InsulinMetric(from: enactedOrSuggested, key: "insulinReq") {
            let unitForInfo = insulinReqMetric.value > 0 ? "E 🔵" : "E"
            if insulinReqMetric.value > 0 {
                infoManager.setPriority(true, for: .recBolus)
            }
            else {
                infoManager.setPriority(false, for: .recBolus)
            }
            infoManager.updateInfoData(type: .recBolus, value: insulinReqMetric, unit: unitForInfo)
            UserDefaultsRepository.deviceRecBolus.value = insulinReqMetric.value
            storage.sharedLatestInsulinReq.value = String(format: "%.2f E", insulinReqMetric.value)
            storage.sharedRawInsulinReq.value = insulinReqMetric.value
        } else {
            UserDefaultsRepository.deviceRecBolus.value = 0
            storage.sharedLatestInsulinReq.value = "0 E"
            storage.sharedRawInsulinReq.value = 0.0
            infoManager.setPriority(false, for: .recBolus)
        }
        
        // Daniel: Carbs Required
        if let carbsReq = enactedOrSuggested["carbsReq"] as? Double {
            let adjustedCarbs = carbsReq * 0.5                                   // 👈 multiplikation
            let latestCarbReq = String(format: "%.0f", adjustedCarbs)            // avrundat
            let unitForInfo = adjustedCarbs > 0 ? "g 🟡" : "g"
            if adjustedCarbs > 0 {
                infoManager.setPriority(true, for: .carbReq)
            }
            else {
                infoManager.setPriority(false, for: .carbReq)
            }

            infoManager.updateInfoData(type: .carbReq, value: latestCarbReq, unit: unitForInfo)
            storage.sharedLatestCarbReq.value = "\(latestCarbReq) g"
            storage.sharedRawCarbReq.value = adjustedCarbs

            LogManager.shared.log(
                category: .deviceStatus,
                message: "Carbs Required updated: original=\(carbsReq), adjusted=\(latestCarbReq)",
                isDebug: true
            )

        } else {
            let defaultCarbReq = "0"
            infoManager.updateInfoData(type: .carbReq, value: defaultCarbReq, unit: "g")
            infoManager.setPriority(false, for: .carbReq)
            storage.sharedLatestCarbReq.value = "0 g"
            storage.sharedRawCarbReq.value = 0.0

            LogManager.shared.log(
                category: .deviceStatus,
                message: "Carbs Required not available, using default: \(defaultCarbReq)",
                isDebug: true
            )
        }
        
        // Autosens
        if let sens = enactedOrSuggested["sensitivityRatio"] as? Double {
            let formattedSens = String(format: "%.0f", sens * 100.0) + " %"
            storage.sharedLatestSens.value = formattedSens

            var formattedSensLimit: String?

            if let reasonString = enactedOrSuggested["reason"] as? String {
                let sensLimitPattern = "Autosens limit: ([0-9]+(?:\\.[0-9]{1,2})?) \\(([0-9]+(?:\\.[0-9]{1,2})?)\\)"
                if let regex = try? NSRegularExpression(pattern: sensLimitPattern),
                   let match = regex.firstMatch(in: reasonString, range: NSRange(location: 0, length: reasonString.utf16.count)) {

                    let nsReasonString = reasonString as NSString
                    let xString = nsReasonString.substring(with: match.range(at: 1))
                    let yString = nsReasonString.substring(with: match.range(at: 2))

                    if let xValue = Double(xString), let yValue = Double(yString) {
                        formattedSensLimit = String(format: "%.0f% % ⇥ %.0f% %", yValue * 100.0, xValue * 100.0)
                    }
                }
            }

            if let formattedSensLimit = formattedSensLimit {
                infoManager.updateInfoData(type: .autosens, value: formattedSensLimit)
                //LogManager.shared.log(category: .deviceStatus, message: "Sensitivity Ratio (limit) updated: \(formattedSensLimit)", isDebug: true)
            } else {
                infoManager.updateInfoData(type: .autosens, value: formattedSens)
                //LogManager.shared.log(category: .deviceStatus, message: "Sensitivity Ratio updated: \(formattedSens)", isDebug: true)
            }
        } else {
            LogManager.shared.log(category: .deviceStatus, message: "Missing or invalid sensitivityRatio in enactedOrSuggested.", isDebug: true)
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
            storage.sharedRawEvBG.value = formattedBGString
            storage.sharedLatestEvBG.value = latestEvBG

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

            let profileTargetHighValue = profileTargetHigh.doubleValue(for: .millimolesPerLiter)
            let enactedTargetValue = enactedTarget.doubleValue(for: .millimolesPerLiter)

            // Compare using formatted strings to avoid floating-point issues
            if profileTargetHighFormatted != enactedTargetFormatted {
                infoManager.updateInfoData(
                    type: .target,
                    firstValue: profileTargetHigh,
                    secondValue: enactedTarget,
                    separator: .arrow,
                    unit: "mmol/L"
                )

                storage.sharedLatestTarget.value = enactedTargetValue
            } else {
                infoManager.updateInfoData(
                    type: .target,
                    value: profileTargetHigh,
                    unit: "mmol/L"
                )

                storage.sharedLatestTarget.value = profileTargetHighValue
            }
        } else if let profileTargetHigh = profileTargetHigh {
            let profileTargetHighValue = profileTargetHigh.doubleValue(for: .millimolesPerLiter)

            infoManager.updateInfoData(
                type: .target,
                value: profileTargetHigh,
                unit: "mmol/L"
            )

            storage.sharedLatestTarget.value = profileTargetHighValue
        }

            // TDD
            if let tddMetric = InsulinMetric(from: enactedOrSuggested, key: "TDD") {
                infoManager.updateInfoData(type: .tdd, value: tddMetric, unit: "E")
            }
        
        let predictioncolor = UIColor.systemGray
        PredictionLabel.textColor = predictioncolor
        topPredictionBG = UserDefaultsRepository.minBGScale.value
        
        if let predbgdata = enactedOrSuggested["predBGs"] as? [String: AnyObject] {
            // Lägg till en flagga includeInMinMax
            let predictionTypes: [(type: String, colorName: String, dataIndex: Int, includeInMinMax: Bool)] = [
                ("ZT",  "ZT",        12, true),
                ("IOB", "Insulin",   13, true), // ⬅️ EXKLUDERA från min/max om du sätter "false"
                ("COB", "LoopYellow",14, true),
                ("UAM", "UAM",       15, true)
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
                    LogManager.shared.log(
                        category: .deviceStatus,
                        message: "❌ Failed to parse deliverAt: \(deliverAtString), falling back to alertLastLoopTime: \(basePredictionTime)",
                        isDebug: true
                    )
                }
            } else {
                LogManager.shared.log(
                    category: .deviceStatus,
                    message: "⚠️ No deliverAt found in enactedOrSuggested, using alertLastLoopTime: \(basePredictionTime)",
                    isDebug: true
                )
            }
            
            for (type, colorName, dataIndex, includeInMinMax) in predictionTypes {
                var predictionData = [ShareGlucoseData]()
                
                // Reset predictionTime for each dataset so they all start at the same time
                var predictionTime = basePredictionTime
                
                if let graphdata = predbgdata[type] as? [Double] {
                    let toLoad = Int(UserDefaultsRepository.predictionToLoad.value * 12)
                    
                    //print("📊 Processing prediction type: \(type), data count: \(graphdata.count), starting at \(predictionTime)")
                    
                    for i in 0...toLoad {
                        if i < graphdata.count {
                            let predictionValue = graphdata[i]
                            
                            // ⬅️ Uppdatera min/max bara om denna kurva ska räknas med
                            if includeInMinMax {
                                minPredBG = min(minPredBG, predictionValue)
                                maxPredBG = max(maxPredBG, predictionValue)
                            }
                            
                            let prediction = ShareGlucoseData(
                                sgv: Int(round(predictionValue)),
                                date: predictionTime,
                                direction: "flat"
                            )
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
                storage.sharedLatestMinMax.value = "\(value) mmol/L"
            } else {
                infoManager.updateInfoData(type: .minMax, value: "--", unit: "mmol/L")
                storage.sharedLatestMinMax.value = "--"
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
