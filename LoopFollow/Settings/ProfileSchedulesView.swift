//
//  ProfileSchedulesView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-26.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import SwiftUI
import Charts

struct ProfileSchedulesView: View {
    @ObservedObject var viewModel = ProfileSchedulesViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedSection: SectionType = .targets // Default section

    enum SectionType: String, CaseIterable {
        case targets = "Mål"
        case basal = "Basal"
        case cr = "CR"
        case isf = "ISF"
        case csf = "CSF"
        case cHr = "Min Kh/h"

        var displayName: String {
            switch self {
            case .targets: return "Targets"
            case .basal: return "Basal"
            case .cr: return "Carb Ratios"
            case .isf: return "Insulin Sensitivity Factor"
            case .csf: return "Carb Sensitivity Factor"
            case .cHr: return "Minimum Carbs grams/hour"
            }
        }
    }

    // Compute chart data based on selected section.
    var chartData: [ChartDataEntry] {
        switch selectedSection {
        case .targets:
            return extractChartData(from: viewModel.targetEntries, fillForAllHours: true)
        case .basal:
            return extractChartData(from: viewModel.basalEntries, skipLast: true)
        case .cr:
            return extractChartData(from: viewModel.carbRatioEntries)
        case .isf:
            return extractChartData(from: viewModel.isfEntries)
        case .csf:
            return extractChartData(from: viewModel.csfEntries)
        case .cHr:
            return extractChartData(from: viewModel.minCarbsEntries, skipLast: true)
        }
    }
    
    /// New unified function to convert ScheduleEntry array to ChartDataEntry array.
    /// - Parameters:
    ///   - entries: The schedule entries.
    ///   - skipLast: If true, drops the final entry (e.g. summary rows).
    ///   - fillForAllHours: If true and only one entry exists (at 00:00), that value is applied to all hours.
    ///   - fillTo24: If true and the last data point’s x-value is less than 24, an extra entry at x=24 is added.
    private func extractChartData(from entries: [ScheduleEntry], skipLast: Bool = false, fillForAllHours: Bool = false, fillTo24: Bool = true) -> [ChartDataEntry] {
        let filteredEntries = skipLast ? Array(entries.dropLast()) : entries
        var outputData: [ChartDataEntry] = []
        
        // If there's only one entry at 00:00 and we want to fill all hours...
        if fillForAllHours, let firstEntry = filteredEntries.first, filteredEntries.count == 1 {
            if let singleValue = Double(firstEntry.value) {
                outputData = (0..<24).map { hour in
                    ChartDataEntry(x: Double(hour), y: singleValue)
                }
            }
        } else {
            for entry in filteredEntries {
                guard let hour = Double(entry.time.prefix(2)),
                      let value = Double(entry.value)
                else { continue }
                outputData.append(ChartDataEntry(x: hour, y: value))
            }
        }
        
        // Extend data to x = 24 if necessary.
        if fillTo24, let last = outputData.last, last.x < 24 {
            outputData.append(ChartDataEntry(x: 24, y: last.y))
        }
        
        return outputData
    }

    var body: some View {
        NavigationView {
            VStack {
                Picker("Select Section", selection: $selectedSection) {
                    ForEach(SectionType.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                LineChartWrapper(chartData: chartData, title: selectedSection.displayName)
                    .frame(height: 150)
                    .padding(.horizontal)

                List {
                    if selectedSection == .targets {
                        Section(header: Text("Mål")) {
                            ForEach(viewModel.targetEntries) { entry in
                                scheduleRow(entry)
                            }
                        }
                    }
                    
                    if selectedSection == .basal {
                        Section(header: Text("Basal")) {
                            ForEach(viewModel.basalEntries) { entry in
                                scheduleRow(entry, isBold: entry.time == "Total Daily Basal")
                            }
                        }
                    }
                    
                    if selectedSection == .cr {
                        Section(header: Text("Insulinkvoter (CR)")) {
                            ForEach(viewModel.carbRatioEntries) { entry in
                                scheduleRow(entry)
                            }
                        }
                    }
                    
                    if selectedSection == .isf {
                        Section(header: Text("Insulinkänslighet (ISF)")) {
                            ForEach(viewModel.isfEntries) { entry in
                                scheduleRow(entry)
                            }
                        }
                    }
                    
                    if selectedSection == .csf {
                        Section(header: Text("Kolhydratskänslighet (CSF))")) {
                            ForEach(viewModel.csfEntries) { entry in
                                scheduleRow(entry)
                            }
                        }
                    }
                    
                    if selectedSection == .cHr {
                        Section(header: Text("Minimi kolhydrater gram/timme")) {
                            ForEach(viewModel.minCarbsEntries) { entry in
                                scheduleRow(entry, isBold: entry.time == "Average")
                            }
                        }
                    }
                }
            }
            .navigationBarTitle("Profilinställningar", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Klar") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func scheduleRow(_ entry: ScheduleEntry, isBold: Bool = false) -> some View {
        HStack {
            Text(entry.time)
                .font(isBold ? .headline.bold() : .subheadline)
            Spacer()
            Text(entry.value)
                .font(isBold ? .headline.bold() : .subheadline)
        }
    }
}
