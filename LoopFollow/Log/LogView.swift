//
//  LogView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-13.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import SwiftUI
import Charts

@available(iOS 26.0, *)
struct LogView: View {
    @ObservedObject var viewModel = LogViewModel()
    @State private var isChartPresented: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    /// Används när vyn ligger i UIKit-nav/modal
    let onDone: (() -> Void)?

    // MARK: - MultiFilter logic
    private struct MultiFilter: Identifiable {
        let id: Int
        let term: String
        let color: Color
    }

    /// Split search text by '.' into up to 3 filters: [blue, yellow, red]
    private var multiFilters: [MultiFilter] {
        let rawParts = viewModel.searchText
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let palette: [Color] = [.blue, .yellow, .red]
        return rawParts.prefix(3).enumerated().map { idx, term in
            MultiFilter(id: idx, term: term, color: palette[idx])
        }
    }

    private func matchingFilter(for line: String) -> MultiFilter? {
        guard !multiFilters.isEmpty else { return nil }
        let lower = line.lowercased()
        return multiFilters.first(where: { lower.contains($0.term.lowercased()) })
    }


    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Picker("Category", selection: $viewModel.selectedCategory) {
                    Text("Allt").tag(LogManager.Category?.none)
                    ForEach(LogManager.Category.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(LogManager.Category?.some(category))
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.horizontal)

                SearchBar(
                    text: $viewModel.searchText,
                    placeholder: viewModel.searchResultsIsHighlighted
                        ? "Highlighta i loggen"
                        : "Sök i loggen"
                )
                .padding(.horizontal)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.filteredLogEntries) { entry in
                            Text(entry.text)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 0)
                                .foregroundColor(
                                    matchingFilter(for: entry.text)?.color
                                    ?? .primary
                                )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .background(Color.clear)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    viewModel.searchResultsIsHighlighted.toggle()
                }) {
                    Image(systemName: viewModel.searchResultsIsHighlighted
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .foregroundColor(viewModel.searchResultsIsHighlighted ? .blue : .primary)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: {
                    isChartPresented = true
                }) {
                    Image(systemName: "info")
                }
                .accessibilityLabel("Info")
            }
                
                ToolbarSpacer(placement: .topBarTrailing)
                
                ToolbarItemGroup(placement: .topBarTrailing) {
                    
                    Button("Klar") {
                        if let onDone {
                            onDone()
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        .onAppear {
            viewModel.loadLogEntries()
        }
        .sheet(isPresented: $isChartPresented) {
            // Bygg upp matchade serier per filter (upp till 3)
            let filters = multiFilters

            let series: [LogViewChart.Series] = filters.map { f in
                let matched = viewModel.filteredLogEntries.filter { entry in
                    entry.text.localizedCaseInsensitiveContains(f.term)
                }
                return .init(id: f.id, label: f.term, color: f.color, entries: matched)
            }
            
            // Bygg en rubrik som inkluderar antal per filter/färg, t.ex. "Träffar: 🔵25 🟡32 🔴122"
            let emojiForSeriesId: [Int: String] = [0: "🔵", 1: "🟡", 2: "🔴"]
            let orderedForTitle = series.sorted(by: { $0.id < $1.id })
            let titleSuffix = orderedForTitle
                .map { s in
                    let emoji = emojiForSeriesId[s.id] ?? ""
                    return "\(emoji)\(s.entries.count) "
                }
                .joined(separator: " ")

            let chartTitle = titleSuffix.isEmpty ? "Träffar" : "Träffar: \(titleSuffix)"

            LogViewChart(
                title: chartTitle,
                // För special-statistik vill vi utgå från "hela" loggen (inte nödvändigtvis bara sökträffarna).
                allLogEntries: viewModel.allLogEntries,
                series: series
            )
        }
    }

}

@available(iOS 16.0, *)
private struct LogViewChart: View {
    let title: String
    let allLogEntries: [LogEntry]
    struct Series: Identifiable {
        let id: Int
        let label: String
        let color: Color
        let entries: [LogEntry]
    }
    let series: [Series]

    @Environment(\.dismiss) private var dismiss

    struct ChartPoint: Identifiable {
        let id: Int
        let seriesId: Int
        let date: Date
        let minuteOfHour: Double
    }

    private var pointsBySeries: [(series: Series, points: [ChartPoint])] {
        let now = Date()
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)

        // Datumformatter för loggens prefix: [HH:mm:ss]
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "sv_SE")
        timeFormatter.dateFormat = "HH:mm:ss"

        let todayStart = dayStart

        func parseDate(from line: String) -> Date? {
            // Förväntat format: "[21:34:12] ..."
            guard let firstOpen = line.firstIndex(of: "["),
                  let firstClose = line[firstOpen...].firstIndex(of: "]") else {
                return nil
            }

            let timeString = String(line[line.index(after: firstOpen)..<firstClose])
            guard let timeOnly = timeFormatter.date(from: timeString) else {
                return nil
            }

            // Kombinera tid med dagens datum
            let comps = calendar.dateComponents([.hour, .minute, .second], from: timeOnly)
            guard var combined = calendar.date(byAdding: comps, to: todayStart) else {
                return nil
            }

            // Begränsa till innevarande dygn: 00:00 -> 00:00 nästa dygn
            guard combined >= dayStart && combined < nextDayStart else {
                return nil
            }

            return combined
        }

        return series.map { s in
            let pts: [ChartPoint] = s.entries.compactMap { entry in
                guard let d = parseDate(from: entry.text) else { return nil }
                let minute = Double(calendar.component(.minute, from: d))
                return ChartPoint(id: entry.id, seriesId: s.id, date: d, minuteOfHour: minute)
            }
            .sorted(by: { $0.date < $1.date })

            return (series: s, points: pts)
        }
    }

    // MARK: - Specialare: BLE Ping success-rate (oavsett blå/gul/röd-filter)

    private struct StatRow: Identifiable {
        let id: String
        let label: String
        let value: String
    }

    private func parseTimeToday(from line: String, calendar: Calendar, todayStart: Date, dayStart: Date, nextDayStart: Date, timeFormatter: DateFormatter) -> Date? {
        // Förväntat format: "[21:34:12] ..."
        guard let firstOpen = line.firstIndex(of: "["),
              let firstClose = line[firstOpen...].firstIndex(of: "]") else {
            return nil
        }

        let timeString = String(line[line.index(after: firstOpen)..<firstClose])
        guard let timeOnly = timeFormatter.date(from: timeString) else {
            return nil
        }

        // Kombinera tid med dagens datum
        let comps = calendar.dateComponents([.hour, .minute, .second], from: timeOnly)
        guard let combined = calendar.date(byAdding: comps, to: todayStart) else {
            return nil
        }

        // Begränsa till innevarande dygn: 00:00 -> 00:00 nästa dygn
        guard combined >= dayStart && combined < nextDayStart else {
            return nil
        }

        return combined
    }

    private var specialStatsRows: [StatRow] {
        let now = Date()
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)

        // Datumformatter för loggens prefix: [HH:mm:ss]
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "sv_SE")
        timeFormatter.dateFormat = "HH:mm:ss"

        let todayStart = dayStart

        // 1) BLE Ping lyckades: räkna faktiska loggar med "Bluetooth ping received" inom dagens intervall
        let pingNeedle = "Bluetooth ping received"

        let pingActual = allLogEntries.reduce(into: 0) { acc, entry in
            guard entry.text.localizedCaseInsensitiveContains(pingNeedle) else { return }
            guard let d = parseTimeToday(from: entry.text,
                                         calendar: calendar,
                                         todayStart: todayStart,
                                         dayStart: dayStart,
                                         nextDayStart: nextDayStart,
                                         timeFormatter: timeFormatter) else { return }
            // Fram till NU
            guard d <= now else { return }
            acc += 1
        }

        // 2) Förväntade: 1 per 5-minutersfönster från midnatt till NU
        let elapsed = max(0, now.timeIntervalSince(dayStart))
        let expected = max(1, Int(elapsed / 300.0) + 1)

        let percent: Double = expected > 0 ? (Double(pingActual) / Double(expected)) * 100.0 : 0
        let percentString = String(format: "%.0f%%", percent)

        let pingValue = "\(pingActual)/\(expected) (\(percentString))"

        return [
            StatRow(id: "ble_ping", label: "BLE Ping lyckades", value: pingValue)
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemeBackground()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    let anyPoints = pointsBySeries.contains(where: { !$0.points.isEmpty })

                    if !anyPoints {
                        Text("Inga matchande loggrader att plotta.")
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    } else {
                        ScatterLogChartView(series: pointsBySeries)
                            .frame(maxWidth: .infinity)
                            .frame(height: 480)
                            .padding(.horizontal)

                        Text("• X-axel: 00:00 → 24:00 (innevarande dygn) \n• Y-axel: minut i timmen (0–60)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                        
                        // Tabell med special-statistik
                        VStack(spacing: 6) {
                            ForEach(specialStatsRows) { row in
                                HStack {
                                    Text(row.label)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(row.value)
                                        .font(.body)
                                        .monospacedDigit()
                                        .foregroundColor(.primary)
                                        .frame(alignment: .trailing)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .background(Color.clear)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Klar") {
                        dismiss()
                    }
                }
            }
        }
    }
}

