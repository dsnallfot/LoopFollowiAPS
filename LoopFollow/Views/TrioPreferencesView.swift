//
//  TrioPreferencesView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-23.

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
    @State private var isShowingAnalyzeDeviations: Bool = false

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
            .sheet(isPresented: $isShowingAnalyzeDeviations) {
                NavigationStack {
                    AnalyzeDeviationsView(viewModel: viewModel)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Klar") {
                                    isShowingAnalyzeDeviations = false
                                }
                            }
                        }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isShowingAnalyzeDeviations = true
                    } label: {
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

    @ObservedObject var viewModel: TrioPreferencesViewModel
    @State private var selectedDate: Date = Date()

    private enum DisplayMode: String, CaseIterable, Identifiable {
        case normal = "Normal"
        case stacked = "Stackad"
        var id: String { rawValue }
    }

    @State private var displayMode: DisplayMode = .normal

    private var devPointsForChart: [(Date, Double)] {
        viewModel.devPoints.sorted(by: { $0.date < $1.date }).map { ($0.date, $0.dev) }
    }

    private var iobCobPointsForChart: [(Date, Double, Double)] {
        viewModel.iobCobPoints.sorted(by: { $0.date < $1.date }).map { ($0.date, $0.iob, $0.cob) }
    }

    private var glucosePointsForChart: [(Date, Double)] {
        viewModel.glucosePoints.sorted(by: { $0.date < $1.date }).map { ($0.date, $0.mmol) }
    }

    private var selectedDayStart: Date {
        Calendar.current.startOfDay(for: selectedDate)
    }

    private var dateRangeLast90Days: ClosedRange<Date> {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now.addingTimeInterval(-90 * 24 * 60 * 60)
        return start...now
    }

    // --- Day navigation chevrons ---
    private var canGoToPreviousDay: Bool {
        selectedDayStart > Calendar.current.startOfDay(for: dateRangeLast90Days.lowerBound)
    }

    private var canGoToNextDay: Bool {
        let todayStart = Calendar.current.startOfDay(for: Date())
        return selectedDayStart < todayStart
    }

    private func goToPreviousDay() {
        guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else { return }
        // Clamp to 90-day window
        let minDay = Calendar.current.startOfDay(for: dateRangeLast90Days.lowerBound)
        let clamped = max(prev, minDay)
        selectedDate = clamped
    }

    private func goToNextDay() {
        guard let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) else { return }
        // Clamp to today
        let todayStart = Calendar.current.startOfDay(for: Date())
        let clamped = min(next, todayStart)
        selectedDate = clamped
    }

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Pinned DatePicker (stays visible while scrolling)
                HStack(spacing: 10) {
                    DatePicker(
                        "",
                        selection: $selectedDate,
                        in: dateRangeLast90Days,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "sv_SE"))
                    
                    Spacer()

                    Picker("", selection: $displayMode) {
                        ForEach(DisplayMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .environment(\.locale, Locale(identifier: "sv_SE"))
                    .frame(maxWidth: 220)
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 12) {
                        if displayMode == .normal {
                            // --- Glucose chart card ---
                            VStack(alignment: .leading, spacing: 8) {
                                if viewModel.glucoseIsLoading {
                                    HStack(spacing: 6) {
                                        ProgressView().scaleEffect(0.8)
                                        Text("Hämtar glukos…")
                                    }
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                                } else if let err = viewModel.glucoseLastError {
                                    Text("Fel: \(err)")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 4)
                                } else {
                                    Text("Glukos (mmol/L)")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                        .fontWeight(.semibold)
                                }

                                AnalyzeGlucoseLineChart(
                                    points: glucosePointsForChart,
                                    windowStart: selectedDayStart,
                                    highLine: Double(UserDefaultsRepository.highLine.value) / 18.0182,
                                    lowLine: Double(UserDefaultsRepository.lowLine.value) / 18.0182,
                                    showNormalChartElements: true
                                )
                                .frame(height: 240)
                            }
                            .padding(12)
                            .themedCardBackground(opacity: 0.12)
                            .padding(.horizontal, 12)
                            
                            // --- Dev chart card ---
                            VStack(alignment: .leading, spacing: 8) {
                                if viewModel.devIsLoading {
                                    HStack(spacing: 6) {
                                        ProgressView().scaleEffect(0.8)
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
                                    Text("Dev (30m +/- mmol/L)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }

                                AnalyzeDeviationsLineChart(points: devPointsForChart, windowStart: selectedDayStart, showNormalChartElements: true)
                                    .frame(height: 240)
                            }
                            .padding(12)
                            .themedCardBackground(opacity: 0.12)
                            .padding(.horizontal, 12)

                            // --- COB/IOB chart card ---
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("COB (g)")
                                        .foregroundColor(Color(.carbs))
                                    Spacer()
                                    Text("IOB (E)")
                                        .foregroundColor(Color(.insulin))
                                }
                                .font(.subheadline)
                                .fontWeight(.semibold)

                                AnalyzeIobCobLineChart(points: iobCobPointsForChart, windowStart: selectedDayStart, showNormalChartElements: true)
                                    .frame(height: 240)
                            }
                            .padding(12)
                            .themedCardBackground(opacity: 0.12)
                            .padding(.horizontal, 12)

                        } else {
                            // --- Stacked overlay card ---
                            VStack(alignment: .leading, spacing: 8) {
                                if viewModel.devIsLoading || viewModel.glucoseIsLoading {
                                    HStack(spacing: 6) {
                                        ProgressView().scaleEffect(0.8)
                                        Text("Hämtar data…")
                                    }
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                                } else if let err = (viewModel.devLastError ?? viewModel.glucoseLastError) {
                                    Text("Fel: \(err)")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 4)
                                } else {
                                    HStack {
                                        Spacer()
                                        Text("━ Glukos")
                                            .foregroundColor(.green)
                                        Spacer()
                                        Text("━ Dev")
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text("━ COB")
                                            .foregroundColor(Color(.carbs))
                                        Spacer()
                                        Text("━ IOB")
                                            .foregroundColor(Color(.insulin))
                                        Spacer()
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                }

                                ZStack {
                                    AnalyzeDeviationsLineChart(points: devPointsForChart, windowStart: selectedDayStart, showNormalChartElements: false)
                                    AnalyzeIobCobLineChart(points: iobCobPointsForChart, windowStart: selectedDayStart, showNormalChartElements: false)
                                    AnalyzeGlucoseLineChart(
                                        points: glucosePointsForChart,
                                        windowStart: selectedDayStart,
                                        highLine: Double(UserDefaultsRepository.highLine.value) / 18.0182,
                                        lowLine: Double(UserDefaultsRepository.lowLine.value) / 18.0182,
                                        showNormalChartElements: false
                                    )
                                }
                                .frame(height: 420)
                            }
                            .padding(12)
                            .themedCardBackground(opacity: 0.12)
                            .padding(.horizontal, 12)
                        }

                        Spacer(minLength: 16)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    goToPreviousDay()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoToPreviousDay)
                .accessibilityLabel("Föregående dag")
            }

                ToolbarItem(placement: .navigationBarLeading) {

                    Button {
                        goToNextDay()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!canGoToNextDay)
                    .accessibilityLabel("Nästa dag")
                }
        }
        .navigationTitle("Utvärdering oref")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.fetchDevIobCobForDay(selectedDate, count: 600)
            viewModel.fetchGlucoseForDay(selectedDate)
        }
        .onChange(of: selectedDate) { newDate in
            viewModel.fetchDevIobCobForDay(newDate, count: 600)
            viewModel.fetchGlucoseForDay(newDate)
        }
    }
}
@available(iOS 16.0, *)
private struct AnalyzeGlucoseLineChart: UIViewRepresentable {

