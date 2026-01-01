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
    @Environment(\.presentationMode) var presentationMode

    @State private var isChartPresented: Bool = false

    var body: some View {
        NavigationView {
            VStack {
                Picker("Category", selection: $viewModel.selectedCategory) {
                    Text("Allt").tag(LogManager.Category?.none)
                    ForEach(LogManager.Category.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(LogManager.Category?.some(category))
                    }
                }
                .pickerStyle(MenuPickerStyle())

                SearchBar(
                    text: $viewModel.searchText,
                    placeholder: viewModel.searchResultsIsHighlighted ? "Highlighta i loggen" : "Sök i loggen"
                )
                .padding([.leading, .trailing])

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.filteredLogEntries) { entry in
                            Text(entry.text)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 0)
                                .foregroundColor(
                                    viewModel.searchResultsIsHighlighted &&
                                    !viewModel.searchText.isEmpty &&
                                    entry.text.localizedCaseInsensitiveContains(viewModel.searchText)
                                    ? .blue
                                    : .primary
                                )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationBarTitle("Dagens logg", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        viewModel.searchResultsIsHighlighted.toggle()
                    }) {
                        Image(systemName: viewModel.searchResultsIsHighlighted
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                            .foregroundColor(viewModel.searchResultsIsHighlighted ? .blue : .primary)
                    }
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
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
            }
            .onAppear {
                viewModel.loadLogEntries()
            }
            .sheet(isPresented: $isChartPresented) {
                // Visa endast rader som matchar söktexten (även när highlight-läget är på)
                let matched = viewModel.filteredLogEntries.filter { entry in
                    !viewModel.searchText.isEmpty && entry.text.localizedCaseInsensitiveContains(viewModel.searchText)
                }

                LogViewChart(
                    title: viewModel.searchText.isEmpty
                        ? "Sökords-träffar"
                        : "Träffar: \(viewModel.searchText) (\(matched.count)st)",
                    matchedEntries: matched
                )
            }
        }
    }

}

@available(iOS 16.0, *)
private struct LogViewChart: View {
    let title: String
    let matchedEntries: [LogEntry]

    @Environment(\.dismiss) private var dismiss

    struct ChartPoint: Identifiable {
        let id: Int
        let date: Date
        let minuteOfHour: Double
    }

    private var points: [ChartPoint] {
        let now = Date()
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .hour, value: -24, to: now) ?? now.addingTimeInterval(-24 * 3600)

        // Datumformatter för loggens prefix: [HH:mm:ss]
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "sv_SE")
        timeFormatter.dateFormat = "HH:mm:ss"

        let todayStart = calendar.startOfDay(for: now)

        return matchedEntries.compactMap { entry in
            // Förväntat format: "[21:34:12] ..."
            guard let firstOpen = entry.text.firstIndex(of: "["),
                  let firstClose = entry.text[firstOpen...].firstIndex(of: "]") else {
                return nil
            }

            let timeString = String(entry.text[entry.text.index(after: firstOpen)..<firstClose])
            guard let timeOnly = timeFormatter.date(from: timeString) else {
                return nil
            }

            // Kombinera tid med dagens datum
            let comps = calendar.dateComponents([.hour, .minute, .second], from: timeOnly)
            guard var combined = calendar.date(byAdding: comps, to: todayStart) else {
                return nil
            }

            // Om loggen avser "igår" (t.ex. efter midnatt och vi tittar 24h bakåt)
            if combined > now {
                combined = calendar.date(byAdding: .day, value: -1, to: combined) ?? combined
            }

            // Begränsa till senaste 24 timmarna
            guard combined >= start && combined <= now else {
                return nil
            }

            let minute = Double(calendar.component(.minute, from: combined))
            return ChartPoint(id: entry.id, date: combined, minuteOfHour: minute)
        }
        .sorted(by: { $0.date < $1.date })
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if points.isEmpty {
                    Text("Inga matchande loggrader att plotta.")
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                } else {
                    ScatterLogChartView(points: points)
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .padding(.horizontal)

                    Text("• X-axel: senaste 24 timmarna \n• Y-axel: minut i timmen (0–60)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                Spacer(minLength: 0)
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
    let points: [LogViewChart.ChartPoint]

    func makeUIView(context: Context) -> ScatterChartView {
        let chartView = ScatterChartView()

        chartView.legend.enabled = false
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

        chartView.xAxis.labelPosition = .bottom
        chartView.xAxis.granularityEnabled = true
        chartView.xAxis.granularity = 3 * 60 * 60 // 3 timmar i sekunder

        return chartView
    }

    func updateUIView(_ uiView: ScatterChartView, context: Context) {
        guard !points.isEmpty else {
            uiView.data = nil
            return
        }

        //let start = points.first!.date
        let end = Date() //points.last!.date

        let entries: [ChartDataEntry] = points.map { p in
            ChartDataEntry(x: p.date.timeIntervalSince1970, y: p.minuteOfHour)
        }

        let dataSet = ScatterChartDataSet(entries: entries, label: "")
        dataSet.setScatterShape(.circle)
        dataSet.scatterShapeSize = 6
        dataSet.setColor(.systemBlue)
        dataSet.drawValuesEnabled = false

        let data = ScatterChartData(dataSet: dataSet)
        uiView.data = data

        // X-skala: senaste 24h (baserat på indata)
        uiView.xAxis.axisMinimum = end.timeIntervalSince1970 - 24 * 60 * 60 //start.timeIntervalSince1970
        uiView.xAxis.axisMaximum = end.timeIntervalSince1970

        // Datumformatter på x-axeln
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "HH:mm"
        uiView.xAxis.valueFormatter = EpochTimeAxisValueFormatter(dateFormatter: formatter)

        uiView.notifyDataSetChanged()
    }
}

private final class EpochTimeAxisValueFormatter: AxisValueFormatter {
    private let dateFormatter: DateFormatter

    init(dateFormatter: DateFormatter) {
        self.dateFormatter = dateFormatter
    }

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let date = Date(timeIntervalSince1970: value)
        return dateFormatter.string(from: date)
    }
}
