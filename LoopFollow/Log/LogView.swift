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

            LogViewChart(
                title: filters.isEmpty
                    ? "Sökträffar"
                    : "Sökträffar",
                    //: "Träffar: \(filters.map { $0.term }.joined(separator: " • "))",
                series: series
            )
        }
    }

}

@available(iOS 16.0, *)
private struct LogViewChart: View {
    let title: String
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
                            .frame(height: 320)
                            .padding(.horizontal)

                        Text("• X-axel: 00:00 → 24:00 (innevarande dygn) \n• Y-axel: minut i timmen (0–60)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
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
        chartView.leftAxis.granularity = 10
        chartView.leftAxis.drawZeroLineEnabled = true

        chartView.xAxis.labelPosition = .bottom
        chartView.xAxis.granularityEnabled = true
        chartView.xAxis.granularity = 3 * 60 * 60 // 3 timmar i sekunder

        // Tvinga 9 etiketter över dygnet: 00, 03, 06, 09, 12, 15, 18, 21, 24
        // (Charts fördelar etiketter jämnt mellan axisMinimum/axisMaximum när force=true)
        chartView.xAxis.setLabelCount(9, force: true)

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

