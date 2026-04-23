//
//  BGData.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2023-10-05.

//

import Foundation
import UIKit

fileprivate var isBGFetchInProgress = false
fileprivate var bgFetchStartedAt: Date? = nil


extension MainViewController {
    // Dex Share Web Call
    func webLoadDexShare() {
        let now = Date()
        
        // Samma stale-skydd som för Nightscout-fetchen
        if isBGFetchInProgress {
            let elapsed = now.timeIntervalSince(bgFetchStartedAt ?? now)
            
            if elapsed > 60 {
                // En pågående fetch verkar ha hängt → släpp låset och börja om.
                LogManager.shared.log(
                    category: .dexcom,
                    message: "[BGFetch] Detected stale in-progress Dexcom fetch (\(Int(elapsed)) s). Forcing reset and starting a new request.",
                    isDebug: false
                )
                isBGFetchInProgress = false
                bgFetchStartedAt = nil
            } else {
                // Normal “in progress” → logga och hoppa över.
                LogManager.shared.log(
                    category: .dexcom,
                    message: "[BGFetch] Skipping webLoadDexShare – fetch already in progress (\(Int(elapsed)) s).",
                    isDebug: false
                )
                return
            }
        }
        
        // Starta en ny Dexcom-fetch
        isBGFetchInProgress = true
        bgFetchStartedAt = now
        
        // Dexcom Share only returns 24 hrs of data as of now
        // Requesting more just for consistency with NS
        let graphHours = 24 * UserDefaultsRepository.downloadDays.value
        let count = graphHours * 12
        
        dexShare?.fetchData(count) { (err, result) -> () in
            LogManager.shared.log(
                category: .dexcom,
                message: "[BGFetch] webLoadDexShare callback – error=\(err?.localizedDescription ?? "nil"), resultCount=\(result?.count ?? 0)",
                isDebug: true
            )
            
            if let error = err {
                LogManager.shared.log(
                    category: .dexcom,
                    message: "Error fetching Dexcom data: \(error.localizedDescription)",
                    limitIdentifier: "Error fetching Dexcom data"
                )
                // Låt Nightscout-fallback ta över; den kommer att nolla in-progress-flaggan i sin callback.
                self.webLoadNSBGData(fromDexFallback: true)
                return
            }
            
            guard let data = result else {
                LogManager.shared.log(
                    category: .dexcom,
                    message: "Received nil data from Dexcom",
                    limitIdentifier: "Received nil data from Dexcom"
                )
                // Fallback till Nightscout (nollar flaggor i sin callback)
                self.webLoadNSBGData(fromDexFallback: true)
                return
            }
            
            // If Dex data is old, load from NS instead
            let latestDate = data[0].date
            let now = dateTimeUtils.getNowTimeIntervalUTC()
            if (latestDate + 330) < now && IsNightscoutEnabled() {
                LogManager.shared.log(
                    category: .dexcom,
                    message: "Dexcom data is old, loading from NS instead",
                    limitIdentifier: "Dexcom data is old, loading from NS instead"
                )
                // Fallback till Nightscout (nollar flaggor i sin callback)
                self.webLoadNSBGData(fromDexFallback: true)
                return
            }
            
            // Dexcom only returns 24 hrs of data. If we need more, call NS.
            if graphHours > 24 && IsNightscoutEnabled() {
                // Här låter vi NS göra jobbet (och nolla flaggor i sin callback).
                self.webLoadNSBGData(dexData: data, fromDexFallback: true)
            } else {
                if let latest = data.first {
                    let ts = Date(timeIntervalSince1970: latest.date)
                    LogManager.shared.log(
                        category: .temporaryDebug,
                        message: "[BGFetch] webLoadDexShare SUCCESS, last sgv=\(latest.sgv) at \(ts)",
                        isDebug: true
                    )
                } else {
                    LogManager.shared.log(
                        category: .temporaryDebug,
                        message: "[BGFetch] webLoadDexShare SUCCESS, but no entries returned",
                        isDebug: false
                    )
                }
                
                // Dex-only success: nu är vi klara → släpp låset.
                isBGFetchInProgress = false
                bgFetchStartedAt = nil
                
                self.ProcessDexBGData(data: data, sourceName: "Dexcom")
            }
        }
    }
    
