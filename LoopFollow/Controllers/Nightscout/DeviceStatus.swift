//
//  DeviceStatus.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2023-10-05.
//  Copyright © 2023 Jon Fawcett. All rights reserved.
//

import Foundation
import UIKit

var sharedCRValue: String = ""
var sharedLatestIOB: String = ""
var sharedLatestCOB: String = ""
var sharedLatestISF: String = ""
var sharedLatestSens: String = ""
var sharedLatestCarbReq: String = ""
var sharedLatestInsulinReq: String = ""
var sharedLatestMinMax: String = ""
var sharedLatestEvBG: String = ""
var sharedMinGuardBG: Double = 0.0
//var sharedInsulinReq: Double = 0.0
var sharedLastSMBUnits: Double = 0.0

extension MainViewController {
    // NS Device Status Web Call
    func webLoadNSDeviceStatus() {
        if UserDefaultsRepository.debugLog.value {
            self.writeDebugLog(value: "Download: device status")
        }
        
        let parameters: [String: String] = ["count": "288"]
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
    
    func mgdlToMmol(_ mgdl: Double) -> Double {
        return mgdl * 0.05551
    }
    
    private func handleDeviceStatusError() {
        if globalVariables.nsVerifiedAlert < dateTimeUtils.getNowTimeIntervalUTC() + 300 {
            globalVariables.nsVerifiedAlert = dateTimeUtils.getNowTimeIntervalUTC()
            //self.sendNotification(title: "Nightscout Error", body: "Please double check url, token, and internet connection. This may also indicate a temporary Nightscout issue")
        }
        DispatchQueue.main.async {
            if self.deviceStatusTimer.isValid {
                self.deviceStatusTimer.invalidate()
            }
            self.startDeviceStatusTimer(time: 10)
        }
    }
    
    func evaluateNotLooping(lastLoopTime: TimeInterval) {
        if let statusStackView = LoopStatusLabel.superview as? UIStackView {
            if ((TimeInterval(Date().timeIntervalSince1970) - lastLoopTime) / 60) > 15 {
                IsNotLooping = true
                /*
                 // Change the distribution to 'fill' to allow manual resizing of arranged subviews
                 statusStackView.distribution = .fill
                 
                 // Hide PredictionLabel and expand LoopStatusLabel to fill the entire stack view
                 PredictionLabel.isHidden = true
                 LoopStatusLabel.frame = CGRect(x: 0, y: 0, width: statusStackView.frame.width, height: statusStackView.frame.height)
                 
                 // Update LoopStatusLabel's properties to display Not Looping
                 LoopStatusLabel.textAlignment = .right
                 LoopStatusLabel.text = "⚠️"
                 LoopStatusLabel.textColor = UIColor.systemYellow
                 LoopStatusLabel.font = UIFont.systemFont(ofSize: 17)
                 */
                
            } else {
                IsNotLooping = false
                /*
                 // Restore the original distribution and visibility of labels
                 statusStackView.distribution = .fillEqually
                 PredictionLabel.isHidden = false
                 
                 // Reset LoopStatusLabel's properties
                 LoopStatusLabel.textAlignment = .right
                 LoopStatusLabel.font = UIFont.systemFont(ofSize: 17)
                 
                 if UserDefaultsRepository.forceDarkMode.value {
                 LoopStatusLabel.textColor = UIColor.white
                 } else {
                 LoopStatusLabel.textColor = UIColor.black
                 }*/
            }
        }
        latestLoopTime = lastLoopTime
    }
    
    // NS Device Status Response Processor
    func updateDeviceStatusDisplay(jsonDeviceStatus: [[String:AnyObject]]) {
        self.clearLastInfoData(index: 0)
        self.clearLastInfoData(index: 1)
        self.clearLastInfoData(index: 3)
        self.clearLastInfoData(index: 4)
        self.clearLastInfoData(index: 5)
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Process: device status") }
        if jsonDeviceStatus.count == 0 {
            return
        }
        
        //Process the current data first
        let lastDeviceStatus = jsonDeviceStatus[0] as [String : AnyObject]?
        
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
                    tableData[5].value = String(format:"%.0f", reservoirData) + " E"
                } else {
                    latestPumpVolume = 50.0
                    tableData[5].value = "50+E"
                }
                
                if let uploader = lastDeviceStatus?["uploader"] as? [String:AnyObject] {
                    let upbat = uploader["battery"] as! Double
                    tableData[4].value = String(format:"%.0f", upbat) + " %"
                    UserDefaultsRepository.deviceBatteryLevel.value = upbat
                }
            }
        }
        
        // Loop
        if let lastLoopRecord = lastDeviceStatus?["loop"] as! [String : AnyObject]? {
            //print("Loop: \(lastLoopRecord)")
            if let lastLoopTime = formatter.date(from: (lastLoopRecord["timestamp"] as! String))?.timeIntervalSince1970  {
                UserDefaultsRepository.alertLastLoopTime.value = lastLoopTime
                if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "lastLoopTime: " + String(lastLoopTime)) }
                if let failure = lastLoopRecord["failureReason"] {
                    LoopStatusLabel.text = " X"
                    latestLoopStatusString = "X"
                    if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Loop Failure: X") }
                } else {
                    var wasEnacted = false
                    if let enacted = lastLoopRecord["enacted"] as? [String:AnyObject] {
                        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Loop: Was Enacted") }
                        wasEnacted = true
                        if let lastTempBasal = enacted["rate"] as? Double {
                            
                        }
                    }
                    if let iobdata = lastLoopRecord["iob"] as? [String:AnyObject] {
                        tableData[0].value = String(format:"%.2f", (iobdata["iob"] as! Double)) + " E"
                        latestIOB = String(format:"%.2f", (iobdata["iob"] as! Double))
                    }
                    if let cobdata = lastLoopRecord["cob"] as? [String:AnyObject] {
                        tableData[1].value = String(format:"%.0f", cobdata["cob"] as! Double) + " g"
                        latestCOB = String(format:"%.0f", cobdata["cob"] as! Double)
                    }
                    if let predictdata = lastLoopRecord["predicted"] as? [String:AnyObject] {
                        let prediction = predictdata["values"] as! [Double]
                        PredictionLabel.text = bgUnits.toDisplayUnits(String(Int(prediction.last!)))
                        PredictionLabel.textColor = UIColor.systemPurple
                        if UserDefaultsRepository.downloadPrediction.value && latestLoopTime < lastLoopTime {
                            predictionData.removeAll()
                            var predictionTime = lastLoopTime
                            let toLoad = Int(UserDefaultsRepository.predictionToLoad.value * 12)
                            var i = 0
                            while i <= toLoad {
                                if i < prediction.count {
                                    let sgvValue = Int(round(prediction[i]))
                                    // Skip values higher than 600
                                    if sgvValue <= 600 {
                                        let prediction = ShareGlucoseData(sgv: sgvValue, date: predictionTime, direction: "flat")
                                        predictionData.append(prediction)
                                    }
                                    predictionTime += 300
                                }
                                i += 1
                            }
                            
                            let predMin = prediction.min()
                            let predMax = prediction.max()
                            tableData[9].value = bgUnits.toDisplayUnits(String(predMin!)) + "-" + bgUnits.toDisplayUnits(String(predMax!)) + " mmol/L"
                            
                            updatePredictionGraph()
                        }
                    }
                    if let recBolus = lastLoopRecord["recommendedBolus"] as? Double {
                        tableData[8].value = String(format:"%.2f", recBolus) + " E"
                        UserDefaultsRepository.deviceRecBolus.value = recBolus
                    }
                    if let loopStatus = lastLoopRecord["recommendedTempBasal"] as? [String:AnyObject] {
                        if let tempBasalTime = formatter.date(from: (loopStatus["timestamp"] as! String))?.timeIntervalSince1970 {
                            var lastBGTime = lastLoopTime
                            if bgData.count > 0 {
                                lastBGTime = bgData[bgData.count - 1].date
                            }
                            if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "tempBasalTime: " + String(tempBasalTime)) }
                            if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "lastBGTime: " + String(lastBGTime)) }
                            if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "wasEnacted: " + String(wasEnacted)) }
                            if tempBasalTime > lastBGTime && !wasEnacted {
                                LoopStatusLabel.text = " ⏀"
                                latestLoopStatusString = "⏀"
                                if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Open Loop: recommended temp. temp time > bg time, was not enacted") }
                            } else {
                                LoopStatusLabel.text = " ↻"
                                latestLoopStatusString = "↻"
                                if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Looping: recommended temp, but temp time is < bg time and/or was enacted") }
                            }
                        }
                    } else {
                        LoopStatusLabel.text = " ↻"
                        latestLoopStatusString = "↻"
                        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Looping: no recommended temp") }
                    }
                    
                }
                
                evaluateNotLooping(lastLoopTime: lastLoopTime)
            } // end lastLoopTime
        } // end lastLoop Record
        
        if let lastLoopRecord = lastDeviceStatus?["openaps"] as! [String : AnyObject]? {
            if let lastLoopTime = formatter.date(from: (lastDeviceStatus?["created_at"] as! String))?.timeIntervalSince1970  {
                UserDefaultsRepository.alertLastLoopTime.value = lastLoopTime
                if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "lastLoopTime: " + String(lastLoopTime)) }
                if let failure = lastLoopRecord["failureReason"] {
                    LoopStatusLabel.text = " X"
                    latestLoopStatusString = "X"
                    if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Loop Failure: X") }
                } else {
                    var wasEnacted = false
                    if let enacted = lastLoopRecord["enacted"] as? [String:AnyObject] {
                        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Loop: Was Enacted") }
                        wasEnacted = true
                        if let lastTempBasal = enacted["rate"] as? Double {
                            // Handle lastTempBasal if needed
                        }
                    }

                    if let iobdata = lastLoopRecord["iob"] as? [String:AnyObject] {
                        if let iob = iobdata["iob"] as? Double {
                            tableData[0].value = String(format:"%.2f", iob) + " E"
                            //Daniel: Added for visualization in remote meal info popup
                            latestIOB = String(format:"%.2f", iob) + " E"
                            sharedLatestIOB = latestIOB
                        }
                    }
                    
                    //Daniel: Use suggested instead of enacted to populate infotable even when not enacted
                    if let suggestedData = lastLoopRecord["suggested"] as? [String:AnyObject] {
                        if let COB = suggestedData["COB"] as? Double {
                            tableData[1].value = String(format:"%.0f", COB) + " g"
                            //Daniel: Added for visualization in remote meal info popup
                            latestCOB = String(format:"%.0f", COB) + " g"
                            sharedLatestCOB = latestCOB
                        }

                        //if let recbolusdata = lastLoopRecord["suggested"] as? [String: AnyObject],
                        if let insulinReq = suggestedData["insulinReq"] as? Double {
                            tableData[8].value = String(format: "%.2f", insulinReq) + " E"
                            UserDefaultsRepository.deviceRecBolus.value = insulinReq
                            //Daniel: Added for visualization in remote meal info popup
                            latestInsulinReq = String(format:"%.2f", insulinReq) + " E"
                            sharedLatestInsulinReq = latestInsulinReq
                        } else {
                            tableData[8].value = "---"
                            UserDefaultsRepository.deviceRecBolus.value = 0
                            print("Warning: Failed to extract insulinReq from recbolusdata.")
                            //Daniel: Added for visualization in remote meal info popup
                            latestInsulinReq = "---"
                            sharedLatestInsulinReq = latestInsulinReq
                        }
                        
                        if let sensitivityRatio = suggestedData["sensitivityRatio"] as? Double {
                            let sens = sensitivityRatio * 100.0
                            tableData[11].value = String(format:"%.0f", sens) + " %"
                            //Daniel: Added for visualization in remote meal info popup
                            latestSens = String(format:"%.0f", sens) + " %"
                            sharedLatestSens = latestSens
                        }
                        
                        if let TDD = suggestedData["TDD"] as? Double {
                            tableData[13].value = String(format:"%.1f", TDD) + " E"
                        }
                        
                        if let ISF = suggestedData["ISF"] as? Double {
                            tableData[14].value = String(format:"%.1f", ISF) + " mmol/L/E"
                            //Daniel: Added for visualization in remote meal info popup
                            latestISF = String(format:"%.1f", ISF) + " mmol/L/E"
                            sharedLatestISF = latestISF
                        }
                        
                        if let CR = suggestedData["CR"] as? Double {
                            tableData[15].value = String(format:"%.1f", CR) + " g/E"
                            sharedCRValue = String(format:"%.1f", CR)
                        }
                        
                        if let currentTargetMgdl = suggestedData["current_target"] as? Double {
                            let currentTargetMmol = mgdlToMmol(currentTargetMgdl)
                            tableData[16].value = String(format: "%.1f", currentTargetMmol) + " mmol/L"
                        }
                        
                        if let carbsReq = suggestedData["carbsReq"] as? Double {
                            tableData[17].value = String(format:"%.0f", carbsReq) + " g"
                            //Daniel: Added for visualization in remote meal info popup
                            latestCarbReq = String(format:"%.0f", carbsReq) + " g"
                            sharedLatestCarbReq = latestCarbReq
                            
                        } else {
                            // If "carbsReq" is not present in suggestedData, set it to 0
                            tableData[17].value = "0 g"
                            //Daniel: Added for visualization in remote meal info popup
                            latestCarbReq = "0 g"
                            sharedLatestCarbReq = latestCarbReq
                        }
                        
                        if let timestampString = suggestedData["timestamp"] as? String {
                            // Assuming "timestamp" format is "2024-05-10T18:12:37.138Z"
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                            dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
                            
                            if let timestamp = dateFormatter.date(from: timestampString) {
                                // Now you have the timestamp as a Date object, convert it to the local timezone
                                let localTimeFormatter = DateFormatter()
                                localTimeFormatter.dateFormat = "HH:mm:ss"
                                localTimeFormatter.timeZone = TimeZone.autoupdatingCurrent
                                
                                let formattedLocalTime = localTimeFormatter.string(from: timestamp)
                                
                                // Set the formattedLocalTime to tableData[18].value
                                tableData[18].value = formattedLocalTime
                            } else {
                                // Handle the case where conversion from string to Date fails
                                print("Failed to convert timestamp string to Date.")
                            }
                        } else {
                            // Handle the case where "timestamp" key doesn't exist or its value is not a string
                            print("Timestamp value not found or not a string.")
                        }
                        
                        //Daniel: Added suggested data for bolus calculator and info
                        if let minGuardBG = suggestedData["minGuardBG"] as? Double {
                            let formattedMinGuardBGString = mgdlToMmol(minGuardBG)
                            sharedMinGuardBG = Double(formattedMinGuardBGString)
                        } else {
                            let formattedLowLine = mgdlToMmol(Double(UserDefaultsRepository.lowLine.value))
                            sharedMinGuardBG = Double(formattedLowLine)
                        }
                        
                        /*if let insulinReq = suggestedData["insulinReq"] as? Double {
                            let formattedInsulinReqString = String(format:"%.2f", insulinReq)
                            sharedInsulinReq = Double(formattedInsulinReqString) ?? 0
                        } else {
                            sharedInsulinReq = 0
                        }*/
                        
                        if let LastSMBUnits = suggestedData["units"] as? Double {
                            let formattedLastSMBUnitsString = String(format:"%.2f", LastSMBUnits)
                            sharedLastSMBUnits = Double(formattedLastSMBUnitsString) ?? 0
                        } else {
                            sharedLastSMBUnits = 0
                        }
                        
                    } else {
                        // If suggestedData is nil, set all tableData values to "Waiting"
                        for i in 1..<tableData.count {
                            tableData[i].value = "---"
                        }
                        
                    }
                    
                    //Auggie - override name
                    let recentOverride = overrideGraphData.last
                    let overrideName: String?
                    if let notes = recentOverride?.notes, !notes.isEmpty {
                        overrideName = notes
                    } else {
                        overrideName = recentOverride?.reason
                    }
                    let recentEnd: TimeInterval = recentOverride?.endDate ?? 0
                    let now = dateTimeUtils.getNowTimeIntervalUTC()
                    if recentEnd >= now {
                        tableData[3].value = String(overrideName ?? "Normal profil")
                    } else {
                        tableData[3].value = "Normal profil"
                    }
                    
                    // Include all values from all predBG types to be able to show min-max values
                    var graphtype = ""
                    var graphdata: [Double] = []
                    
                    if let enactdata = lastLoopRecord["suggested"] as? [String: AnyObject],
                       let predbgdata = enactdata["predBGs"] as? [String: [Double]] {
                        
                        let availableTypes = ["COB", "UAM", "IOB", "ZT"]
                        for type in availableTypes {
                            if let data = predbgdata[type] {
                                graphtype = type
                                graphdata += data // Merging all available values into one array to be able to present predmin-predmax based an all prediction values
                            }
                        }
                        
                        if UserDefaultsRepository.downloadPrediction.value && latestLoopTime < lastLoopTime {
                            predictionData.removeAll()
                            var predictionTime = lastLoopTime
                            let toLoad = Int(UserDefaultsRepository.predictionToLoad.value * 12)
                            var i = 0
                            while i <= toLoad {
                                if i < graphdata.count {
                                    let prediction = ShareGlucoseData(sgv: Int(round(graphdata[i])), date: predictionTime, direction: "flat")
                                    predictionData.append(prediction)
                                    predictionTime += 300
                                }
                                i += 1
                            }
                                                       
                            // Daniel: Collect predbgdata per type to create prediction charts COB, UAM, IOB, ZT
                            if let graphdataCOB = predbgdata["COB"] {
                                predictionDataCOB.removeAll()
                                var predictionTimeCOB = lastLoopTime
                                let toLoad = Int(UserDefaultsRepository.predictionToLoad.value * 12)
                                var i = 0
                                while i <= toLoad {
                                    if i < graphdataCOB.count {
                                        let predictionCOB = ShareGlucoseData(sgv: Int(round(graphdataCOB[i])), date: predictionTimeCOB, direction: "flat")
                                        predictionDataCOB.append(predictionCOB)
                                        predictionTimeCOB += 300
                                    }
                                    i += 1
                                }
                            } else {
                                predictionDataCOB.removeAll()
                                print("No COB prediction found")
                            }
                            updatePredictionGraphCOB(color: UIColor(named: "LoopYellow"))
                            
                            if let graphdataUAM = predbgdata["UAM"] {
                                predictionDataUAM.removeAll()
                                var predictionTimeUAM = lastLoopTime
                                let toLoad = Int(UserDefaultsRepository.predictionToLoad.value * 12)
                                var i = 0
                                while i <= toLoad {
                                    if i < graphdataUAM.count {
                                        let predictionUAM = ShareGlucoseData(sgv: Int(round(graphdataUAM[i])), date: predictionTimeUAM, direction: "flat")
                                        predictionDataUAM.append(predictionUAM)
                                        predictionTimeUAM += 300
                                    }
                                    i += 1
                                }
                            } else {
                                predictionDataUAM.removeAll()
                                print("No UAM prediction found")
                            }
                            updatePredictionGraphUAM(color: UIColor(named: "UAM"))
                            
                            if let graphdataIOB = predbgdata["IOB"] {
                                predictionDataIOB.removeAll()
                                var predictionTimeIOB = lastLoopTime
                                let toLoad = Int(UserDefaultsRepository.predictionToLoad.value * 12)
                                var i = 0
                                while i <= toLoad {
                                    if i < graphdataIOB.count {
                                        let predictionIOB = ShareGlucoseData(sgv: Int(round(graphdataIOB[i])), date: predictionTimeIOB, direction: "flat")
                                        predictionDataIOB.append(predictionIOB)
                                        predictionTimeIOB += 300
                                    }
                                    i += 1
                                }
                            } else {
                                predictionDataIOB.removeAll()
                                print("No IOB prediction found")
                            }
                            updatePredictionGraphIOB(color: UIColor(named: "Insulin"))
                            
                            if let graphdataZT = predbgdata["ZT"] {
                                predictionDataZT.removeAll()
                                var predictionTimeZT = lastLoopTime
                                let toLoad = Int(UserDefaultsRepository.predictionToLoad.value * 12)
                                var i = 0
                                while i <= toLoad {
                                    if i < graphdataZT.count {
                                        let predictionZT = ShareGlucoseData(sgv: Int(round(graphdataZT[i])), date: predictionTimeZT, direction: "flat")
                                        predictionDataZT.append(predictionZT)
                                        predictionTimeZT += 300
                                    }
                                    i += 1
                                }
                            } else {
                                predictionDataZT.removeAll()
                                print("No ZT prediction found")
                            }
                            updatePredictionGraphZT(color: UIColor(named: "ZT"))
                            
                        }
                        
                        var predictionColor = UIColor.systemGray

                        if let eventualData = lastLoopRecord["suggested"] as? [String: Any],
                            let eventualBGValue = eventualData["eventualBG"] as? NSNumber,
                            let loopYellow = UIColor(named: "LoopYellow"),
                            let loopRed = UIColor(named: "LoopRed"),
                            let loopGreen = UIColor(named: "LoopGreen") {
                                
                            let eventualBGFloatValue = eventualBGValue.floatValue // Convert NSNumber to Float
                            
                            let eventualBGStringValue = String(describing: eventualBGValue)
                            let formattedBGString = bgUnits.toDisplayUnits(eventualBGStringValue).replacingOccurrences(of: ",", with: ".")
                            //Daniel: Added for visualization in remote meal info popup
                            latestEvBG = formattedBGString + " mmol/L"
                            sharedLatestEvBG = latestEvBG
                            
                            
                            if eventualBGFloatValue >= UserDefaultsRepository.highLine.value {
                                PredictionLabel.text = "    Prognos ⇢ \(formattedBGString)"
                                PredictionLabel.textColor = loopYellow
                                predictionColor = loopYellow
                            } else if eventualBGFloatValue <= UserDefaultsRepository.lowLine.value {
                                PredictionLabel.text = "    Prognos ⇢ \(formattedBGString)"
                                PredictionLabel.textColor = loopRed
                                predictionColor = loopRed
                            } else if eventualBGFloatValue > UserDefaultsRepository.lowLine.value && eventualBGFloatValue < UserDefaultsRepository.highLine.value {
                                PredictionLabel.text = "    Prognos ⇢ \(formattedBGString)"
                                PredictionLabel.textColor = loopGreen
                                predictionColor = loopGreen
                            }
                        }

                        // Update PredictionLabel with the new color
                        PredictionLabel.textColor = predictionColor
                
                        if let predMin = graphdata.min(), let predMax = graphdata.max() {
                            let formattedPredMin = bgUnits.toDisplayUnits(String(predMin)).replacingOccurrences(of: ",", with: ".")
                            let formattedPredMax = bgUnits.toDisplayUnits(String(predMax)).replacingOccurrences(of: ",", with: ".")
                            tableData[9].value = "\(formattedPredMin)-\(formattedPredMax) mmol/L"
                            //updatePredictionGraph(color: predictioncolor)
                            //Daniel: Added for visualization in remote meal info popup
                            latestMinMax = "\(formattedPredMin)-\(formattedPredMax) mmol/L"
                            sharedLatestMinMax = latestMinMax
                        } else {
                            tableData[9].value = "N/A"
                            //Daniel: Added for visualization in remote meal info popup
                            latestMinMax = "N/A"
                            sharedLatestMinMax = latestMinMax
                        }
                    }
                    
                    if let loopStatus = lastLoopRecord["recommendedTempBasal"] as? [String:AnyObject] {
                        if let tempBasalTime = formatter.date(from: (loopStatus["timestamp"] as! String))?.timeIntervalSince1970 {
                            var lastBGTime = lastLoopTime
                            if bgData.count > 0 {
                                lastBGTime = bgData[bgData.count - 1].date
                            }
                            if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "tempBasalTime: " + String(tempBasalTime)) }
                            if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "lastBGTime: " + String(lastBGTime)) }
                            if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "wasEnacted: " + String(wasEnacted)) }
                            if tempBasalTime > lastBGTime && !wasEnacted {
                                LoopStatusLabel.text = " ⏀"
                                latestLoopStatusString = "⏀"
                                if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Open Loop: recommended temp. temp time > bg time, was not enacted") }
                            } else {
                                LoopStatusLabel.text = " ᮰"
                                latestLoopStatusString = "᮰"
                                if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Looping: recommended temp, but temp time is < bg time and/or was enacted") }
                            }
                        }
                    } else if let enacted = lastLoopRecord["enacted"] as? [String: AnyObject],
                              let received = enacted["recieved"] as? Bool, !received {
                        // Daniel: If "recieved" is false, it means there's a failure. received is misspelled as recieved in iAPS upload to NS Device status
                        LoopStatusLabel.text = " ᮰"
                        LoopStatusLabel.textColor = UIColor(named: "LoopYellow")
                        latestLoopStatusString = "᮰"
                        if UserDefaultsRepository.debugLog.value {
                            self.writeDebugLog(value: "iAPS Not Enacted: X")
                        }
                    } else {
                        LoopStatusLabel.text = " ᮰"
                        LoopStatusLabel.textColor = UIColor(named: "LoopGreen")
                        latestLoopStatusString = "᮰"
                        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Looping: no recommended temp") }
                        print("Looping: no recommended temp")
                    }
                    
                }
                if ((TimeInterval(Date().timeIntervalSince1970) - lastLoopTime) / 60) > 15 {
                    LoopStatusLabel.text = " ᮰"
                    LoopStatusLabel.textColor = UIColor(named: "LoopRed")
                    latestLoopStatusString = "᮰"

                }
                latestLoopTime = lastLoopTime
                
                evaluateNotLooping(lastLoopTime: lastLoopTime)
            }
        }
        
        infoTable.reloadData()
        
        // Start the timer based on the timestamp
        let now = dateTimeUtils.getNowTimeIntervalUTC()
        let secondsAgo = now - latestLoopTime
        
        DispatchQueue.main.async {
            // if Loop is overdue over: 20:00, re-attempt every 5 minutes
            if secondsAgo >= (20 * 60) {
                self.startDeviceStatusTimer(time: (5 * 60))
                print("started 5 minute device status timer")
                
                // if the Loop is overdue: 10:00-19:59, re-attempt every minute
            } else if secondsAgo >= (10 * 60) {
                self.startDeviceStatusTimer(time: 60)
                print("started 1 minute device status timer")
                
                // if the Loop is overdue: 7:00-9:59, re-attempt every 30 seconds
            } else if secondsAgo >= (7 * 60) {
                self.startDeviceStatusTimer(time: 30)
                print("started 30 second device status timer")
                
                // if the Loop is overdue: 5:00-6:59 re-attempt every 10 seconds
            } else if secondsAgo >= (5 * 60) {
                self.startDeviceStatusTimer(time: 10)
                print("started 10 second device status timer")
                
                // We have a current Loop. Set timer to 5:10 from last reading
            } else {
                self.startDeviceStatusTimer(time: 310 - secondsAgo)
                let timerVal = 310 - secondsAgo
                print("started 5:10 device status timer: \(timerVal)")
            }
        }
    }
}
