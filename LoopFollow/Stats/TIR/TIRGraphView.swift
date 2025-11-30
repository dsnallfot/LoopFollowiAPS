// LoopFollow
// TIRGraphView.swift

import Charts
import SwiftUI
import UIKit

struct TIRGraphView: UIViewRepresentable {
    let tirData: [TIRDataPoint]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context _: Context) -> UIView {
        let containerView = NonInteractiveContainerView()
        containerView.backgroundColor = .clear

        let chartView = BarChartView()
        chartView.backgroundColor = .clear
        chartView.rightAxis.enabled = false
        chartView.leftAxis.enabled = true
        chartView.xAxis.labelPosition = .bottom
        chartView.xAxis.granularity = 1.0
        chartView.leftAxis.axisMinimum = 0.0
        chartView.leftAxis.axisMaximum = 100.0
        chartView.leftAxis.valueFormatter = PercentageAxisValueFormatter()
        chartView.leftAxis.labelCount = 5
        chartView.rightAxis.drawGridLinesEnabled = false
        chartView.leftAxis.drawGridLinesEnabled = true
        chartView.leftAxis.gridLineDashLengths = [2, 2]
        chartView.xAxis.drawGridLinesEnabled = false
        chartView.legend.enabled = false
        chartView.chartDescription.enabled = false
        chartView.isUserInteractionEnabled = false

        containerView.addSubview(chartView)
        chartView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chartView.topAnchor.constraint(equalTo: containerView.topAnchor),
            chartView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            chartView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            chartView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        return containerView
    }

    class Coordinator {}

    func updateUIView(_ containerView: UIView, context _: Context) {
        guard let chartView = containerView.subviews.first as? BarChartView else { return }
        guard !tirData.isEmpty else { return }

        var stackedEntries: [BarChartDataEntry] = []
        var veryLowLabelEntries: [BarChartDataEntry] = []
        var lowLabelEntries: [BarChartDataEntry] = []
        var inRangeLabelEntries: [BarChartDataEntry] = []
        var highLabelEntries: [BarChartDataEntry] = []
        var veryHighLabelEntries: [BarChartDataEntry] = []
        var xAxisLabels: [String] = []

        for (index, point) in tirData.enumerated() {
            // Stacked bar (very low, low, in range, high, very high)
            let stackedEntry = BarChartDataEntry(
                x: Double(index),
                yValues: [
                    point.veryLow,
                    point.low,
                    point.inRange,
                    point.high,
                    point.veryHigh,
                ]
            )
            stackedEntries.append(stackedEntry)

            // Label entries: place value labels at the vertical center of each segment,
            // with a small upward visual offset. We clamp so att etiketten aldrig hamnar
            // under 0-linjen eller under segmentets botten.
            let labelOffset = 5.5

            // Very Low segment
            let rawCenterVeryLow = point.veryLow / 2.0 - labelOffset
            let centerVeryLow = max(rawCenterVeryLow, 0)
            let veryLowLabelEntry = BarChartDataEntry(
                x: Double(index),
                y: centerVeryLow,
                data: NSNumber(value: point.veryLow)
            )
            veryLowLabelEntries.append(veryLowLabelEntry)

            // Low segment
            let lowBottom = point.veryLow
            let rawCenterLow = lowBottom + (point.low / 2.0) - labelOffset
            let centerLow = max(rawCenterLow, lowBottom)
            let lowLabelEntry = BarChartDataEntry(
                x: Double(index),
                y: centerLow ,
                data: NSNumber(value: point.low)
            )
            lowLabelEntries.append(lowLabelEntry)

            // In Range segment
            let inRangeBottom = point.veryLow + point.low
            let rawCenterOfInRange = inRangeBottom + (point.inRange / 2.0) - labelOffset
            let centerOfInRange = max(rawCenterOfInRange, inRangeBottom + 1.0)
            let inRangeLabelEntry = BarChartDataEntry(
                x: Double(index),
                y: centerOfInRange,
                data: NSNumber(value: point.inRange)
            )
            inRangeLabelEntries.append(inRangeLabelEntry)

            // High segment
            let highBottom = inRangeBottom + point.inRange
            let rawCenterHigh = highBottom + (point.high / 2.0) - labelOffset
            let centerHigh = max(rawCenterHigh, highBottom + 1.0)
            let highLabelEntry = BarChartDataEntry(
                x: Double(index),
                y: centerHigh,
                data: NSNumber(value: point.high)
            )
            highLabelEntries.append(highLabelEntry)

            // Very High segment
            let veryHighBottom = highBottom + point.high
            let rawCenterVeryHigh = veryHighBottom + (point.veryHigh / 2.0) - labelOffset
            let centerVeryHigh = max(rawCenterVeryHigh, veryHighBottom + 1.0)
            let veryHighLabelEntry = BarChartDataEntry(
                x: Double(index),
                y: centerVeryHigh,
                data: NSNumber(value: point.veryHigh)
            )
            veryHighLabelEntries.append(veryHighLabelEntry)

            xAxisLabels.append(point.period.rawValue)
        }

        // Main stacked dataset for the TIR distribution
        let stackedSet = BarChartDataSet(entries: stackedEntries, label: "Time in Range")
        stackedSet.colors = [
            UIColor.systemRed.withAlphaComponent(0.7),
            UIColor.systemOrange.withAlphaComponent(0.7),
            UIColor.systemGreen.withAlphaComponent(0.7),
            UIColor.systemBlue.withAlphaComponent(0.7),
            UIColor.systemPurple.withAlphaComponent(0.7),
        ]
        stackedSet.stackLabels = ["Very Low", "Low", "In Range", "High", "Very High"]
        stackedSet.drawValuesEnabled = false

        // Transparent datasets used only for drawing centered percentage labels per segment
        let veryLowLabelSet = BarChartDataSet(entries: veryLowLabelEntries, label: "")
        veryLowLabelSet.colors = [UIColor.clear]
        veryLowLabelSet.drawValuesEnabled = true
        veryLowLabelSet.valueFont = .systemFont(ofSize: 8, weight: .semibold)
        veryLowLabelSet.valueTextColor = .white.withAlphaComponent(0.8)
        veryLowLabelSet.valueFormatter = InRangeValueFormatter()

        let lowLabelSet = BarChartDataSet(entries: lowLabelEntries, label: "")
        lowLabelSet.colors = [UIColor.clear]
        lowLabelSet.drawValuesEnabled = true
        lowLabelSet.valueFont = .systemFont(ofSize: 8, weight: .semibold)
        lowLabelSet.valueTextColor = .white.withAlphaComponent(0.8)
        lowLabelSet.valueFormatter = InRangeValueFormatter()

        let inRangeLabelSet = BarChartDataSet(entries: inRangeLabelEntries, label: "")
        inRangeLabelSet.colors = [UIColor.clear]
        inRangeLabelSet.drawValuesEnabled = true
        inRangeLabelSet.valueFont = .systemFont(ofSize: 8, weight: .semibold)
        inRangeLabelSet.valueTextColor = .white.withAlphaComponent(0.8)
        inRangeLabelSet.valueFormatter = InRangeValueFormatter()

        let highLabelSet = BarChartDataSet(entries: highLabelEntries, label: "")
        highLabelSet.colors = [UIColor.clear]
        highLabelSet.drawValuesEnabled = true
        highLabelSet.valueFont = .systemFont(ofSize: 8, weight: .semibold)
        highLabelSet.valueTextColor = .white.withAlphaComponent(0.8)
        highLabelSet.valueFormatter = InRangeValueFormatter()

        let veryHighLabelSet = BarChartDataSet(entries: veryHighLabelEntries, label: "")
        veryHighLabelSet.colors = [UIColor.clear]
        veryHighLabelSet.drawValuesEnabled = true
        veryHighLabelSet.valueFont = .systemFont(ofSize: 8, weight: .semibold)
        veryHighLabelSet.valueTextColor = .white.withAlphaComponent(0.8)
        veryHighLabelSet.valueFormatter = InRangeValueFormatter()

        let data = BarChartData(dataSets: [
            stackedSet,
            veryLowLabelSet,
            lowLabelSet,
            inRangeLabelSet,
            highLabelSet,
            veryHighLabelSet,
        ])
        data.barWidth = 0.6

        chartView.data = data

        chartView.xAxis.valueFormatter = IndexAxisValueFormatter(values: xAxisLabels)
        chartView.xAxis.labelRotationAngle = 0
        chartView.xAxis.labelCount = xAxisLabels.count

        chartView.notifyDataSetChanged()
    }
}

class PercentageAxisValueFormatter: AxisValueFormatter {
    func stringForValue(_ value: Double, axis _: AxisBase?) -> String {
        return String(format: "%.0f %%", value)
    }
}

class InRangeValueFormatter: ValueFormatter {
     func stringForValue(
        _ value: Double,
        entry: ChartDataEntry,
        dataSetIndex: Int,
        viewPortHandler: ViewPortHandler?
    ) -> String {
        // We stored the "In Range" percentage in entry.data as NSNumber
        if let number = entry.data as? NSNumber {
            let inRange = number.doubleValue
            // Hide labels for very small segments to avoid clutter
            if inRange < 5.0 {
                return ""
            }
            return String(format: "%.0f %%", inRange)
        } else {
            // Fallback to the raw value if data is missing
            if value < 5.0 {
                return ""
            }
            return String(format: "%.0f %%", value)
        }
    }
}