    // NS BG Data Web call
    func webLoadNSBGData(dexData: [ShareGlucoseData] = [], fromDexFallback: Bool = false) {
        // This kicks it out in the instance where dexcom fails but they aren't using NS &&
        if !fromDexFallback {
            let now = Date()
            
            if isBGFetchInProgress {
                let elapsed = now.timeIntervalSince(bgFetchStartedAt ?? now)
                
                // Om en fetch verkar ha hängt längre än 60 sekunder → släpp låset och starta om.
                if elapsed > 60 {
                    LogManager.shared.log(
                        category: .nightscout,
                        message: "[BGFetch] Detected stale in-progress NS fetch (\(Int(elapsed)) s). Forcing reset and starting a new request.",
                        isDebug: false
                    )
                    isBGFetchInProgress = false
                    bgFetchStartedAt = nil
                } else {
                    // Normal “in progress” → logga och hoppa över.
                    LogManager.shared.log(
                        category: .nightscout,
                        message: "[BGFetch] Skipping webLoadNSBGData – fetch already in progress (\(Int(elapsed)) s).",
                        isDebug: false
                    )
                    return
                }
            }
            
            // Starta en ny NS-fetch
            isBGFetchInProgress = true
            bgFetchStartedAt = now
        }

        if !IsNightscoutEnabled() {
            // Om Nightscout är avstängt – se till att vi inte lämnar in-progress-flaggan satt.
            isBGFetchInProgress = false
            bgFetchStartedAt = nil
            return
        }
        
        var parameters: [String: String] = [:]
        let utcISODateFormatter = ISO8601DateFormatter()
        let date = Calendar.current.date(byAdding: .day,
                                         value: -1 * UserDefaultsRepository.downloadDays.value,
                                         to: Date())!
        parameters["count"] = "\(UserDefaultsRepository.downloadDays.value * 2 * 24 * 60 / 5)"
        parameters["find[dateString][$gte]"] = utcISODateFormatter.string(from: date)
        
        // Exclude 'cal' entries
        parameters["find[type][$ne]"] = "cal"
        
        NightscoutUtils.executeRequest(eventType: .sgv, parameters: parameters) { (result: Result<[ShareGlucoseData], Error>) in
            /*LogManager.shared.log(
                category: .temporaryDebug,
                message: "[BGFetch] webLoadNSBGData callback – result=\(result)",
                isDebug: true
            )*/
            switch result {
            case .success(let entriesResponse):
                if let latest = entriesResponse.first {
                    let ts = Date(timeIntervalSince1970: latest.date / 1000.0)
                    LogManager.shared.log(
                        category: .temporaryDebug,
                        message: "[BGFetch] webLoadNSBGData SUCCESS, last sgv=\(latest.sgv) at \(ts)",
                        isDebug: true
                    )
                } else {
                    LogManager.shared.log(
                        category: .temporaryDebug,
                        message: "[BGFetch] webLoadNSBGData SUCCESS, but no entries returned",
                        isDebug: false
                    )
                }
                var nsData = entriesResponse
                DispatchQueue.main.async {
                    // transform NS data to look like Dex data
                    for i in 0..<nsData.count {
                        // convert the NS timestamp to seconds instead of milliseconds
                        nsData[i].date /= 1000
                        nsData[i].date.round(FloatingPointRoundingRule.toNearestOrEven)
                    }
                    var nsData2: [ShareGlucoseData] = []
                    var lastAddedTime = Double.infinity
                    let minInterval: Double = 4 * 60
                    
                    for reading in nsData {
                        if lastAddedTime - reading.date >= minInterval {
                            nsData2.append(reading)
                            lastAddedTime = reading.date
                        }
                    }
                    
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
                    isBGFetchInProgress = false
                    bgFetchStartedAt = nil
                    self.ProcessDexBGData(data: nsData2, sourceName: sourceName)
                }
            case .failure(let error):
                LogManager.shared.log(
                    category: .temporaryDebug,
                    message: "[BGFetch] webLoadNSBGData FAILED: \(error.localizedDescription)",
                    isDebug: false
                )
                LogManager.shared.log(category: .nightscout,
                                      message: "Failed to fetch bg data: \(error)",
                                      limitIdentifier: "Failed to fetch bg data")

                // Bestäm retry-delay baserat på felet
                let retryDelay: TimeInterval
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .notConnectedToInternet,
                         .networkConnectionLost,
                         .timedOut:
                        // Tydligt “tunnel-läge” / inget nät → ta det lugnt
                        retryDelay = 60    // eller t.o.m. 120 om du vill vara ännu snällare
                    default:
                        // Annat fel (serverfel etc) → lite mer aggressiv retry är ok
                        retryDelay = 15
                    }
                } else {
                    retryDelay = 15
                }

                DispatchQueue.main.async {
                    TaskScheduler.shared.rescheduleTask(
                        id: .fetchBG,
                        to: Date().addingTimeInterval(retryDelay)
                    )
                }

                // om vi har Dexcom-data, använd den tills vidare
                if !dexData.isEmpty {
                    self.ProcessDexBGData(data: dexData, sourceName: "Dexcom")
                }

                isBGFetchInProgress = false
                bgFetchStartedAt = nil
                return
            }
        }
    }
    
    /// Processes incoming BG data.
    func ProcessDexBGData(data: [ShareGlucoseData], sourceName: String) {
        let graphHours = 24 * UserDefaultsRepository.downloadDays.value
        
        guard !data.isEmpty else {
            LogManager.shared.log(category: .nightscout, message: "No bg data received. Skipping processing.", limitIdentifier: "No bg data received. Skipping processing.")
            return
        }
        let latestReading = data[0]
        let sensorTimestamp = latestReading.date
        let now = dateTimeUtils.getNowTimeIntervalUTC()
        // secondsAgo is how old the newest reading is
        let secondsAgo = now - sensorTimestamp
        
        // Determine the cycle duration based on device type.
        let cycleDuration: TimeInterval = (Storage.shared.backgroundRefreshType.value == .rileyLink) ? 60 : 300

        // Compute the current sensor schedule offset using the appropriate cycle.
        let currentOffset = sensorScheduleOffset(for: sensorTimestamp, cycle: cycleDuration)
        
        if Storage.shared.sensorScheduleOffset.value != currentOffset {
            Storage.shared.sensorScheduleOffset.value = currentOffset
            LogManager.shared.log(category: .nightscout,
                                  message: "Sensor schedule offset: \(currentOffset) seconds.",
                                  isDebug: true)
        }
        
        // Determine the next polling delay.
        var delayToSchedule: Double = 0
        
        DispatchQueue.main.async {
            // Fallback scheduling for older readings.
            if secondsAgo >= (20 * 60) {
                delayToSchedule = 5 * 60
                
                
                LogManager.shared.log(category: .nightscout,
                                      message: "Reading is very old (\(secondsAgo) sec). Scheduling next fetch in 5 minutes.",
                                      isDebug: true)
            } else if secondsAgo >= (10 * 60) {
                delayToSchedule = 60
                
                
                LogManager.shared.log(category: .nightscout,
                                      message: "Reading is moderately old (\(secondsAgo) sec). Scheduling next fetch in 60 seconds.",
                                      isDebug: true)
            } else if secondsAgo >= (7 * 60) {
                delayToSchedule = 30
                
                
                LogManager.shared.log(category: .nightscout,
                                      message: "Reading is a bit old (\(secondsAgo) sec). Scheduling next fetch in 30 seconds.",
                                      isDebug: true)
            } else if secondsAgo >= (5 * 60) {
                delayToSchedule = 5
                
                
                LogManager.shared.log(category: .nightscout,
                                      message: "Reading is close to 5 minutes old (\(secondsAgo) sec). Scheduling next fetch in 5 seconds.",
                                      isDebug: true)
            } else {
                delayToSchedule = 300 - secondsAgo + Double(UserDefaultsRepository.bgUpdateDelay.value)
                LogManager.shared.log(category: .nightscout,
                                      message: "Fresh reading. Scheduling next fetch in \(delayToSchedule) seconds.",
                                      isDebug: true)
                
                TaskScheduler.shared.rescheduleTask(id: .alarmCheck, to: Date().addingTimeInterval(3))
            }
            
            if NightscoutSocketManager.shared.connectionState == .authenticated {
                            delayToSchedule = max(delayToSchedule * 3, 60)
                        }
            
            TaskScheduler.shared.rescheduleTask(id: .fetchBG, to: Date().addingTimeInterval(delayToSchedule))
            
            // Evaluate speak conditions if there is a previous value.
            if data.count > 1 {
                self.evaluateSpeakConditions(currentValue: data[0].sgv, previousValue: data[1].sgv)
            }
        }
        
        // Process data for graph display.
        bgData.removeAll()
        var sgvBatchForCache: [SGVJSON] = []
        
        for i in 0..<data.count {
            let dateString = data[data.count - 1 - i].date
            let readingTimestamp = data[data.count - 1 - i].date
            if readingTimestamp >= dateTimeUtils.getTimeIntervalNHoursAgo(N: graphHours) {
                let sgvValue = data[data.count - 1 - i].sgv

                // Skip outlier values (e.g. first reading of a new sensor might be abnormally high).
                if sgvValue > 600 {
                    LogManager.shared.log(category: .nightscout,
                                          message: "Skipping reading with sgv \(sgvValue) as it exceeds threshold.",
                                          isDebug: true)
                    continue
                }

                let reading = ShareGlucoseData(sgv: sgvValue, date: readingTimestamp, direction: data[data.count - 1 - i].direction)
                bgData.append(reading)
                // Collect SGVs for NightscoutCache (seconds since 1970 already)
                let sgvEntry = SGVJSON(date: reading.date, sgv: reading.sgv)
                sgvBatchForCache.append(sgvEntry)
            }
        }

        // Persist recent BG data into NightscoutCache on a background queue.
        // This keeps the per‑day cache files in sync with live BG without extra nightly fetches.
        if !sgvBatchForCache.isEmpty {
            let batchCopy = sgvBatchForCache
            DispatchQueue.global(qos: .utility).async {
                NightscoutCache.mergeSGVBatch(batchCopy)
            }
        }
        
        LogManager.shared.log(category: .nightscout,
                              message: "Graph data updated with \(bgData.count) entries.",
                              isDebug: true)
        
        viewUpdateNSBG(sourceName: sourceName)
    }
    /*
    /// Computes the sensor schedule offset (in seconds) for a given time interval.
    /// The offset is the remainder (in seconds) of the time elapsed since midnight (UTC) divided by 300 seconds.
    /// For example, if the sensor reports a time that corresponds to 13:06:30, the offset is 90 seconds.
    func sensorScheduleOffset(for timeInterval: TimeInterval) -> TimeInterval {
        var calendar = Calendar(identifier: .gregorian)
        // Use UTC to be consistent with our sensor timestamps.
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        
        let date = Date(timeIntervalSince1970: timeInterval)
        let startOfDay = calendar.startOfDay(for: date)
        let secondsSinceStartOfDay = date.timeIntervalSince(startOfDay)
        return secondsSinceStartOfDay.truncatingRemainder(dividingBy: 300)
    }
    */
    /// Computes the sensor schedule offset (in seconds) for a given time interval.
    /// The offset is the remainder (in seconds) of the time elapsed since midnight (UTC)
    /// divided by the given cycle length (default 300 seconds).
    func sensorScheduleOffset(for timeInterval: TimeInterval, cycle: TimeInterval = 300) -> TimeInterval {
        var calendar = Calendar(identifier: .gregorian)
        // Use UTC to be consistent with our sensor timestamps.
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        
        let date = Date(timeIntervalSince1970: timeInterval)
        let startOfDay = calendar.startOfDay(for: date)
        let secondsSinceStartOfDay = date.timeIntervalSince(startOfDay)
        return secondsSinceStartOfDay.truncatingRemainder(dividingBy: cycle)
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
            // Spegla live-BG till statistikens BG-array (senaste ~2 dygnen)
            self.stats_syncBGFromLive()
            self.updateStats()
            self.stats_saveToCache()

            let latestEntryIndex = entries.count - 1
            let latestBGEntry = entries[latestEntryIndex]
            let latestBG = latestBGEntry.sgv
            let lastBGTime = latestBGEntry.date

            var priorBGEntry: ShareGlucoseData?
            var priorBG: Int?
            var deltaBG: Int?
            var deltaWasInterpolated: Bool = false

            // Daniel: Find a valid prior entry that is at least 4 minutes apart
            for i in (0..<latestEntryIndex).reversed() {
                let candidateEntry = entries[i]
                let timeDifferenceSec = latestBGEntry.date - candidateEntry.date
                let timeDifferenceMin = timeDifferenceSec / 60

                // Guard against near-duplicates (<4 min apart)
                if timeDifferenceMin >= 4 {
                    priorBGEntry = candidateEntry
                    priorBG = candidateEntry.sgv

                    let rawDelta = Double(latestBG - priorBG!)

                    // If more than 6 minutes apart, interpolate to a 5‑minute equivalent delta.
                    if timeDifferenceSec > 6 * 60 {
                        let scale = 300.0 / Double(timeDifferenceSec)  // 5 min / actual gap
                        let interpolated = rawDelta * scale
                        deltaBG = Int(round(interpolated))
                        deltaWasInterpolated = true
                    } else {
                        deltaBG = Int(rawDelta)
                    }
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
            // NOTE: `latestBG` (sgv) is always mg/dL (from NS/Dex).
            // We only convert for display via `Localizer.toDisplayUnits(...)`.
            // Dexcom “LOW/HIGH” are represented as 40 / 400 mg/dL, regardless of display units.
            let bgValueMgdl = latestBG

            let bgDisplay: String
            if bgValueMgdl <= 40 {
                bgDisplay = "LÅG"
            } else if bgValueMgdl >= 400 {
                bgDisplay = "HÖG"
            } else {
                bgDisplay = Localizer
                    .toDisplayUnits(String(latestBG))
                    .replacingOccurrences(of: ",", with: ".")
            }
            self.BGText.text = bgDisplay
            //Daniel: Added for visualization in remote meal info popup
            Storage.shared.sharedLatestBG.value = bgDisplay
            snoozerBG = bgDisplay
            self.setBGTextColor()
            // 🦄 Show/hide unicorn for exactly 5.5 mmol/L
            self.updateUnicornVisibility(forBGDisplayString: bgDisplay)
            self.update67HandsVisibility(forBGDisplayString: bgDisplay)
            self.updateTargetLogoVisibility(forBGDisplayString: bgDisplay)
            
            // Direction handling
            if let directionBG = entries[latestEntryIndex].direction {
                self.DirectionText.text = self.bgDirectionGraphic(directionBG)
                //Daniel: Added for visualization in remote meal info popup
                Storage.shared.sharedLatestDirection.value = self.bgDirectionGraphic(directionBG)
                snoozerDirection = self.bgDirectionGraphic(directionBG)
                self.latestDirectionString = self.bgDirectionGraphic(directionBG)
            } else {
                self.DirectionText.text = ""
                //Daniel: Added for visualization in remote meal info popup
                Storage.shared.sharedLatestDirection.value = ""
                snoozerDirection = ""
                self.latestDirectionString = ""
            }
            
            // Delta handling
            if let deltaBG = deltaBG {
                if deltaBG < 0 {
                    self.latestDeltaString = Localizer.toDisplayUnits(String(deltaBG)).replacingOccurrences(of: ",", with: ".")
                } else {
                    self.latestDeltaString = "+" + Localizer.toDisplayUnits(String(deltaBG)).replacingOccurrences(of: ",", with: ".")
                }

                var formattedDelta = self.latestDeltaString.replacingOccurrences(of: ",", with: ".")
                if deltaWasInterpolated { formattedDelta += "*" }

                // Daniel: Added for visualization in remote meal info popup
                Storage.shared.sharedLatestDelta.value = formattedDelta

                self.DeltaText.text = formattedDelta
                snoozerDelta = formattedDelta
            } else {
                self.DeltaText.text = "--"
                Storage.shared.sharedLatestDelta.value = "--"
                snoozerDelta = "--"
                self.latestDeltaString = "--"
            }

            // Apply strikethrough to BGText based on the staleness of the data
            let bgTextStr = (self.BGText.text ?? "").replacingOccurrences(of: ",", with: ".")
            let attributeString = NSMutableAttributedString(string: bgTextStr)
            attributeString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attributeString.length))
            if deltaTime >= 11 { // Data is stale for 11 min +
                attributeString.addAttribute(.strikethroughColor, value: UIColor.systemRed, range: NSRange(location: 0, length: attributeString.length))
                self.updateBadge(val: 0)

                // If a Dexcom G7 sensor note – surface severity; otherwise N/A
                if let status = self.dexcomG7SensorStatus(after: lastBGTime) {
                    self.infoManager.updateInfoData(type: .sensorStatus, value: status)
                    self.infoManager.setPriority(true, for: .sensorStatus)
                } else {
                    self.infoManager.updateInfoData(type: .sensorStatus, value: "--")
                    self.infoManager.setPriority(false, for: .sensorStatus)
                }

            } else if deltaTime >= 6 { // Data is stale for 6-11 min
                attributeString.addAttribute(.strikethroughColor, value: UIColor.label, range: NSRange(location: 0, length: attributeString.length))
                self.updateBadge(val: 0)

                // If a Dexcom G7 sensor note – surface severity; otherwise N/A
                if let status = self.dexcomG7SensorStatus(after: lastBGTime) {
                    self.infoManager.updateInfoData(type: .sensorStatus, value: status)
                    self.infoManager.setPriority(true, for: .sensorStatus)
                } else {
                    self.infoManager.updateInfoData(type: .sensorStatus, value: "--")
                    self.infoManager.setPriority(false, for: .sensorStatus)
                }

            } else { // Data is fresh
                attributeString.addAttribute(.strikethroughColor, value: UIColor.clear, range: NSRange(location: 0, length: attributeString.length))
                self.updateBadge(val: latestBG)
                self.infoManager.updateInfoData(type: .sensorStatus, value: "OK 🟢")
                self.infoManager.setPriority(false, for: .sensorStatus)
            }
            self.BGText.attributedText = attributeString
            
            // Snoozer Display
            guard let snoozer = self.tabBarController!.viewControllers?[2] as? SnoozeViewController else { return }
            snoozer.BGLabel.text = snoozerBG
            snoozer.DirectionLabel.text = snoozerDirection
            snoozer.DeltaLabel.text = snoozerDelta
            snoozer.updateEasterEggs(bgDisplay: snoozerBG)
            
            //FifteenMinutesTrend
            
            // Clean up bgTextStr and snoozerDelta
            var cleanedBGTextStr = bgTextStr.replacingOccurrences(of: ",", with: ".")
            let cleanedSnoozerDelta = snoozerDelta
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: "+", with: "")// Remove leading plus sign if present
                .replacingOccurrences(of: "*", with: "")// Remove * sign if present
            // Convert to Double
            let bgValue = Double(cleanedBGTextStr)
            let deltaBGValue = Double(cleanedSnoozerDelta)
            // Log cleaned and converted values
            LogManager.shared.log(category: .contact, message: "Cleaned bgValue: \(bgValue ?? 0.0)", isDebug: true)
            LogManager.shared.log(category: .contact, message: "Cleaned deltaBGValue: \(deltaBGValue ?? 0.0)", isDebug: true)
            // Perform calculation
            let fifteenMin = ((bgValue ?? 0.0) + (deltaBGValue ?? 0.0) * 2)
            // Format the calculated value to a string
            let fifteenMinString = String(format: "%.1f", fifteenMin)
            LogManager.shared.log(category: .contact, message: "fifteenMin calculation: \(fifteenMinString)", isDebug: true)
            // Convert back to Double for conditional checks
            let fifteenMinValue = Double(fifteenMinString) ?? 0.0
            // Use the calculated 'fifteenMinValue' to build the color-coded string
            var fifteenMinColorString: String = ""
            if deltaTime >= 6 {
                fifteenMinColorString = " ❔ "
                let sensorTrendString = "--"
                self.infoManager.updateInfoData(type: .sensorTrend, value: sensorTrendString)
                self.infoManager.setPriority(true, for: .sensorTrend)
            } else if self.BGText.text == "LÅG" {
                fifteenMinColorString = " 🆘 "
                let sensorTrendString = "LÅG 🆘"
                self.infoManager.updateInfoData(type: .sensorTrend, value: sensorTrendString)
                self.infoManager.setPriority(true, for: .sensorTrend)
            } else if self.BGText.text == "HÖG" {
                fifteenMinColorString = " ⚠️ "
                let sensorTrendString = "HÖG 🆘"
                self.infoManager.updateInfoData(type: .sensorTrend, value: sensorTrendString)
                self.infoManager.setPriority(true, for: .sensorTrend)
            } else if fifteenMinValue < 3.9 {
                fifteenMinColorString = " 🆘 "
                let sensorTrendString = "\(fifteenMinString) mmol/L 🆘"
                self.infoManager.updateInfoData(type: .sensorTrend, value: sensorTrendString)
                self.infoManager.setPriority(true, for: .sensorTrend)
            } else if fifteenMinValue > 7.8 {
                fifteenMinColorString = " ⚠️ "
                let sensorTrendString = "\(fifteenMinString) mmol/L ⚠️"
                self.infoManager.updateInfoData(type: .sensorTrend, value: sensorTrendString)
                self.infoManager.setPriority(true, for: .sensorTrend)
            } else {
                fifteenMinColorString = " ✅ "
                let sensorTrendString = "\(fifteenMinString) mmol/L ✅"
                self.infoManager.updateInfoData(type: .sensorTrend, value: sensorTrendString)
                self.infoManager.setPriority(false, for: .sensorTrend)
            }
            
            var cob = "-- g"
            if let latestCOB = self.latestCOB?.description, !latestCOB.isEmpty {
                if let numericPart = Double(latestCOB.replacingOccurrences(of: "g", with: "").trimmingCharacters(in: .whitespaces)) {
                    // Format to one decimal place and reconstruct the string with "E"
                    cob = String(format: "%.0f", numericPart) + "g"
                } else {
                    cob = latestCOB // Fallback to original if parsing fails
                }
            }
            LogManager.shared.log(category: .contact, message: "COB: \(cob)", isDebug: true)
            
            var iob = "-- E"
            if let latestIOB = self.latestIOB?.description, !latestIOB.isEmpty {
                if let numericPart = Double(latestIOB.replacingOccurrences(of: "E", with: "").trimmingCharacters(in: .whitespaces)) {
                    // Format to one decimal place and reconstruct the string with "E"
                    iob = String(format: "%.1f", numericPart) + "E"
                } else {
                    iob = latestIOB // Fallback to original if parsing fails
                }
            }
            LogManager.shared.log(category: .contact, message: "IOB: \(iob)", isDebug: true)
            
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
                    if self.BGText.text == "LÅG" {
                        extra3 = "LÅG"
                    } else if self.BGText.text == "HÖG" {
                        extra3 = "HÖG"
                    } else {
                        extra3 = fifteenMinString
                    }
                }
                
                self.contactImageUpdater.updateContactImage(bgValue: bgTextStr, extra: extra, extra2: extra2, extra3: extra3, iob: iob, cob: cob, stale: deltaTime >= 6)//>= 12)
            }
            PhoneSessionManager.shared.sendConfig()
        }
    }
    
    /// Returns a sensor-status string based on Dexcom G7 Nightscout Note treatments AFTER the latest BG timestamp.
    /// We use the emoji prefix in the note to infer severity:
    /// - "⛔️ Dexcom G7"  -> "Fel ⛔️"
    /// - "⚠️ Dexcom G7" -> "Fel ⚠️"
    /// Returns nil if no matching note exists.
    private func dexcomG7SensorStatus(after latestBGTime: TimeInterval) -> String? {
        // noteGraphData is populated from NS treatments (Notes.swift)
        // noteStruct.date is in seconds since 1970.
        guard !noteGraphData.isEmpty else { return nil }

        // Only consider notes newer than the latest BG
        let relevant = noteGraphData.filter { $0.date > latestBGTime }
        guard !relevant.isEmpty else { return nil }

        // Highest severity wins (⛔️ over ⚠️)
        if relevant.contains(where: { $0.note.localizedCaseInsensitiveContains("⛔️ Dexcom G7") }) {
            return "Fel ⛔️"
        }

        if relevant.contains(where: { $0.note.localizedCaseInsensitiveContains("⚠️ Dexcom G7") }) {
            return "Fel ⚠️"
        }

        return nil
    }
    
    /// Shows a big unicorn behind BGView when BG is exactly 5.5 mmol/L, hides otherwise.
    fileprivate func updateUnicornVisibility(forBGDisplayString bg: String) {
        let shouldShow = (bg == "5.5")
        UIView.animate(withDuration: 0.25) {
            self.unicornLabel.alpha = shouldShow ? 0.5 : 0.0
        }
    }
    /// Shows the 6–7 hands image behind BGView when BG is exactly 6.7 mmol/L
    fileprivate func update67HandsVisibility(forBGDisplayString bg: String) {
        let shouldShow = (bg == "6.7")
        UIView.animate(withDuration: 0.25) {
            self.hands67ImageView.alpha = shouldShow ? 0.4 : 0.0
        }
    }
    /// Shows the target logo image behind BGView when BG is exactly at target mmol/L,
    /// except when target is 5.5 or 6.7 (those are reserved for unicorn / 67-hands).
    fileprivate func updateTargetLogoVisibility(forBGDisplayString bg: String) {
        let targetMgdl = Double(UserDefaultsRepository.targetLine.value)
        let targetMmolRaw = targetMgdl * GlucoseConversion.mgDlToMmolL

        // Avrunda target till 1 decimal
        let targetMmol = (targetMmolRaw * 10).rounded() / 10

        // Specialvärden som aldrig ska visa target-loggan
        if targetMmol == 5.5 || targetMmol == 6.7 {
            UIView.animate(withDuration: 0.25) {
                self.targetLogoImageView.alpha = 0.0
            }
            return
        }

        let bgValue = Double(bg)
        let shouldShow = bgValue == targetMmol

        UIView.animate(withDuration: 0.25) {
            self.targetLogoImageView.alpha = shouldShow ? 0.25 : 0.0
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

// MARK: - Lightweight BG provider (Nightscout only)

/// Provides recent BG readings to other view‑controllers without UI coupling.
final class BGProvider {

    /// Return the latest `hours` worth of SGV entries (newest‑first).
    /// Each entry’s `date` is already in **seconds**.
    static func fetch(hours: Int = 24 * UserDefaultsRepository.downloadDays.value,
                      completion: @escaping ([ShareGlucoseData]) -> Void) {

        guard IsNightscoutEnabled() else {       // fallback if NS disabled
            completion([])
            return
        }

        var params: [String: String] = [:]
        let iso = ISO8601DateFormatter()
        let since = Calendar.current.date(byAdding: .hour, value: -hours, to: Date())!
        params["count"] = "\(hours * 12 + 12)"                      // a little extra
        params["find[dateString][$gte]"] = iso.string(from: since)
        params["find[type][$ne]"] = "cal"                            // skip calibration rows

        NightscoutUtils.executeRequest(eventType: .sgv, parameters: params) {
            (result: Result<[ShareGlucoseData], Error>) in

            var cleaned: [ShareGlucoseData] = []

            if case .success(let raw) = result {
                var lastAdded = Double.infinity
                for var e in raw {           // NS is newest‑first
                    e.date /= 1000          // ms → s
                    e.date.round()
                    if lastAdded - e.date >= 240 {   // keep ≥4 min apart
                        cleaned.append(e)
                        lastAdded = e.date
                    }
                    if cleaned.count >= hours * 12 { break }
                }
            } else if case .failure(let err) = result {
                LogManager.shared.log(category: .nightscout,
                                      message: "BGProvider fetch error \(err)",
                                      limitIdentifier: "BGProvider fetch error")
            }
            DispatchQueue.main.async { completion(cleaned) }
        }
    }
}
