//
//  TrioPreferencesView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-23.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import SwiftUI
import UIKit
import Charts

@available(iOS 16.0, *)
private struct PreferenceKeyItem: Identifiable {
    let key: String
    var id: String { key }
}
private struct PinnedSearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(spacing: 0) {
            UISearchBarRepresentable(text: $text, placeholder: placeholder)
                .frame(height: 44)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 2)

            //Divider()
                //.overlay(Color(UIColor.separator))
        }
        .background(Color.clear)
    }
}

private struct UISearchBarRepresentable: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let sb = UISearchBar(frame: .zero)
        sb.delegate = context.coordinator
        sb.placeholder = placeholder
        sb.autocapitalizationType = .none
        sb.autocorrectionType = .no
        sb.searchBarStyle = .minimal
        sb.returnKeyType = .done
        sb.enablesReturnKeyAutomatically = false
        if #available(iOS 13.0, *) {
            sb.searchTextField.backgroundColor = UIColor.systemGray.withAlphaComponent(0.1)
        }
        return sb
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            // Keep binding in sync if user taps away
            text = searchBar.text ?? ""
        }
    }
}

@available(iOS 16.0, *)
struct TrioPreferencesView: View {
    @ObservedObject var viewModel = TrioPreferencesViewModel()
    @State private var searchText: String = ""
    @State private var selectedPreferenceKeyForLog: PreferenceKeyItem?

    var filteredPreferences: [PreferenceEntry] {
        if searchText.isEmpty {
            return viewModel.preferences
        } else {
            return viewModel.preferences.filter { $0.key.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                PinnedSearchBar(text: $searchText, placeholder: "Sök inställningar...")

                List(filteredPreferences) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(entry.key)
                                .font(.headline)
                            Spacer()
                            Text(entry.value)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 6) {
                            if let last = viewModel.latestChangeDate(forKey: entry.key) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.purple)

                                Text("Senast ändrad: \(last.formatted(.dateTime.year().month().day()))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                    .onTapGesture {
                        selectedPreferenceKeyForLog = PreferenceKeyItem(key: entry.key)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .sheet(item: $selectedPreferenceKeyForLog) { item in
                ZStack {
                    // Lägg till bakgrunden här för att fylla hela modalen
                    ThemeBackground()
                        .ignoresSafeArea()
                    
                    // Din wrapper ovanpå bakgrunden
                    SettingsLogModal(initialSearchText: item.key)
                }
                // Om du vill att handtaget högst upp på sheetet ska synas tydligt:
                //.presentationDragIndicator(.visible)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: AnalyzeDeviationsView(viewModel: viewModel)) {
                        Image(systemName: "lightbulb.max")
                    }
                    .accessibilityLabel("Oref utvärdering")
                }
            }
        }
    }
}

@available(iOS 16.0, *)
private struct SettingsLogModal: UIViewControllerRepresentable {
    let initialSearchText: String

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = TrioSettingsLogView(initialSearchText: initialSearchText)
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        if let vc = uiViewController.viewControllers.first as? TrioSettingsLogView {
            vc.setSearchTextAndFilter(initialSearchText)
        }
    }
}


@available(iOS 16.0, *)
struct AnalyzeDeviationsView: View {

    enum ChartMode: String, CaseIterable, Identifiable {
        case dev30m = "Dev 30m"
        case iobCob = "COB • IOB"
        var id: String { rawValue }
    }

    @ObservedObject var viewModel: TrioPreferencesViewModel
    @State private var mode: ChartMode = .dev30m

    private var devRows: [TrioPreferencesViewModel.DevPoint] {
        viewModel.devPoints.sorted(by: { $0.date > $1.date })
    }

    private var iobCobRows: [TrioPreferencesViewModel.IobCobPoint] {
        viewModel.iobCobPoints.sorted(by: { $0.date > $1.date })
    }

