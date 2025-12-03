//
//  LineChartView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-26.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import SwiftUI
import Charts

struct LineChartWrapper: UIViewRepresentable {
    var chartData: [(data: [ChartDataEntry], label: String)]
    var title: String

    func makeUIView(context: Context) -> Charts.LineChartView {
        let chartView = Charts.LineChartView()
                chartView.chartDescription.enabled = false
                chartView.legend.enabled = false
                chartView.rightAxis.enabled = false
                chartView.xAxis.labelPosition = .bottom
                chartView.xAxis.granularity = 1
                chartView.xAxis.valueFormatter = HourAxisFormatter()
                chartView.xAxis.labelCount = 7 // Ensures "24" is included
                chartView.xAxis.axisMinimum = 0
                chartView.xAxis.axisMaximum = 24 // Extend X-axis to ensure "24" appears
                
                chartView.leftAxis.axisMinimum = 0
                chartView.leftAxis.labelCount = 5
                chartView.leftAxis.valueFormatter = NoZeroYAxisFormatter(decimalPlaces: getDecimalPlaces(for: title))

                // 🔹 Make X and Y grid lines dashed/dotted and more subtle
                let gridLineColor = NSUIColor.lightGray.withAlphaComponent(0.5) // Faint gray

                chartView.xAxis.gridColor = gridLineColor
                chartView.xAxis.gridLineWidth = 0.5 // Thin grid lines
                chartView.xAxis.gridLineDashLengths = [2, 2] // Dotted effect

                chartView.leftAxis.gridColor = gridLineColor
                chartView.leftAxis.gridLineWidth = 0.5
                chartView.leftAxis.gridLineDashLengths = [2, 2] // Dotted effect

                chartView.rightAxis.enabled = false // Hide right Y-axis

        // Disable zooming and interactions
        chartView.pinchZoomEnabled = false
        chartView.doubleTapToZoomEnabled = false
        chartView.highlightPerTapEnabled = false
        chartView.highlightPerDragEnabled = false
        chartView.dragEnabled = false
        chartView.scaleXEnabled = false
        chartView.scaleYEnabled = false

        return chartView
    }

    func updateUIView(_ chartView: Charts.LineChartView, context: Context) {
        let dataSets = chartData.map { item -> LineChartDataSet in
            let stepEntries = createStepChartData(from: item.data)
            let dataSet = LineChartDataSet(entries: stepEntries, label: item.label)
            dataSet.drawCirclesEnabled = false
            dataSet.drawValuesEnabled = false
            dataSet.mode = .linear

            // Stil: tjock linje för primär, dashad för IOB
            if item.label.lowercased().contains("iob") {
                dataSet.lineWidth = 2.0
                dataSet.lineDashLengths = [2, 2]
            } else {
                dataSet.lineWidth = 3.0
            }

            // Auto assign color (you can make this customizable later)
            if item.label.lowercased().contains("uam") {
                dataSet.setColor(.systemBlue)
            } else if item.label.lowercased().contains("iob") {
                dataSet.setColor(.systemTeal)
            } else {
                dataSet.setColor(.systemPurple)
            }

            return dataSet
        }

        let lineChartData = LineChartData(dataSets: dataSets)
        chartView.data = lineChartData

        chartView.leftAxis.valueFormatter = NoZeroYAxisFormatter(decimalPlaces: getDecimalPlaces(for: title))
        chartView.notifyDataSetChanged()
    }

    /// Determines the number of decimal places for the Y-axis based on the section title
    private func getDecimalPlaces(for title: String) -> Int {
        switch title {
        case "Basal", "SMB Limits":
            return 2 // Show 2 decimal places
        case "Targets", "Insulin Sensitivity Factor", "Carb Sensitivity Factor":
            return 1 // Show 1 decimal place
        case "Carb Ratios", "Minimum Carbs grams/hour":
            return 0 // No decimal places
        default:
            return 0 // Default to no decimals
        }
    }

    /// Converts standard chart data into step-like data
    private func createStepChartData(from data: [ChartDataEntry]) -> [ChartDataEntry] {
        var stepData: [ChartDataEntry] = []

        for i in 0..<data.count {
            let entry = data[i]
            stepData.append(entry) // original point

            // Insert horizontal step to next x, using current y
            if i < data.count - 1 {
                let nextEntry = data[i + 1]
                stepData.append(ChartDataEntry(x: nextEntry.x, y: entry.y))
            }
        }

        // 🟣 Add final point at x=24 to stretch the line
        if let last = data.last, last.x < 24 {
            stepData.append(ChartDataEntry(x: 24.0, y: last.y))
        }

        return stepData
    }
}

// Custom X-Axis Formatter for hours (00, 04, 08, ..., 24)
class HourAxisFormatter: AxisValueFormatter {
    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let hour = Int(value)
        return hour == 24 ? "24" : String(format: "%02d", hour)
    }
}

// Custom Y-Axis Formatter to handle dynamic decimal places and hide 0 value
class NoZeroYAxisFormatter: AxisValueFormatter {
    var decimalPlaces: Int = 0 // Default

    init(decimalPlaces: Int = 0) {
        self.decimalPlaces = decimalPlaces
    }

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        guard value != 0 else { return "" } // Hide 0
        return String(format: "%.\(decimalPlaces)f", value)
    }
}
