//
//  StatsView.swift
//  LoopFollow
//
//  Created by Jon Fawcett on 6/23/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//

import Foundation
import Charts
import UIKit


extension MainViewController {

    func updateStats()
    {
        func minutesToHHMM(_ minutes: Double) -> String {
            let total = max(0, Int(ceil(minutes)))
            let h = total / 60
            let m = total % 60
            return String(format: "%02d:%02d", h, m)
        }

        func computeTirNeededString() -> String {
            
            // Use BG data from 00:00 (local) to now
            let now = Date()
            let cal = Calendar.current
            let startOfToday = cal.startOfDay(for: now)
            let startTI = startOfToday.timeIntervalSince1970
            let nowTI = now.timeIntervalSince1970
            // Target: 50% in range for *today's actual length* (DST-safe: 23h/24h/25h days)
            let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday)
            let totalDayMinutes: Double = {
                if let startOfTomorrow {
                    return max(0.0, (startOfTomorrow.timeIntervalSince1970 - startTI) / 60.0)
                }
                return 24.0 * 60.0
            }()
            let targetMinutes: Double = totalDayMinutes * 0.5
            let todayOfData = bgData.filter { $0.date >= startTI && $0.date <= nowTI }
            guard todayOfData.count > 0 else {
                return ""
            }

            // Percent in range for today so far
            let statsToday = StatsData(bgData: todayOfData)
            let fractionInRange = Double(max(0.0, min(1.0, statsToday.percentRange / 100.0)))

            // Translate percent into time-in-range for today so far
            let elapsedMinutes = max(0.0, (nowTI - startTI) / 60.0)
            let inRangeMinutesSoFar = elapsedMinutes * fractionInRange

            // Remaining time today (DST-safe totalDayMinutes)
            let remainingMinutes = max(0.0, totalDayMinutes - elapsedMinutes)

            // How much in-range is still needed to hit 12h by midnight
            let neededMinutes = targetMinutes - inRangeMinutesSoFar

            if neededMinutes <= 0 {
                return "✅"
            }

            if neededMinutes > remainingMinutes {
                return "🚫"
            }

            return minutesToHHMM(neededMinutes)
        }
        if bgData.count > 0 {
            // Choose data scope for stats
            let statsSourceData: [ShareGlucoseData]

            switch statsScopeMode {
            case .today:
                // Today 00:00 (local) -> now
                let now = Date()
                let startOfToday = Calendar.current.startOfDay(for: now).timeIntervalSince1970
                let nowTI = now.timeIntervalSince1970
                statsSourceData = bgData.filter { $0.date >= startOfToday && $0.date <= nowTI }

            case .schoolday:
                // Schoolday: 08:00 -> 16:00 (or 08:00 -> now if before 16:00).
                // If before 08:00: show N/A for all values.
                let now = Date()
                let cal = Calendar.current
                let startOfToday = cal.startOfDay(for: now)

                let start08 = cal.date(bySettingHour: 8, minute: 0, second: 0, of: startOfToday)
                    ?? startOfToday.addingTimeInterval(8 * 3600)
                let end16 = cal.date(bySettingHour: 16, minute: 0, second: 0, of: startOfToday)
                    ?? startOfToday.addingTimeInterval(16 * 3600)

                if now < start08 {
                    statsSourceData = []
                } else {
                    let end = min(now, end16)
                    let startTI = start08.timeIntervalSince1970
                    let endTI = end.timeIntervalSince1970
                    statsSourceData = bgData.filter { $0.date >= startTI && $0.date <= endTI }
                }

            case .period:
                // Existing behavior: use the requested download window (last 24h if >1 day loaded)
                var lastDayOfData = bgData
                let graphHours = 24 * UserDefaultsRepository.downloadDays.value
                if graphHours > 24 {
                    let oneDayAgo = dateTimeUtils.getTimeIntervalNHoursAgo(N: 24)
                    var startIndex = 0
                    while startIndex < bgData.count && bgData[startIndex].date < oneDayAgo {
                        startIndex += 1
                    }
                    lastDayOfData = Array(bgData.dropFirst(startIndex))
                }
                statsSourceData = lastDayOfData
            }

            // If no data in the chosen scope, don't update the stats UI
            guard statsSourceData.count > 0 else {
                statsLowPercent.text = "N/A"
                statsInRangePercent.text = "N/A"
                statsHighPercent.text = "N/A"
                statsAvgBG.text = "N/A"
                statsEstA1C.text = "N/A"
                statsStdDev.text = "N/A"

                // Clear pie
                statsPieChart.data = nil
                statsPieChart.notifyDataSetChanged()
                return
            }

            let stats = StatsData(bgData: statsSourceData)
            // TIR needed (today 00:00 -> now) to reach 50% TIR (12h) by midnight
            let tirNeededString = computeTirNeededString()
            self.infoManager.updateInfoData(type: .tirNeeded, value: tirNeededString)
            
            statsLowPercent.text = String(format:"%.1f", stats.percentLow) + "%"
            statsInRangePercent.text = String(format:"%.1f", stats.percentRange) + "%"
            statsHighPercent.text = String(format:"%.1f", stats.percentHigh) + "%"

            statsAvgBG.text = Localizer.toDisplayUnits(String(format:"%.0f", stats.avgBG)).replacingOccurrences(of: ",", with: ".")

            if UserDefaultsRepository.useIFCC.value {
                // Keep legacy UI behavior: still show % for A1C as before (even if IFCC might ideally be mmol/mol)
                statsEstA1C.text = String(format:"%.0f", stats.a1C) + "%"
            } else {
                statsEstA1C.text = String(format:"%.1f", stats.a1C) + "%"
            }

            statsStdDev.text = String(format:"%.1f", stats.stdDev)
            
            createStatsPie(pieData: stats.pie)
        }
        
    }
    
    func createStatsPie(pieData: [DataStructs.pieData]) {
        statsPieChart.legend.enabled = false
        statsPieChart.drawEntryLabelsEnabled = false
        statsPieChart.drawHoleEnabled = false
        statsPieChart.rotationEnabled = false
        
        var chartEntry = [PieChartDataEntry]()
        var colors = [UIColor]()
        
        for i in 0..<pieData.count{
            var slice = Double(pieData[i].value)
            if slice == 0 { slice = 0.1 }
            let value = PieChartDataEntry(value: slice)
            chartEntry.append(value)
            
            if pieData[i].name == "high" {
                if UserDefaultsRepository.colorBGText.value {
                    let color = UIColor.systemPurple.withAlphaComponent(0.8)
                        colors.append(color)
                } else {
                    if let color = UIColor(named: "LoopYellow")?.withAlphaComponent(0.8) {
                        colors.append(color)
                    }
                }
                
            } else if pieData[i].name == "low" {
                if let color = UIColor(named: "LoopRed")?.withAlphaComponent(0.8) {
                    colors.append(color)
                }
            } else {
                if let color = UIColor(named: "LoopGreen")?.withAlphaComponent(0.8) {
                    colors.append(color)
                }
            }
        }
        
        let set = PieChartDataSet(entries: chartEntry, label: "")
        
        
        
        set.drawIconsEnabled = false
        set.sliceSpace = 2
        set.drawValuesEnabled = false
        set.valueLineWidth = 0
        set.formLineWidth = 0
        set.sliceSpace = 0
        
        set.colors.removeAll()
        if colors.count > 0 {
            for i in 0..<colors.count{
                set.addColor(colors[i])
            }
        }
        
        let data = PieChartData(dataSet: set)
        statsPieChart.data = data
        
    }

}