    private var timeFormatter: DateFormatter {
        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "HH:mm"
        return df
    }


    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(spacing: 12) {
                // Chart container (300p)
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $mode) {
                        ForEach(ChartMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 4)

                    if viewModel.devIsLoading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Hämtar device status…")
                        }
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    } else if let err = viewModel.devLastError {
                        Text("Fel: \(err)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    } else {
                        if mode == .dev30m {
                            Text("Dev (30m +/- mmol/L)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        } else {
                            HStack {
                                Text("COB (g)")
                                    .foregroundColor(.orange)
                                Spacer()
                                Text("IOB (E)")
                                    .foregroundColor(.teal)
                            }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }

                    if mode == .dev30m {
                        AnalyzeDeviationsLineChart(points: devRows.map { ($0.date, $0.dev) })
                            .frame(height: 260)
                    } else {
                        AnalyzeIobCobLineChart(points: iobCobRows.map { ($0.date, $0.iob, $0.cob) })
                            .frame(height: 260)
                    }
                }
                .padding(12)
                .frame(height: 340)
                .themedCardBackground(opacity: 0.12)
                .padding(.horizontal, 12)

                // Table below the chart
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if mode == .dev30m {
                            ForEach(devRows) { row in
                                HStack {
                                    Text(String(format: "%+.1f mmol/L", row.dev))
                                        .font(.body)
                                    Spacer()
                                    Text(timeFormatter.string(from: row.date))
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .themedCardBackground(opacity: 0.10)
                            }
                        } else {
                            ForEach(iobCobRows) { row in
                                HStack {
                                    Text(String(format: "COB: %.0f g • IOB: %.2f E", row.cob, row.iob))
                                        .font(.body)
                                    Spacer()
                                    Text(timeFormatter.string(from: row.date))
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .themedCardBackground(opacity: 0.10)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
            }
        }
        .navigationTitle("Utvärdering oref (24h)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Ad hoc fetch: latest 600 device status, then window to last 24h
            viewModel.fetchDevIobCobLast24h(count: 600)
        }
    }
}

@available(iOS 16.0, *)
private struct AnalyzeDeviationsLineChart: UIViewRepresentable {

    /// (date, value)
    let points: [(Date, Double)]

    func makeUIView(context: Context) -> LineChartView {
        let v = LineChartView()

        v.legend.enabled = false
        v.chartDescription.enabled = false
        v.rightAxis.enabled = false
        v.minOffset = 8
        // Add a bit of space on the right so the last x-label ("nu") doesn't clip
        v.extraRightOffset = 14

        v.pinchZoomEnabled = true
        v.doubleTapToZoomEnabled = true
        v.scaleXEnabled = true
        v.scaleYEnabled = false
        v.dragEnabled = true

        v.highlightPerTapEnabled = false
        v.highlightPerDragEnabled = false
        v.drawMarkers = false

        // Transparent so ThemeBackground shows through
        v.backgroundColor = .clear
        v.isOpaque = false

        // X axis
        let xAxis = v.xAxis
        xAxis.labelPosition = .bottom
        //xAxis.avoidFirstLastClippingEnabled = true
        xAxis.drawGridLinesEnabled = true
        xAxis.granularityEnabled = true
        xAxis.granularity = 3 * 60 * 60 // 2h ticks by default

        // Left axis
        let yAxis = v.leftAxis
        yAxis.drawGridLinesEnabled = true
        yAxis.drawZeroLineEnabled = true

        // Make the 0-line stand out more than other grid lines
        yAxis.zeroLineWidth = 1.5
        yAxis.zeroLineColor = UIColor.label.withAlphaComponent(0.75)

        yAxis.axisMinimum = -12
        yAxis.axisMaximum = 12
        yAxis.granularityEnabled = true
        yAxis.granularity = 2

        return v
    }

    func updateUIView(_ uiView: LineChartView, context: Context) {
        guard !points.isEmpty else {
            uiView.data = nil
            uiView.setNeedsDisplay()
            return
        }

        // Ensure points are sorted by time (oldest -> newest)
        let sorted = points.sorted(by: { $0.0 < $1.0 })

        // Define a 24h rolling window ending at the newest point
        let endDate = sorted.last!.0
        let startDate = endDate.addingTimeInterval(-24 * 60 * 60)

        // Build entries where x is seconds since startDate
        var entries: [ChartDataEntry] = []
        entries.reserveCapacity(sorted.count)

        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for (d, v) in sorted {
            // Keep points within the 24h window
            guard d >= startDate && d <= endDate else { continue }

            let x = d.timeIntervalSince(startDate)
            entries.append(ChartDataEntry(x: x, y: v))

            if v < minY { minY = v }
            if v > maxY { maxY = v }
        }

        let set = LineChartDataSet(entries: entries, label: "")
        set.setColor(.label)
        set.lineWidth = 1.5
        set.drawValuesEnabled = false
        set.drawCirclesEnabled = false
        set.mode = .linear
        set.drawFilledEnabled = false
        set.highlightEnabled = false

        uiView.data = LineChartData(dataSet: set)

        // X axis formatting: show time-of-day labels across the 24h window
        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "HH:mm"

        uiView.xAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
            let date = startDate.addingTimeInterval(value)
            return df.string(from: date)
        }

        // Force x range to exactly 24h
        uiView.xAxis.axisMinimum = 0
        uiView.xAxis.axisMaximum = 24 * 60 * 60

        // Y axis scaling: pad a bit but keep reasonable bounds (deviations ~ +/-10)
        if minY.isFinite && maxY.isFinite {
            let pad: Double = 1.5
            let minBound = floor(minY - pad)
            let maxBound = ceil(maxY + pad)
            let span = max(4, maxBound - minBound)

            uiView.leftAxis.axisMinimum = min(-12, minBound)
            uiView.leftAxis.axisMaximum = max(12, minBound + span)
        } else {
            uiView.leftAxis.axisMinimum = -12
            uiView.leftAxis.axisMaximum = 12
        }

        // Grid styling (subtle) + emphasized zero line
        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.35)
        uiView.xAxis.gridColor = gridLineColor
        uiView.xAxis.gridLineWidth = 0.5
        uiView.xAxis.gridLineDashLengths = [2, 2]

        uiView.leftAxis.gridColor = gridLineColor
        uiView.leftAxis.gridLineWidth = 0.5
        uiView.leftAxis.gridLineDashLengths = [2, 2]

        // Ensure the 0-line stays emphasized even after updates
        uiView.leftAxis.drawZeroLineEnabled = true
        uiView.leftAxis.zeroLineWidth = 1.5
        uiView.leftAxis.zeroLineColor = UIColor.label.withAlphaComponent(0.75)

        uiView.rightAxis.enabled = false

        uiView.notifyDataSetChanged()
        uiView.setNeedsDisplay()
    }
}