@available(iOS 16.0, *)
private struct ScatterLogChartView: UIViewRepresentable {
    let series: [(series: LogViewChart.Series, points: [LogViewChart.ChartPoint])]

    func makeUIView(context: Context) -> ScatterChartView {
        let chartView = ScatterChartView()
        chartView.backgroundColor = .clear
        chartView.isOpaque = false

        chartView.legend.enabled = true
        chartView.legend.verticalAlignment = .bottom
        chartView.legend.horizontalAlignment = .center
        chartView.legend.orientation = .horizontal
        chartView.legend.drawInside = false
        chartView.chartDescription.enabled = false

        chartView.dragEnabled = true
        chartView.setScaleEnabled(true)
        chartView.pinchZoomEnabled = true
        chartView.highlightPerTapEnabled = false
        chartView.highlightPerDragEnabled = false

        // Axlar
        chartView.rightAxis.enabled = false
        chartView.leftAxis.axisMinimum = 0
        chartView.leftAxis.axisMaximum = 60
        chartView.leftAxis.granularity = 1
        chartView.leftAxis.drawZeroLineEnabled = true

        chartView.xAxis.labelPosition = .bottom
        chartView.xAxis.granularityEnabled = true
        chartView.xAxis.granularity = 3 * 60 * 60 // 3 timmar i sekunder

        // Tvinga 9 etiketter över dygnet: 00, 03, 06, 09, 12, 15, 18, 21, 24
        // (Charts fördelar etiketter jämnt mellan axisMinimum/axisMaximum när force=true)
        chartView.xAxis.setLabelCount(9, force: true)
        
        // Tvinga 13 etiketter över 60min: 0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60
        chartView.leftAxis.setLabelCount(13, force: true)

        // Extra bottenmarginal för att separera x-axel och legend visuellt
        chartView.extraBottomOffset = 6

        return chartView
    }

