//
//  BGData.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2023-10-05.
//  Copyright © 2023 Jon Fawcett. All rights reserved.
//

import Foundation
import UIKit

var sharedLatestBG: String = ""
var sharedLatestDirection: String = ""
var sharedLatestDelta: String = ""

extension MainViewController {
    // Dex Share Web Call
    func webLoadDexShare() {
        // Dexcom Share only returns 24 hrs of data as of now
        // Requesting more just for consistency with NS
        let graphHours = 24 * UserDefaultsRepository.downloadDays.value
        let count = graphHours * 12
        dexShare?.fetchData(count) { (err, result) -> () in
            
            if let error = err {
                LogManager.shared.log(category: .dexcom, message: "Error fetching Dexcom data: \(error.localizedDescription)")
                self.webLoadNSBGData()
                return
            }
            
            guard let data = result else {
                LogManager.shared.log(category: .dexcom, message: "Received nil data from Dexcom")
                self.webLoadNSBGData()
                return
            }
            
            // If Dex data is old, load from NS instead
            let latestDate = data[0].date
            let now = dateTimeUtils.getNowTimeIntervalUTC()
            if (latestDate + 330) < now && IsNightscoutEnabled() {
                self.webLoadNSBGData()
                print("Dex data is old, loading from NS instead")
                return
            }
            
            // Dexcom only returns 24 hrs of data. If we need more, call NS.
            if graphHours > 24 && IsNightscoutEnabled() {
                self.webLoadNSBGData(dexData: data)
            } else {
                self.ProcessDexBGData(data: data, sourceName: "Dexcom")
            }
        }
    }

    // NS BG Data Web call
    func webLoadNSBGData(dexData: [ShareGlucoseData] = []) {
        // This kicks it out in the instance where dexcom fails but they aren't using NS &&
        if !IsNightscoutEnabled() {
            return
        }

        var parameters: [String: String] = [:]
        let utcISODateFormatter = ISO8601DateFormatter()
        let date = Calendar.current.date(byAdding: .day, value: -1 * UserDefaultsRepository.downloadDays.value, to: Date())!
        parameters["count"] = "\(UserDefaultsRepository.downloadDays.value * 2 * 24 * 60 / 5)"
        parameters["find[dateString][$gte]"] = utcISODateFormatter.string(from: date)

        // Exclude 'cal' entries
        parameters["find[type][$ne]"] = "cal"
        
        NightscoutUtils.executeRequest(eventType: .sgv, parameters: parameters) { (result: Result<[ShareGlucoseData], Error>) in
            switch result {
            case .success(let entriesResponse):
                var nsData = entriesResponse
                DispatchQueue.main.async {
                    // transform NS data to look like Dex data
                    for i in 0..<nsData.count {
                        // convert the NS timestamp to seconds instead of milliseconds
                        nsData[i].date /= 1000
                        nsData[i].date.round(FloatingPointRoundingRule.toNearestOrEven)
                    }
                    print(nsData.count)
                    
                    //Avoid duplicate entries messing up the graph, only use one reading per 5 minutes.
                    let graphHours = 24 * UserDefaultsRepository.downloadDays.value
                    let points = graphHours * 12 + 1
                    var nsData2 = [ShareGlucoseData]()
                    let timestamp = Date().timeIntervalSince1970
                    for i in 0..<points {
                        //Starting with "now" and then step 5 minutes back in time
                        let target = timestamp - Double(i) * 60 * 5
                        //Find the reading closest to the target, but not too far away
                        let closest = nsData.filter{ abs($0.date - target) < 3 * 60 }.min { abs($0.date - target) < abs($1.date - target) }
                        //If a reading is found, add it to the new array
                        if let item = closest {
                            nsData2.append(item)
                        }
                    }
                    print(nsData2.count)
                    
                    // merge NS and Dex data if needed; use recent Dex data and older NS data
                    var sourceName = "Nightscout"
                    if !dexData.isEmpty {
                        let oldestDexDate = dexData[dexData.count - 1].date
                        var itemsToRemove = 0
                        while itemsToRemove < nsData2.count && nsData2[itemsToRemove].date >= oldestDexDate {
                            itemsToRemove += 1
                        }
                        nsData2.removeFirst(itemsToRemove)
                        nsData2 = dexData + nsData2
                        sourceName = "Dexcom"
                    }
                    // trigger the processor for the data after downloading.
                    self.ProcessDexBGData(data: nsData2, sourceName: sourceName)
                }
            case .failure(let error):
                LogManager.shared.log(category: .nightscout, message: "Failed to fetch data: \(error)")
                DispatchQueue.main.async {
                    TaskScheduler.shared.rescheduleTask(
                        id: .fetchBG,
                        to: Date().addingTimeInterval(10)
                    )
                }
                // if we have Dex data, use it
                if !dexData.isEmpty {
                    self.ProcessDexBGData(data: dexData, sourceName: "Dexcom")
                }
                return
            }
        }
    }
    
