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
        if bgData.count > 0 {
            var lastDayOfData = bgData
            let graphHours = 24 * UserDefaultsRepository.downloadDays.value
            // If we loaded more than 1 day of data, only use the last day for the stats
            if graphHours > 24 {
                let oneDayAgo = dateTimeUtils.getTimeIntervalNHoursAgo(N: 24)
                var startIndex = 0
                while startIndex < bgData.count && bgData[startIndex].date < oneDayAgo {
                    startIndex += 1
                }
                lastDayOfData = Array(bgData.dropFirst(startIndex))
            }
            
            let stats = StatsData(bgData: lastDayOfData)
            
            statsLowPercent.text = String(format:"%.1f%", stats.percentLow) + "%"
            statsInRangePercent.text = String(format:"%.1f%", stats.percentRange) + "%"
            statsHighPercent.text = String(format:"%.1f%", stats.percentHigh) + "%"
            statsAvgBG.text = bgUnits.toDisplayUnits(String(format:"%.0f%", stats.avgBG)).replacingOccurrences(of: ",", with: ".")
            if UserDefaultsRepository.useIFCC.value {
                statsEstA1C.text = String(format:"%.0f%", stats.a1C)
            }
            else
            {
                statsEstA1C.text = String(format:"%.1f%", stats.a1C)
            }
            statsStdDev.text = String(format:"%.2f%", stats.stdDev)
            
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
            
            /*
            let redHue: CGFloat = 0.0 / 360.0       // 0 degrees
            let greenHue: CGFloat = 120.0 / 360.0   // 120 degrees
            let purpleHue: CGFloat = 270.0 / 360.0  // 270 degrees
            var hue = greenHue
            
            if pieData[i].name == "high" {
                //purple
                hue = purpleHue
                hue = UIColor(named: "ZT")
            } else if pieData[i].name == "low" {
                //red
                hue = redHue
            } else {
                //green
                hue = greenHue
            }
            
            let color = UIColor(hue: hue, saturation: 0.5, brightness: 0.8, alpha: 0.9)
            colors.append(color)
            */
            
            /*
            //Another way to do this - use the colors used for high and low via dynamic BG color
             
             if pieData[i].name == "high" {
                 let color = setBGColor(Int(UserDefaultsRepository.alertUrgentHighBG.value))
                 colors.append(color)
             } else if pieData[i].name == "low" {
                 let color = setBGColor(Int(UserDefaultsRepository.alertUrgentLowBG.value))
                 print("Auggie: user default alertUrgentlowBG \(UserDefaultsRepository.alertUrgentLowBG.value)")
                 colors.append(color)
             } else {
                 let color = setBGColor(Int(UserDefaultsRepository.targetLine.value))
                 colors.append(color)
             }
             
             */
            
            
            if pieData[i].name == "high" {
                if let color = UIColor(named: "ZT")?.withAlphaComponent(0.8) { //? }.withAlphaComponent(0.8) {
                    colors.append(color)
                }
            } else if pieData[i].name == "low" {
                if let color = UIColor(named: "LoopRed")?.withAlphaComponent(0.8) { //? }.withAlphaComponent(0.8) {
                    colors.append(color)
                }
            } else {
                if let color = UIColor(named: "LoopGreen")?.withAlphaComponent(0.8) { //? }.withAlphaComponent(0.8) {
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