    func updateUIView(_ uiView: ScatterChartView, context: Context) {
        guard series.contains(where: { !$0.points.isEmpty }) else {
            uiView.data = nil
            return
        }

        let end = Date()

        // Viktigt: ordna serierna så att de ritas i rätt "lager" (0 underst, 1 mitten, 2 överst)
        let orderedSeries = series.sorted(by: { $0.series.id < $1.series.id })

        let dataSets: [ScatterChartDataSet] = orderedSeries.compactMap { s in
            guard !s.points.isEmpty else { return nil }

            let entries: [ChartDataEntry] = s.points.map { p in
                ChartDataEntry(x: p.date.timeIntervalSince1970, y: p.minuteOfHour)
            }

            let ds = ScatterChartDataSet(entries: entries, label: s.series.label)

            // Unika shapes + storlekar per filter
            switch s.series.id {
            case 0:
                // Blå: större cirkel (underst)
                ds.setScatterShape(.circle)
                ds.scatterShapeSize = 10
            case 1:
                // Yellow: triangel (mitten)
                ds.setScatterShape(.triangle)
                ds.scatterShapeSize = 8
            case 2:
                // Röd: cross (överst)
                ds.setScatterShape(.x)
                ds.scatterShapeSize = 7
            default:
                ds.setScatterShape(.circle)
                ds.scatterShapeSize = 7
            }

            ds.setColor(UIColor(s.series.color))
            ds.drawValuesEnabled = false
            return ds
        }

        uiView.data = ScatterChartData(dataSets: dataSets)

        // X-skala: innevarande dygn (00:00 -> 00:00 nästa dygn)
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: end)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)
        uiView.xAxis.axisMinimum = dayStart.timeIntervalSince1970
        uiView.xAxis.axisMaximum = nextDayStart.timeIntervalSince1970
        uiView.xAxis.setLabelCount(9, force: true)

        // Datumformatter på x-axeln
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "HH"
        uiView.xAxis.valueFormatter = EpochTimeAxisValueFormatter(dateFormatter: formatter)

        uiView.backgroundColor = .clear
        uiView.isOpaque = false
        uiView.notifyDataSetChanged()
    }
}

private final class EpochTimeAxisValueFormatter: AxisValueFormatter {
    private let dateFormatter: DateFormatter

    init(dateFormatter: DateFormatter) {
        self.dateFormatter = dateFormatter
    }

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        guard let axis = axis else {
            let date = Date(timeIntervalSince1970: value)
            return dateFormatter.string(from: date)
        }

        // Om detta är sista tick-marken (00:00 nästa dygn), visa "24" istället för "00"
        if abs(value - axis.axisMaximum) < 1 {
            return "24"
        }

        let date = Date(timeIntervalSince1970: value)
        return dateFormatter.string(from: date)
    }
}
