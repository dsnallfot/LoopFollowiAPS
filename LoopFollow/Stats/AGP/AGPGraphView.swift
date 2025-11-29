// LoopFollow
// AGPGraphView.swift

import Charts
import SwiftUI

struct AGPGraphView: UIViewRepresentable {
    let agpData: [AGPDataPoint]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context _: Context) -> UIView {
        let containerView = NonInteractiveContainerView()
        containerView.backgroundColor = .clear

        let chartView = LineChartView()
        chartView.rightAxis.enabled = false
        chartView.leftAxis.enabled = true
        chartView.xAxis.labelPosition = .bottom

        // Enable dashed horizontal gridlines on the right axis
        chartView.rightAxis.drawGridLinesEnabled = true
        //chartView.rightAxis.gridLineDashLengths = [4, 2]
        chartView.rightAxis.gridColor = .label.withAlphaComponent(0.15)
        chartView.rightAxis.gridLineWidth = 0.5

        // Left axis stays hidden
        chartView.leftAxis.drawGridLinesEnabled = false

        // Keep X-axis gridlines disabled
        chartView.xAxis.drawGridLinesEnabled = false

        chartView.rightAxis.valueFormatter = ChartYMMOLValueFormatter()
        
        chartView.leftAxis.valueFormatter = ChartYMMOLValueFormatter()

        // Fix Y-axis to 0–360 mg/dL, which via ChartYMMOLValueFormatter corresponds to 0–20 mmol/L
        let rightAxis = chartView.rightAxis
        rightAxis.axisMinimum = 0
        rightAxis.axisMaximum = 360
        rightAxis.granularity = 72 // 72 mg/dL ≈ 4.0 mmol/L
        rightAxis.granularityEnabled = true
        rightAxis.setLabelCount(6, force: true) // 0, 72, 144, 216, 288, 360
        rightAxis.spaceTop = 0
        rightAxis.spaceBottom = 0

        // Make sure the (hidden) left axis uses the same scale and no extra padding,
        // otherwise Charts will still reserve top/bottom space based on it.
        let leftAxis = chartView.leftAxis
        leftAxis.axisMinimum = 0
        leftAxis.axisMaximum = 360
        leftAxis.granularity = 72 // 72 mg/dL ≈ 4.0 mmol/L
        leftAxis.granularityEnabled = true
        leftAxis.setLabelCount(6, force: true) // 0, 72, 144, 216, 288, 360
        leftAxis.spaceTop = 0
        leftAxis.spaceBottom = 0
        leftAxis.drawLabelsEnabled = true
        leftAxis.drawGridLinesEnabled = false

        // Restore a small, consistent outer padding so axes and labels are fully visible,
        // without affecting the internal 0–360 mg/dL scale.
        chartView.extraTopOffset = 8
        chartView.extraBottomOffset = 8
        chartView.minOffset = 8

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
        guard let chartView = containerView.subviews.first as? LineChartView else { return }
        guard !agpData.isEmpty else { return }
        var p5Entries: [ChartDataEntry] = []
        var p25Entries: [ChartDataEntry] = []
        var p50Entries: [ChartDataEntry] = []
        var p75Entries: [ChartDataEntry] = []
        var p95Entries: [ChartDataEntry] = []

        for point in agpData {
            let x = Double(point.timeOfDay) / 60.0
            p5Entries.append(ChartDataEntry(x: x, y: point.p5))
            p25Entries.append(ChartDataEntry(x: x, y: point.p25))
            p50Entries.append(ChartDataEntry(x: x, y: point.p50))
            p75Entries.append(ChartDataEntry(x: x, y: point.p75))
            p95Entries.append(ChartDataEntry(x: x, y: point.p95))
        }

        let sortedP5 = p5Entries.sorted { $0.x < $1.x }
        let sortedP25 = p25Entries.sorted { $0.x < $1.x }
        let sortedP50 = p50Entries.sorted { $0.x < $1.x }
        let sortedP75 = p75Entries.sorted { $0.x < $1.x }
        let sortedP95 = p95Entries.sorted { $0.x < $1.x }

        guard !sortedP5.isEmpty, !sortedP25.isEmpty, !sortedP50.isEmpty,
              !sortedP75.isEmpty, !sortedP95.isEmpty
        else {
            return
        }
        let p5DataSet = LineChartDataSet(entries: sortedP5, label: "5th")
        p5DataSet.colors = [NSUIColor.systemGray.withAlphaComponent(0.6)]
        p5DataSet.lineWidth = 1.5
        p5DataSet.drawCirclesEnabled = false
        p5DataSet.drawValuesEnabled = false
        p5DataSet.drawFilledEnabled = false
        p5DataSet.mode = .cubicBezier

        let p25DataSet = LineChartDataSet(entries: sortedP25, label: "25th")
        p25DataSet.colors = [NSUIColor.systemBlue.withAlphaComponent(0.7)]
        p25DataSet.lineWidth = 1.5
        p25DataSet.drawCirclesEnabled = false
        p25DataSet.drawValuesEnabled = false
        p25DataSet.drawFilledEnabled = false
        p25DataSet.mode = .cubicBezier

        let p50DataSet = LineChartDataSet(entries: sortedP50, label: "Median")
        p50DataSet.colors = [NSUIColor.systemBlue]
        p50DataSet.lineWidth = 3
        p50DataSet.drawCirclesEnabled = false
        p50DataSet.drawValuesEnabled = false
        p50DataSet.drawFilledEnabled = false
        p50DataSet.mode = .cubicBezier

        let p75DataSet = LineChartDataSet(entries: sortedP75, label: "75th")
        p75DataSet.colors = [NSUIColor.systemBlue.withAlphaComponent(0.7)]
        p75DataSet.lineWidth = 1.5
        p75DataSet.drawCirclesEnabled = false
        p75DataSet.drawValuesEnabled = false
        p75DataSet.drawFilledEnabled = false
        p75DataSet.mode = .cubicBezier

        let p95DataSet = LineChartDataSet(entries: sortedP95, label: "95th")
        p95DataSet.colors = [NSUIColor.systemGray.withAlphaComponent(0.6)]
        p95DataSet.lineWidth = 1.5
        p95DataSet.drawCirclesEnabled = false
        p95DataSet.drawValuesEnabled = false
        p95DataSet.drawFilledEnabled = false
        p95DataSet.mode = .cubicBezier

        // Use a fixed Y-range 0–360 mg/dL to match axis settings (0–20 mmol/L)
        let maxY = 360.0
        let hourMinY = 0.0

        // Target lines (defaults: 70 / 140 mg/dL, converted if needed)
        let defaultTargetLowMgdl: Double = 70
        let defaultTargetHighMgdl: Double = 140
        let targetLow: Double = 70
        let targetHigh: Double = 140
        /*if UserDefaultsRepository.units.value == "mg/dL" {
            targetLow = defaultTargetLowMgdl
            targetHigh = defaultTargetHighMgdl
        } else {
            // Convert mg/dL → mmol/L
            targetLow = defaultTargetLowMgdl * GlucoseConversion.mgDlToMmolL
            targetHigh = defaultTargetHighMgdl * GlucoseConversion.mgDlToMmolL
        }*/

        var hourLines: [ChartDataEntry] = []
        for hour in 0 ... 24 {
            let x = Double(hour)
            hourLines.append(ChartDataEntry(x: x, y: hourMinY))
            hourLines.append(ChartDataEntry(x: x, y: maxY))
            if hour < 24 {
                hourLines.append(ChartDataEntry(x: x + 0.0001, y: hourMinY))
            }
        }

        let hourLinesDataSet = LineChartDataSet(entries: hourLines, label: "Hours")
        hourLinesDataSet.colors = [NSUIColor.label.withAlphaComponent(0.15)]
        hourLinesDataSet.lineWidth = 0.5
        hourLinesDataSet.drawCirclesEnabled = false
        hourLinesDataSet.drawValuesEnabled = false
        hourLinesDataSet.drawFilledEnabled = false

        // Horizontal target lines
        let targetLowEntries = [
            ChartDataEntry(x: 0, y: targetLow),
            ChartDataEntry(x: 24, y: targetLow),
        ]
        let targetHighEntries = [
            ChartDataEntry(x: 0, y: targetHigh),
            ChartDataEntry(x: 24, y: targetHigh),
        ]

        let targetLowDataSet = LineChartDataSet(entries: targetLowEntries, label: "Target Low")
        targetLowDataSet.colors = [NSUIColor.systemRed.withAlphaComponent(0.8)]
        targetLowDataSet.lineWidth = 1
        targetLowDataSet.drawCirclesEnabled = false
        targetLowDataSet.drawValuesEnabled = false
        targetLowDataSet.drawFilledEnabled = false

        let targetHighDataSet = LineChartDataSet(entries: targetHighEntries, label: "Target High")
        targetHighDataSet.colors = [NSUIColor.systemPurple.withAlphaComponent(0.8)]
        targetHighDataSet.lineWidth = 1
        targetHighDataSet.drawCirclesEnabled = false
        targetHighDataSet.drawValuesEnabled = false
        targetHighDataSet.drawFilledEnabled = false

        let data = LineChartData()
        data.append(hourLinesDataSet)
        data.append(targetLowDataSet)
        data.append(targetHighDataSet)
        data.append(p5DataSet)
        data.append(p25DataSet)
        data.append(p50DataSet)
        data.append(p75DataSet)
        data.append(p95DataSet)
        

        chartView.data = data
        chartView.notifyDataSetChanged()
        chartView.setNeedsDisplay()
    }
}