@available(iOS 16.0, *)
private struct AnalyzeIobCobLineChart: UIViewRepresentable {

    /// (date, iob, cob)
    let points: [(Date, Double, Double)]

    func makeUIView(context: Context) -> LineChartView {
        let v = LineChartView()

        v.legend.enabled = false
        v.chartDescription.enabled = false

        v.minOffset = 8
        //v.extraRightOffset = 14

        v.pinchZoomEnabled = true
        v.doubleTapToZoomEnabled = true
        v.scaleXEnabled = true
        v.scaleYEnabled = false
        v.dragEnabled = true

        v.highlightPerTapEnabled = false
        v.highlightPerDragEnabled = false
        v.drawMarkers = false

        v.backgroundColor = .clear
        v.isOpaque = false

        // X axis
        let xAxis = v.xAxis
        xAxis.labelPosition = .bottom
        xAxis.drawGridLinesEnabled = true
        xAxis.granularityEnabled = true
        xAxis.granularity = 3 * 60 * 60

        // Left axis (COB)
        let left = v.leftAxis
        left.drawGridLinesEnabled = true
        left.drawZeroLineEnabled = true
        left.zeroLineWidth = 1.5
        left.zeroLineColor = UIColor.label.withAlphaComponent(0.75)
        left.axisMinimum = -30
        left.axisMaximum = 150
        left.granularityEnabled = true
        left.granularity = 30

        // Right axis (IOB)
        let right = v.rightAxis
        right.enabled = true
        right.drawGridLinesEnabled = false
        right.drawZeroLineEnabled = false
        right.axisMinimum = -1
        right.axisMaximum = 5
        right.granularityEnabled = true
        right.granularity = 1

        return v
    }

    func updateUIView(_ uiView: LineChartView, context: Context) {
        guard !points.isEmpty else {
            uiView.data = nil
            uiView.setNeedsDisplay()
            return
        }

        let sorted = points.sorted(by: { $0.0 < $1.0 })

        let endDate = sorted.last!.0
        let startDate = endDate.addingTimeInterval(-24 * 60 * 60)

        var cobEntries: [ChartDataEntry] = []
        var iobEntries: [ChartDataEntry] = []
        cobEntries.reserveCapacity(sorted.count)
        iobEntries.reserveCapacity(sorted.count)

        for (d, iob, cob) in sorted {
            guard d >= startDate && d <= endDate else { continue }
            let x = d.timeIntervalSince(startDate)
            cobEntries.append(ChartDataEntry(x: x, y: cob))
            iobEntries.append(ChartDataEntry(x: x, y: iob))
        }

        let cobSet = LineChartDataSet(entries: cobEntries, label: "COB")
        cobSet.setColor(UIColor.orange.withAlphaComponent(0.85))
        cobSet.lineWidth = 2
        cobSet.drawValuesEnabled = false
        cobSet.drawCirclesEnabled = false
        cobSet.mode = .linear
        cobSet.drawFilledEnabled = false
        cobSet.highlightEnabled = false
        cobSet.axisDependency = .left

        let iobSet = LineChartDataSet(entries: iobEntries, label: "IOB")
        iobSet.setColor(UIColor.systemTeal.withAlphaComponent(0.85))
        iobSet.lineWidth = 2
        iobSet.drawValuesEnabled = false
        iobSet.drawCirclesEnabled = false
        iobSet.mode = .linear
        iobSet.drawFilledEnabled = false
        iobSet.highlightEnabled = false
        iobSet.axisDependency = .right

        uiView.data = LineChartData(dataSets: [cobSet, iobSet])

        // X labels
        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "HH:mm"
        uiView.xAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
            let date = startDate.addingTimeInterval(value)
            return df.string(from: date)
        }

        uiView.xAxis.axisMinimum = 0
        uiView.xAxis.axisMaximum = 24 * 60 * 60

        // Subtle grid styling
        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.35)
        uiView.xAxis.gridColor = gridLineColor
        uiView.xAxis.gridLineWidth = 0.5
        uiView.xAxis.gridLineDashLengths = [2, 2]

        uiView.leftAxis.gridColor = gridLineColor
        uiView.leftAxis.gridLineWidth = 0.5
        uiView.leftAxis.gridLineDashLengths = [2, 2]

        uiView.rightAxis.axisLineColor = UIColor.label.withAlphaComponent(0.5)
        uiView.rightAxis.labelTextColor = UIColor.label.withAlphaComponent(0.85)
        uiView.leftAxis.labelTextColor = UIColor.label.withAlphaComponent(0.85)
        uiView.xAxis.labelTextColor = UIColor.label.withAlphaComponent(0.85)

        uiView.notifyDataSetChanged()
        uiView.setNeedsDisplay()
    }
}