    /// (date, mmol/L)
    let points: [(Date, Double)]
    let windowStart: Date
    let highLine: Double
    let lowLine: Double
    let showNormalChartElements: Bool

    func makeUIView(context: Context) -> LineChartView {
        let v = LineChartView()

        v.legend.enabled = false
        v.chartDescription.enabled = false
        v.rightAxis.enabled = false
        v.minOffset = 8
        v.extraRightOffset = showNormalChartElements ? 20 : 12
        v.extraLeftOffset = showNormalChartElements ? 0 : 12

        v.pinchZoomEnabled = showNormalChartElements
        v.doubleTapToZoomEnabled = showNormalChartElements
        v.scaleXEnabled = showNormalChartElements
        v.scaleYEnabled = false
        v.dragEnabled = showNormalChartElements

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
        xAxis.drawLabelsEnabled = true//showNormalChartElements

        // Y axis (0–24 mmol/L)
        let yAxis = v.leftAxis
        yAxis.drawGridLinesEnabled = showNormalChartElements
        yAxis.drawZeroLineEnabled = false
        yAxis.axisMinimum = showNormalChartElements ? 0 : -2
        yAxis.axisMaximum = showNormalChartElements ? 24 : 22
        yAxis.granularityEnabled = true
        yAxis.granularity = 2
        yAxis.drawLimitLinesBehindDataEnabled = true
        yAxis.drawLabelsEnabled = showNormalChartElements

        return v
    }

