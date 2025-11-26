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
        containerView.backgroundColor = .systemBackground

        let chartView = BarChartView()
        chartView.backgroundColor = .systemBackground
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
        var labelEntries: [BarChartDataEntry] = []
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

            // Label entry: place the value label at the vertical center of the "In Range" segment.
            // The "In Range" segment starts after veryLow + low and has height = inRange.
            let belowInRange = point.veryLow + point.low
            let centerOfInRange = belowInRange + (point.inRange / 2.0 - 5)

            let labelEntry = BarChartDataEntry(
                x: Double(index),
                y: centerOfInRange,
                data: NSNumber(value: point.inRange)
            )
            labelEntries.append(labelEntry)

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

        // Transparent dataset used only for drawing centered "In Range" percentage labels
        let labelSet = BarChartDataSet(entries: labelEntries, label: "")
        labelSet.colors = [UIColor.clear]
        labelSet.drawValuesEnabled = true
        labelSet.valueFont = .systemFont(ofSize: 10, weight: .semibold)
        labelSet.valueTextColor = .white
        labelSet.valueFormatter = InRangeValueFormatter()

        let data = BarChartData(dataSets: [stackedSet, labelSet])
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
        return String(format: "%.0f%%", value)
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
            return String(format: "%.0f%%", inRange)
        } else {
            // Fallback to the raw value if data is missing
            if value < 5.0 {
                return ""
            }
            return String(format: "%.0f%%", value)
        }
    }
}
