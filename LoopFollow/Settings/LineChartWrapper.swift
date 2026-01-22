//
//  LineChartView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-26.

//

import SwiftUI
import Charts

import UIKit

struct LineChartStyle {
    var lineColor: NSUIColor
    var showCircles: Bool = false
    var circleRadius: CGFloat = 4
    var circleColor: ((Double) -> NSUIColor)? = nil
}

struct LineChartWrapper: UIViewRepresentable {
    var chartData: [(data: [ChartDataEntry], label: String)]
    var title: String
    var style: LineChartStyle? = nil

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
        
                chartView.drawGridBackgroundEnabled = true
                chartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)

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
            dataSet.drawValuesEnabled = false
            dataSet.mode = .linear

            if let style = style {
                dataSet.setColor(style.lineColor)
                dataSet.drawCirclesEnabled = style.showCircles
                dataSet.circleRadius = style.circleRadius

                if let circleColorProvider = style.circleColor {
                    let colors = item.data.map { entry in
                        circleColorProvider(entry.y)
                    }
                    dataSet.circleColors = colors
                } else {
                    dataSet.setCircleColor(style.lineColor)
                }
            } else {
                dataSet.drawCirclesEnabled = false
            }

            // Stil: tjock linje för primär, dashad för IOB
            if item.label.lowercased().contains("iob") {
                dataSet.lineWidth = 3.0
                dataSet.lineDashLengths = [2, 2]
            } else {
                dataSet.lineWidth = 3.0
            }

            if style == nil {
                if item.label.lowercased().contains("uam") {
                    dataSet.setColor(.systemBlue)
                } else if item.label.lowercased().contains("iob") {
                    dataSet.setColor(.systemBlue)
                } else {
                    dataSet.setColor(.systemPurple)
                }
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

// MARK: - StatsLineChartWrapper (för användardata över tid)

struct StatsLineChartWrapper: UIViewRepresentable {
    var entries: [ChartDataEntry]
    var dates: [Date]
    var title: String
    var style: LineChartStyle

    func makeUIView(context: Context) -> Charts.LineChartView {
        let chartView = Charts.LineChartView()
        chartView.chartDescription.enabled = false
        chartView.legend.enabled = false
        chartView.rightAxis.enabled = false

        chartView.xAxis.labelPosition = .bottom
        chartView.xAxis.granularity = 1
        chartView.xAxis.labelCount = min(6, dates.count)
        chartView.xAxis.valueFormatter = StatsDateAxisFormatter(dates: dates)

        chartView.leftAxis.labelCount = 5

        // Grid – samma look som profilgrafer
        let gridLineColor = NSUIColor.lightGray.withAlphaComponent(0.5)
        chartView.xAxis.gridColor = gridLineColor
        chartView.xAxis.gridLineWidth = 0.5
        chartView.xAxis.gridLineDashLengths = [2, 2]

        chartView.leftAxis.gridColor = gridLineColor
        chartView.leftAxis.gridLineWidth = 0.5
        chartView.leftAxis.gridLineDashLengths = [2, 2]

        chartView.drawGridBackgroundEnabled = true
        chartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)

        chartView.rightAxis.enabled = false

        // Inga gester
        chartView.pinchZoomEnabled = false
        chartView.doubleTapToZoomEnabled = false
        chartView.highlightPerTapEnabled = true
        chartView.highlightPerDragEnabled = false
        chartView.dragEnabled = false
        chartView.scaleXEnabled = false
        chartView.scaleYEnabled = false

        // Marker för att visa värdet för vald punkt
        let marker = StatsMarker()
        marker.chartView = chartView
        chartView.marker = marker
        chartView.drawMarkers = true

        return chartView
    }

    func updateUIView(_ chartView: Charts.LineChartView, context: Context) {
        guard !entries.isEmpty, !dates.isEmpty else {
            chartView.data = nil
            return
        }

        let dataSet = LineChartDataSet(entries: entries, label: title)
        dataSet.drawValuesEnabled = false
        dataSet.mode = .linear
        dataSet.lineWidth = 1.0
        // Dölj vertikal/horisontell highlight-indikator (crosshair)
        dataSet.drawHorizontalHighlightIndicatorEnabled = false
        dataSet.drawVerticalHighlightIndicatorEnabled = true

        // 🔹 Style från LineChartStyle
        dataSet.setColor(style.lineColor)
        dataSet.drawCirclesEnabled = style.showCircles
        dataSet.circleRadius = style.circleRadius

        if let circleColorProvider = style.circleColor {
            let colors = entries.map { entry in
                circleColorProvider(entry.y)
            }
            dataSet.circleColors = colors
        } else {
            dataSet.setCircleColor(style.lineColor)
        }

        let data = LineChartData(dataSet: dataSet)
        chartView.data = data

        // 🔹 Dynamisk X-axel: från första datum till idag
        if let firstDate = dates.first {
            let secondsPerDay: Double = 60 * 60 * 24
            let totalDays = Date().timeIntervalSince(firstDate) / secondsPerDay
            let maxX = max(totalDays, entries.map { $0.x }.max() ?? 0)
            chartView.xAxis.axisMinimum = 0
            chartView.xAxis.axisMaximum = maxX
            chartView.xAxis.labelCount = 6   // lagom antal etiketter
        }

        // 🔹 Dynamisk Y-axel (min/max + lite luft)
        let ys = entries.map { $0.y }
        if let minY = ys.min(), let maxY = ys.max() {
            let range = maxY - minY
            let padding = range == 0 ? max(1, maxY * 0.1) : range * 0.15
            chartView.leftAxis.axisMinimum = minY - padding
            chartView.leftAxis.axisMaximum = maxY + padding
        }

        chartView.notifyDataSetChanged()
    }
}

// Marker som visar värdet för vald datapunkt
final class StatsMarker: MarkerView {
    private let label = UILabel()
    private let insets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
    private let formatter: NumberFormatter

    override init(frame: CGRect) {
        formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1

        super.init(frame: frame)

        backgroundColor = UIColor.secondarySystemBackground
        layer.cornerRadius = 6
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.cgColor
        layer.masksToBounds = true

        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = UIColor.label
        addSubview(label)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func refreshContent(entry: ChartDataEntry, highlight: Highlight) {
        label.text = formatter.string(from: NSNumber(value: entry.y))
        label.sizeToFit()

        let size = CGSize(
            width: label.bounds.width + insets.left + insets.right,
            height: label.bounds.height + insets.top + insets.bottom
        )

        self.bounds = CGRect(origin: .zero, size: size)
        label.frame = CGRect(
            x: insets.left,
            y: insets.top,
            width: label.bounds.width,
            height: label.bounds.height
        )
        layoutIfNeeded()
    }

    override func offsetForDrawing(atPoint point: CGPoint) -> CGPoint {
        // Centrera markern horisontellt och lägg den ovanför punkten
        let size = self.bounds.size
        return CGPoint(x: -size.width / 2, y: -size.height - 100 )
    }
}

// Formatter för datum på X-axeln (yyMM)
class StatsDateAxisFormatter: AxisValueFormatter {
    private let startDate: Date
    private let df: DateFormatter
    private let calendar = Calendar(identifier: .gregorian)

    init(dates: [Date]) {
        // Använd första datumet som startpunkt för x = 0
        self.startDate = dates.first ?? Date()
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "yy-MM"
        self.df = df
    }

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        // value ≈ antal dagar sedan startDate
        let dayOffset = Int(round(value))
        guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else {
            return ""
        }
        return df.string(from: date)
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