    func updateUIView(_ uiView: LineChartView, context: Context) {
        guard !points.isEmpty else {
            uiView.data = nil
            uiView.setNeedsDisplay()
            return
        }

        let sorted = points.sorted(by: { $0.0 < $1.0 })
        let startDate = windowStart
        let endDate = startDate.addingTimeInterval(24 * 60 * 60)

        var entries: [ChartDataEntry] = []
        entries.reserveCapacity(sorted.count)

        for (d, mmol) in sorted {
            guard d >= startDate && d <= endDate else { continue }
            let x = d.timeIntervalSince(startDate)
            entries.append(ChartDataEntry(x: x, y: mmol))
        }

        let set = LineChartDataSet(entries: entries, label: "")
        set.setColor(.green)
        set.lineWidth = showNormalChartElements ? 2 : 1
        set.drawValuesEnabled = false
        set.drawCirclesEnabled = false
        set.mode = .linear
        set.drawFilledEnabled = false
        set.highlightEnabled = false

        uiView.data = LineChartData(dataSet: set)

        // High/Low limit lines
        uiView.leftAxis.removeAllLimitLines()

        let high = ChartLimitLine(limit: highLine)
        high.lineWidth = 0.5
        high.lineColor = UIColor.systemPurple
        high.labelPosition = .rightTop
        high.valueTextColor = UIColor.clear

        let low = ChartLimitLine(limit: lowLine)
        low.lineWidth = 0.5
        low.lineColor = UIColor.systemRed
        low.labelPosition = .rightBottom
        low.valueTextColor = UIColor.clear

        uiView.leftAxis.addLimitLine(high)
        uiView.leftAxis.addLimitLine(low)

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

        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.35)
        uiView.xAxis.gridColor = gridLineColor
        uiView.xAxis.gridLineWidth = 0.5
        uiView.xAxis.gridLineDashLengths = [2, 2]

        uiView.leftAxis.gridColor = gridLineColor
        uiView.leftAxis.gridLineWidth = 0.5
        uiView.leftAxis.gridLineDashLengths = [2, 2]

        uiView.notifyDataSetChanged()
        uiView.setNeedsDisplay()
    }
}

@available(iOS 16.0, *)
private struct AnalyzeDeviationsLineChart: UIViewRepresentable {

    /// (date, value)
    let points: [(Date, Double)]
    let windowStart: Date
    let showNormalChartElements: Bool

