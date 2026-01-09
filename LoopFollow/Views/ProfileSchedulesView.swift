//
//  ProfileSchedulesView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-26.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import SwiftUI
import Charts

@available(iOS 16.0, *)
struct ProfileSchedulesView: View {
    @ObservedObject var viewModel = ProfileSchedulesViewModel()
    
    @State private var selectedSection: SectionType = .targets // Default section
    @State private var showProfileUpdatedAlert: Bool = false

    enum SectionType: String, CaseIterable {
        case targets = "Mål"
        case basal = "Basal"
        case cr = "CR"
        case isf = "ISF"
        case csf = "CSF"
        case cHr = "Kh/h"
        case smb = "SMB"

        var displayName: String {
            switch self {
            case .targets: return "Targets"
            case .basal: return "Basal"
            case .cr: return "Carb Ratios"
            case .isf: return "Insulin Sensitivity Factor"
            case .csf: return "Carb Sensitivity Factor"
            case .cHr: return "Minimum Carbs grams/hour"
            case .smb: return "SMB Limits"
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
        case .smb:
            // Parse the first number from the "x.xx / y.yy" string for graph
            let entries = viewModel.smbEntries.compactMap { entry -> ScheduleEntry? in
                guard let valueString = entry.value.split(separator: "/").first,
                      let value = Double(valueString.trimmingCharacters(in: .whitespaces)) else {
                    return nil
                }
                return ScheduleEntry(time: entry.time, value: String(format: "%.2f", value))
            }
            return extractChartData(from: entries)
        }
    }
    
    var multiChartData: [(data: [ChartDataEntry], label: String)] {
        switch selectedSection {
        case .basal:
            let basalData = extractChartData(from: viewModel.basalEntries, skipLast: true)
            let basalIOBData = extractChartData(from: viewModel.basalIOBEntries, skipLast: true)

            return [
                (data: basalData, label: "Basal"),
                (data: basalIOBData, label: "Basal IOB")
            ]

        case .smb:
            let smbValues = viewModel.smbEntries.compactMap { entry -> (x: Double, smb: Double, uam: Double)? in
                guard let hour = Double(entry.time.prefix(2)) else { return nil }
                let parts = entry.value.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2,
                      let smb = Double(parts[0]),
                      let uam = Double(parts[1]) else { return nil }
                return (x: hour, smb: smb, uam: uam)
            }

            let smbData = smbValues.map { ChartDataEntry(x: $0.x, y: $0.smb) }
            let uamData = smbValues.map { ChartDataEntry(x: $0.x, y: $0.uam) }

            return [
                (data: smbData, label: "Max SMB"),
                (data: uamData, label: "Max UAMSMB")
            ]

        default:
            return [(data: chartData, label: selectedSection.displayName)]
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
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("Select Section", selection: $selectedSection) {
                    ForEach(SectionType.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                LineChartWrapper(chartData: multiChartData, title: selectedSection.displayName)
                    .frame(height: 150)
                    .padding(.horizontal)

                List {
                    if selectedSection == .targets {
                        Section(header: Text("🟪 Mål (mmol/L)")) {
                            ForEach(viewModel.targetEntries) { entry in
                                scheduleRow(entry)
                                    .listRowBackground(Color.black.opacity(0.1))
                            }
                        }
                        .listRowBackground(Color.black.opacity(0.1))
                    }

                    if selectedSection == .basal {
                        Section(header: Text("🟪 Basal (E/h)")) {
                            ForEach(viewModel.basalEntries) { entry in
                                scheduleRow(entry, isBold: entry.time == "Total daglig basal")
                                    .listRowBackground(Color.black.opacity(0.1))
                            }
                        }
                        .listRowBackground(Color.black.opacity(0.1))

                        Section(header: Text("🟦 Basal IOB (E aktiv/h)")) {
                            ForEach(viewModel.basalIOBEntries) { entry in
                                scheduleRow(entry, isBold: entry.time == "Medel basal IOB/h")
                                    .listRowBackground(Color.black.opacity(0.1))
                            }
                        }
                        .listRowBackground(Color.black.opacity(0.1))
                    }

                    if selectedSection == .cr {
                        Section(header: Text("🟪 Insulinkvoter CR (g/E)")) {
                            ForEach(viewModel.carbRatioEntries) { entry in
                                scheduleRow(entry)
                                    .listRowBackground(Color.black.opacity(0.1))
                            }
                        }
                        .listRowBackground(Color.black.opacity(0.1))
                    }

                    if selectedSection == .isf {
                        Section(header: Text("🟪 Insulinkänslighet ISF (mmol/L/E)")) {
                            ForEach(viewModel.isfEntries) { entry in
                                scheduleRow(entry)
                                    .listRowBackground(Color.black.opacity(0.1))
                            }
                        }
                        .listRowBackground(Color.black.opacity(0.1))
                    }

                    if selectedSection == .csf {
                        Section(header: Text("🟪 Kh-känslighet CSF (mmol/L/g)")) {
                            ForEach(viewModel.csfEntries) { entry in
                                scheduleRow(entry)
                                    .listRowBackground(Color.black.opacity(0.1))
                            }
                        }
                        .listRowBackground(Color.black.opacity(0.1))
                    }

                    if selectedSection == .cHr {
                        Section(header: Text("🟪 Minsta absorption Kh (g/h)")) {
                            ForEach(viewModel.minCarbsEntries) { entry in
                                scheduleRow(entry, isBold: entry.time == "Medelvärde")
                                    .listRowBackground(Color.black.opacity(0.1))
                            }
                        }
                        .listRowBackground(Color.black.opacity(0.1))
                    }

                    if selectedSection == .smb {
                        Section(header: Text("🟦 Maxgräns SMB / UAMSMB (E/SMB)")) {
                            ForEach(viewModel.smbEntries) { entry in
                                scheduleRow(entry)
                                    .listRowBackground(Color.black.opacity(0.1))
                            }
                        }
                        .listRowBackground(Color.black.opacity(0.1))
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showProfileUpdatedAlert = true
                } label: {
                    Image(systemName: "info")
                }
                .accessibilityLabel("Profil uppdaterades senast")
            }
        }
        .alert("Profil uppdaterades senast", isPresented: $showProfileUpdatedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(ProfileManager.shared.profileCreatedAtFormatted ?? "Okänt")
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