    // Dexcom BG Data Response processor
    func ProcessDexBGData(data: [ShareGlucoseData], sourceName: String){
        let graphHours = 24 * UserDefaultsRepository.downloadDays.value
        
        if data.count == 0 {
            return
        }
        let latestDate = data[0].date
        let now = dateTimeUtils.getNowTimeIntervalUTC()
        
        // Start the BG timer based on the reading
        let secondsAgo = now - latestDate
        
        DispatchQueue.main.async {
            if secondsAgo >= (20 * 60) {
                TaskScheduler.shared.rescheduleTask(
                    id: .fetchBG,
                    to: Date().addingTimeInterval(5 * 60)
                )
            } else if secondsAgo >= (10 * 60) {
                TaskScheduler.shared.rescheduleTask(
                    id: .fetchBG,
                    to: Date().addingTimeInterval(60)
                )
            } else if secondsAgo >= (7 * 60) {
                TaskScheduler.shared.rescheduleTask(
                    id: .fetchBG,
                    to: Date().addingTimeInterval(30)
                )
            } else if secondsAgo >= (5 * 60) {
                TaskScheduler.shared.rescheduleTask(
                    id: .fetchBG,
                    to: Date().addingTimeInterval(10)
                )
            } else {
                let delay = (300 - secondsAgo + Double(UserDefaultsRepository.bgUpdateDelay.value))
                TaskScheduler.shared.rescheduleTask(
                    id: .fetchBG,
                    to: Date().addingTimeInterval(delay)
                )

                if data.count > 1 {
                    self.evaluateSpeakConditions(currentValue: data[0].sgv, previousValue: data[1].sgv)
                }
            }
        }
        
        bgData.removeAll()
        
        // loop through the data so we can reverse the order to oldest first for the graph
        for i in 0..<data.count {
            let dateString = data[data.count - 1 - i].date
            if dateString >= dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours) {
                let sgvValue = data[data.count - 1 - i].sgv
                
                // Skip the current iteration if the sgv value is over 600
                // First time a user starts a G7, they get a value of 4000
                if sgvValue > 600 {
                    continue
                }
                
                let reading = ShareGlucoseData(sgv: sgvValue, date: dateString, direction: data[data.count - 1 - i].direction)
                bgData.append(reading)
            }
        }
        