    func makeUIView(context: Context) -> LineChartView {
        let v = LineChartView()

        v.legend.enabled = false
        v.chartDescription.enabled = false
        v.rightAxis.enabled = false
        v.minOffset = 8
        // Add a bit of space on the right so the last x-label ("nu") doesn't clip
        v.extraRightOffset = showNormalChartElements ? 20 : 12
        v.extraLeftOffset = showNormalChartElements ? 0 : 12

        v.pinchZoomEnabled = showNormalChartElements
        v.doubleTapToZoomEnabled = showNormalChartElements
        v.scaleXEnabled = showNormalChartElements
        v.scaleYEnabled = false
        v.dragEnabled = showNormalChartElements

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
        xAxis.drawLabelsEnabled = true//showNormalChartElements

        // Left axis
        let yAxis = v.leftAxis
        yAxis.drawGridLinesEnabled = true//showNormalChartElements
        yAxis.drawZeroLineEnabled = true

        // Make the 0-line stand out more than other grid lines
        yAxis.zeroLineWidth = 1.5
        yAxis.zeroLineColor = UIColor.label.withAlphaComponent(0.75)

        yAxis.axisMinimum = showNormalChartElements ? -8 : -8
        yAxis.axisMaximum = showNormalChartElements ? 16 : 16
        yAxis.granularityEnabled = true
        yAxis.granularity = 2
        yAxis.drawLabelsEnabled = showNormalChartElements

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

        // Fixed 24h window for the selected day
        let startDate = windowStart
        let endDate = startDate.addingTimeInterval(24 * 60 * 60)

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
        set.lineWidth = showNormalChartElements ? 2 : 1
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

            uiView.leftAxis.axisMinimum = showNormalChartElements ? min(-8, minBound) : -8
            uiView.leftAxis.axisMaximum = showNormalChartElements ? max(16, minBound + span) : 16
            uiView.leftAxis.axisMinimum = showNormalChartElements ? -8 : -8
            uiView.leftAxis.axisMaximum = showNormalChartElements ? 16 : 16
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
        uiView.leftAxis.zeroLineWidth = showNormalChartElements ? 2 : 1
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
    let windowStart: Date
    let showNormalChartElements: Bool

    func makeUIView(context: Context) -> LineChartView {
        let v = LineChartView()

        v.legend.enabled = false
        v.chartDescription.enabled = false

        v.minOffset = 8
        v.extraRightOffset = showNormalChartElements ? 0 : 12
        v.extraLeftOffset = showNormalChartElements ? 0 : 12

        v.pinchZoomEnabled = showNormalChartElements
        v.doubleTapToZoomEnabled = showNormalChartElements
        v.scaleXEnabled = showNormalChartElements
        v.scaleYEnabled = false
        v.dragEnabled = showNormalChartElements

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
        xAxis.drawLabelsEnabled = true//showNormalChartElements

        // Left axis (COB)
        let left = v.leftAxis
        left.drawGridLinesEnabled = showNormalChartElements
        left.drawZeroLineEnabled = true
        left.zeroLineWidth = 1.5
        left.zeroLineColor = UIColor.label.withAlphaComponent(0.75)
        left.axisMinimum = showNormalChartElements ? -30 : -60
        left.axisMaximum = showNormalChartElements ? 150 : 120
        left.granularityEnabled = true
        left.granularity = 30
        left.drawLabelsEnabled = showNormalChartElements

        // Right axis (IOB)
        let right = v.rightAxis
        right.enabled = true
        right.drawGridLinesEnabled = false
        right.drawZeroLineEnabled = false
        right.axisMinimum = showNormalChartElements ? -1 : -2
        right.axisMaximum = showNormalChartElements ? 5 : 4
        right.granularityEnabled = true
        right.granularity = 1
        right.drawLabelsEnabled = showNormalChartElements

        return v
    }

    func updateUIView(_ uiView: LineChartView, context: Context) {
        guard !points.isEmpty else {
            uiView.data = nil
            uiView.setNeedsDisplay()
            return
        }

        let sorted = points.sorted(by: { $0.0 < $1.0 })

        let startDate = windowStart
        let endDate = startDate.addingTimeInterval(24 * 60 * 60)

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
        cobSet.setColor(UIColor.carbs)
        cobSet.lineWidth = showNormalChartElements ? 2 : 1
        cobSet.drawValuesEnabled = false
        cobSet.drawCirclesEnabled = false
        cobSet.mode = .linear
        cobSet.drawFilledEnabled = false
        cobSet.highlightEnabled = false
        cobSet.axisDependency = .left

        let iobSet = LineChartDataSet(entries: iobEntries, label: "IOB")
        iobSet.setColor(.insulin)
        iobSet.lineWidth = showNormalChartElements ? 2 : 1
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
