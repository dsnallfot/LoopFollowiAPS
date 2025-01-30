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
                let isfInMmol = enactedISFValue * 0.0555 // Conversion factor
                let isfUnit = "mmol/L"
                sharedLatestISF = String(format: "%.1f %@", isfInMmol, isfUnit)

                var determinedISFUnit: HKUnit = .milligramsPerDeciliter
                if enactedISFValue < 25 {
                    determinedISFUnit = .millimolesPerLiter
                }
                enactedISF = HKQuantity(unit: determinedISFUnit, doubleValue: enactedISFValue)
            }
            if let profileISF = profileISF, let enactedISF = enactedISF, profileISF != enactedISF {
                infoManager.updateInfoData(type: .isf, firstValue: profileISF, secondValue: enactedISF, separator: .arrow, unit: "mmol/L/E")
            } else if let profileISF = profileISF {
                infoManager.updateInfoData(type: .isf, value: profileISF, unit: "mmol/L/E")
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
                sharedLatestCOB = String(format: "%.0f E", latestCOB?.value ?? 0)
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

            // Insulin Required
            if let insulinReqMetric = InsulinMetric(from: enactedOrSuggested, key: "insulinReq") {
                infoManager.updateInfoData(type: .recBolus, value: insulinReqMetric, unit: "E")
                UserDefaultsRepository.deviceRecBolus.value = insulinReqMetric.value
                sharedLatestInsulinReq = String(format: "%.2f E", insulinReqMetric.value)
            } else {
                UserDefaultsRepository.deviceRecBolus.value = 0
                sharedLatestInsulinReq = "0 E"
            }
            
            // Daniel: Carbs Required for later use
            if let carbsReq = enactedOrSuggested["carbsReq"] as? Double {
                let latestCarbReq = String(format: "%.0f g", carbsReq)
                sharedLatestCarbReq = latestCarbReq
                infoManager.updateInfoData(type: .carbReq, value: latestCarbReq)
                print("Carbs Required updated: \(latestCarbReq)")
            } else {
                let defaultCarbReq = "0 g"
                sharedLatestCarbReq = defaultCarbReq
                infoManager.updateInfoData(type: .carbReq, value: defaultCarbReq)
                print("Carbs Required not available, using default: \(defaultCarbReq)")
            }

            // Autosens
            if let sens = enactedOrSuggested["sensitivityRatio"] as? Double {
                let formattedSens = String(format: "%.0f", sens * 100.0) + " %"
                sharedLatestSens = formattedSens
                infoManager.updateInfoData(type: .autosens, value: formattedSens)
                print("Sensitivity Ratio updated: \(formattedSens)")
            } else {
                print("Missing or invalid sensitivityRatio in enactedOrSuggested.")
            }

            
            var predictionColor = UIColor.systemGray

            // Eventual BG Handling
            if let eventualBGValue = enactedOrSuggested["eventualBG"] as? Double,
               let loopYellow = UIColor(named: "LoopYellow"),
               let loopRed = UIColor(named: "LoopRed"),
               let loopGreen = UIColor(named: "LoopGreen") {

                // Convert eventualBGValue to necessary formats
                let eventualBGFloatValue = Float(eventualBGValue) // Convert Double to Float for compatibility
                let eventualBGStringValue = String(describing: eventualBGValue) // Convert to String
                let formattedBGString = Localizer.toDisplayUnits(eventualBGStringValue).replacingOccurrences(of: ",", with: ".") // Format for display

                // Update visualization for remote meal info popup
                latestEvBG = formattedBGString + " mmol/L"
                sharedRawEvBG = formattedBGString
                sharedLatestEvBG = latestEvBG

                // Update PredictionLabel with color based on eventualBG value
                if ((TimeInterval(Date().timeIntervalSince1970) - lastLoopTime) / 60) > 16 {
                    PredictionLabel.text = "  ❌  Loop ej aktiv!"
                    predictionColor = UIColor.systemRed
                    
                } else if eventualBGFloatValue >= UserDefaultsRepository.highLine.value {
                    if UserDefaultsRepository.colorBGText.value {
                        PredictionLabel.text = "    Prognos ⇢ \(formattedBGString)"
                        predictionColor = UIColor.systemPurple
                    } else {
                        PredictionLabel.text = "    Prognos ⇢ \(formattedBGString)"
                        predictionColor = loopYellow
                    }
                } else if eventualBGFloatValue <= UserDefaultsRepository.lowLine.value {
                    PredictionLabel.text = "    Prognos ⇢ \(formattedBGString)"
                    predictionColor = loopRed
                    
                } else if eventualBGFloatValue > UserDefaultsRepository.lowLine.value && eventualBGFloatValue < UserDefaultsRepository.highLine.value {
                    PredictionLabel.text = "    Prognos ⇢ \(formattedBGString)"
                    predictionColor = loopGreen
                }
            }

            // Ensure the color is updated on the main thread
            DispatchQueue.main.async {
                //print("Setting PredictionLabel color to \(predictionColor)")
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

                for (type, colorName, dataIndex) in predictionTypes {
                    var predictionData = [ShareGlucoseData]()
                    if let graphdata = predbgdata[type] as? [Double] {
                        var predictionTime = UserDefaultsRepository.alertLastLoopTime.value
                        let toLoad = Int(UserDefaultsRepository.predictionToLoad.value * 12)

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
                    let value = "\(Localizer.toDisplayUnits(String(minPredBG))) / \(Localizer.toDisplayUnits(String(maxPredBG)))"
                    infoManager.updateInfoData(type: .minMax, value: value, unit: "mmol/L")
                    sharedLatestMinMax = value
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