        viewUpdateNSBG(sourceName: sourceName)
    }
    
    func updateServerText(with serverText: String? = nil) {
        if UserDefaultsRepository.showDisplayName.value, let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            self.serverText.text = displayName
        } else if let serverText = serverText {
            self.serverText.text = serverText
        }
    }
    
    // NS BG Data Front end updater
    func viewUpdateNSBG(sourceName: String) {
        DispatchQueue.main.async {
            TaskScheduler.shared.rescheduleTask(id: .minAgoUpdate, to: Date())
            
            let entries = self.bgData
            if entries.count < 2 { return } // Protect index out of bounds
            
            self.updateBGGraph()
            self.updateStats()
            
            let latestEntryIndex = entries.count - 1
            let latestBGEntry = entries[latestEntryIndex]
            let latestBG = latestBGEntry.sgv
            let lastBGTime = latestBGEntry.date
            
            var priorBGEntry: ShareGlucoseData?
            var priorBG: Int?
            var deltaBG: Int?
            
            // Daniel: Find a valid prior entry that is at least 4 minutes apart
            for i in (0..<latestEntryIndex).reversed() {
                let candidateEntry = entries[i]
                let timeDifference = (latestBGEntry.date - candidateEntry.date) / 60
                if timeDifference >= 4 {
                    priorBGEntry = candidateEntry
                    priorBG = candidateEntry.sgv
                    deltaBG = latestBG - priorBG!
                    break
                }
            }
            
            let deltaTime = (TimeInterval(Date().timeIntervalSince1970) - lastBGTime) / 60
            var userUnit = " mg/dL"
            if self.mmol {
                userUnit = " mmol/L"
            }
            
            self.updateServerText(with: sourceName)
            
            var snoozerBG = ""
            var snoozerDirection = ""
            var snoozerDelta = ""
            
            // Set BGText with the latest BG value
            self.BGText.text = Localizer.toDisplayUnits(String(latestBG)).replacingOccurrences(of: ",", with: ".")
            //Daniel: Added for visualization in remote meal info popup
            sharedLatestBG = Localizer.toDisplayUnits(String(latestBG)).replacingOccurrences(of: ",", with: ".")
            snoozerBG = Localizer.toDisplayUnits(String(latestBG)).replacingOccurrences(of: ",", with: ".")
            self.setBGTextColor()
            
            // Direction handling
            if let directionBG = entries[latestEntryIndex].direction {
                self.DirectionText.text = self.bgDirectionGraphic(directionBG)
                //Daniel: Added for visualization in remote meal info popup
                sharedLatestDirection = self.bgDirectionGraphic(directionBG)
                snoozerDirection = self.bgDirectionGraphic(directionBG)
                self.latestDirectionString = self.bgDirectionGraphic(directionBG)
            } else {
                self.DirectionText.text = ""
                //Daniel: Added for visualization in remote meal info popup
                sharedLatestDirection = ""
                snoozerDirection = ""
                self.latestDirectionString = ""
            }
            
            // Delta handling
            if let deltaBG = deltaBG {
                if deltaBG < 0 {
                    self.DeltaText.text = Localizer.toDisplayUnits(String(deltaBG)).replacingOccurrences(of: ",", with: ".")
                    //Daniel: Added for visualization in remote meal info popup
                    sharedLatestDelta = Localizer.toDisplayUnits(String(deltaBG)).replacingOccurrences(of: ",", with: ".")
                    snoozerDelta = Localizer.toDisplayUnits(String(deltaBG)).replacingOccurrences(of: ",", with: ".")
                    self.latestDeltaString = String(deltaBG).replacingOccurrences(of: ",", with: ".")
                } else {
                    self.DeltaText.text = "+" + Localizer.toDisplayUnits(String(deltaBG)).replacingOccurrences(of: ",", with: ".")
                    //Daniel: Added for visualization in remote meal info popup
                    sharedLatestDelta = "+" + Localizer.toDisplayUnits(String(deltaBG)).replacingOccurrences(of: ",", with: ".")
                    snoozerDelta = "+" + Localizer.toDisplayUnits(String(deltaBG)).replacingOccurrences(of: ",", with: ".")
                    self.latestDeltaString = "+" + String(deltaBG).replacingOccurrences(of: ",", with: ".")
                }
            } else {
                self.DeltaText.text = "N/A"
                sharedLatestDelta = "N/A"
                snoozerDelta = "N/A"
                self.latestDeltaString = "N/A"
            }
            /*
            // Delta handling
            if deltaBG < 0 {
                self.DeltaText.text = Localizer.toDisplayUnits(String(deltaBG))
                snoozerDelta = Localizer.toDisplayUnits(String(deltaBG))
                self.latestDeltaString = String(deltaBG)
            } else {
                self.DeltaText.text = "+" + Localizer.toDisplayUnits(String(deltaBG))
                snoozerDelta = "+" + Localizer.toDisplayUnits(String(deltaBG))
                self.latestDeltaString = "+" + String(deltaBG)
            }
            */
            // Apply strikethrough to BGText based on the staleness of the data
            let bgTextStr = (self.BGText.text ?? "").replacingOccurrences(of: ",", with: ".")
            let attributeString = NSMutableAttributedString(string: bgTextStr)
            attributeString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attributeString.length))
            if deltaTime >= 6 { // Data is stale
                attributeString.addAttribute(.strikethroughColor, value: UIColor.systemRed, range: NSRange(location: 0, length: attributeString.length))
                self.updateBadge(val: 0)
            } else { // Data is fresh
                attributeString.addAttribute(.strikethroughColor, value: UIColor.clear, range: NSRange(location: 0, length: attributeString.length))
                self.updateBadge(val: latestBG)
            }
            self.BGText.attributedText = attributeString
            
            // Snoozer Display
            guard let snoozer = self.tabBarController!.viewControllers?[2] as? SnoozeViewController else { return }
            snoozer.BGLabel.text = snoozerBG
            snoozer.DirectionLabel.text = snoozerDirection
            snoozer.DeltaLabel.text = snoozerDelta
            
            //FifteenMinutesTrend
            
            // Clean up bgTextStr and snoozerDelta
            let cleanedBGTextStr = bgTextStr.replacingOccurrences(of: ",", with: ".")
            let cleanedSnoozerDelta = snoozerDelta
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: "+", with: "") // Remove leading plus sign if present
            // Convert to Double
            let bgValue = Double(cleanedBGTextStr)
            let deltaBGValue = Double(cleanedSnoozerDelta)
            // Log cleaned and converted values
            print("Cleaned bgValue: \(bgValue ?? 0.0)")
            print("Cleaned deltaBGValue: \(deltaBGValue ?? 0.0)")
            // Perform calculation
            let fifteenMin = ((bgValue ?? 0.0) + (deltaBGValue ?? 0.0) * 2.5)
            print("Raw fifteenMin calculation: \(fifteenMin)")
            // Format the calculated value to a string
            let fifteenMinString = String(format: "%.1f", fifteenMin)
            // Convert back to Double for conditional checks
            let fifteenMinValue = Double(fifteenMinString) ?? 0.0
            // Use the calculated 'fifteenMinValue' to build the color-coded string
            var fifteenMinColorString: String = ""
            if deltaTime >= 6 {
                fifteenMinColorString = " ❔ "
            } else if fifteenMinValue < 3.9 {
                fifteenMinColorString = " 🆘 "
            } else if fifteenMinValue > 7.8 {
                fifteenMinColorString = " ⚠️ "
            } else {
                fifteenMinColorString = " ✅ "
            }
            
            var cob = "N/A g"
            if let latestCOB = self.latestCOB?.description, !latestCOB.isEmpty {
                cob = latestCOB
            }
            print("cob: \(cob)")

            var iob = "N/A E"
            if let latestIOB = self.latestIOB?.description, !latestIOB.isEmpty {
                if let numericPart = Double(latestIOB.replacingOccurrences(of: "E", with: "").trimmingCharacters(in: .whitespaces)) {
                    // Format to one decimal place and reconstruct the string with "E"
                    iob = String(format: "%.1f", numericPart) + "E"
                } else {
                    iob = latestIOB // Fallback to original if parsing fails
                }
            }
            print("iob: \(iob)")
            
            // Update contact
            if ObservableUserDefaults.shared.contactEnabled.value {
                var extra: String = ""
                
                if ObservableUserDefaults.shared.contactTrend.value {
                    extra = snoozerDirection
                } else if ObservableUserDefaults.shared.contactDelta.value {
                    extra = snoozerDelta
                }
                
                var extra2: String = ""
                var extra3: String = ""
                if ObservableUserDefaults.shared.contactFifteenMinutes.value {
                    extra2 = fifteenMinColorString
                    extra3 = fifteenMinString
                }
                
                self.contactImageUpdater.updateContactImage(bgValue: bgTextStr, extra: extra, extra2: extra2, extra3: extra3, iob: iob, cob: cob, stale: deltaTime >= 6)//>= 12)
            }
        }
    }
}

extension CarbMetric: CustomStringConvertible {
    var description: String {
        return String(format: "%.0f", value) // Adjust format as needed
    }
}

extension InsulinMetric: CustomStringConvertible {
    var description: String {
        return String(format: "%.2f", value) // Adjust format as needed
    }
}
