// LoopFollow
// AggregatedStatsView.swift

import SwiftUI
import UIKit

struct AggregatedStatsView: View {
    @ObservedObject var viewModel: AggregatedStatsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showGMI: Bool
    @State private var showStdDev: Bool
    @State private var showFPU: Bool
    @State private var showSMB: Bool
    @State private var showProfileBasal: Bool
    @State private var selectedPeriod = 14
    @State private var isLoadingData = false

    init(viewModel: AggregatedStatsViewModel) {
        self.viewModel = viewModel
        _showGMI = State(initialValue: Storage.shared.showGMI.value)
        _showStdDev = State(initialValue: Storage.shared.showStdDev.value)
        _showFPU = State(initialValue: Storage.shared.showFPU.value)
        _showSMB = State(initialValue: Storage.shared.showSMB.value)
        _showProfileBasal = State(initialValue: Storage.shared.showProfileBasal.value)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed segment picker header
            VStack(spacing: 8) {
                Picker("Period", selection: $selectedPeriod) {
                    Text("Idag").tag(0)
                    Text("24 h").tag(1)
                    Text("7 dagar").tag(7)
                    Text("14 dagar").tag(14)
                    Text("30 dagar").tag(30)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .onChange(of: selectedPeriod) { newValue in
                    isLoadingData = true
                    viewModel.updatePeriod(newValue) {
                        isLoadingData = false
                    }
                }
            }
            .background(Color(.systemBackground))
            .zIndex(1)

            ScrollView {
                VStack(spacing: 20) {
                    if isLoadingData {
                        ProgressView("Laddar data...")
                            .padding()
                    }

                    StatsGridView(
                        simpleStats: viewModel.simpleStats,
                        showGMI: $showGMI,
                        showStdDev: $showStdDev,
                        showFPU: $showFPU,
                        showSMB: $showSMB,
                        showProfileBasal: $showProfileBasal
                    )
                    .padding(.horizontal)

                    AGPView(viewModel: viewModel.agpStats)
                        .padding(.horizontal)

                    TIRView(viewModel: viewModel.tirStats)
                        .padding(.horizontal)

                    GRIView(viewModel: viewModel.griStats)
                        .padding(.horizontal)
                }
                .padding(.bottom)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Statistik")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Ladda om") {
                    viewModel.calculateStats()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Klar") {
                    dismiss()
                }
            }
        }
        .onAppear {
            viewModel.dataService.ensureDataAvailable(
                onProgress: {},
                completion: {
                    viewModel.calculateStats()
                }
            )
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let unit: String?
    let color: Color
    var isInteractive: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(color)

                    if let unit = unit {
                        Text(unit)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            if isInteractive {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(8)
            }
        }
        .background(Color(.systemGray5))
        .cornerRadius(20)
    }
}
    private func formatBasal(_ value: Double?) -> String {
        guard let value = value else { return "---" }
        return String(format: "%.2f", value)
    }

struct StatsGridView: View {
    @ObservedObject var simpleStats: SimpleStatsViewModel
    @Binding var showGMI: Bool
    @Binding var showStdDev: Bool
    @Binding var showFPU: Bool
    @Binding var showSMB: Bool
    @Binding var showProfileBasal: Bool

    private var hasInsulinData: Bool {
        simpleStats.totalDailyDose != nil || simpleStats.avgBolus != nil || simpleStats.actualBasal != nil
    }

    private var hasCarbData: Bool {
        simpleStats.avgCarbs != nil
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Button(action: {
                    showGMI.toggle()
                    Storage.shared.showGMI.value = showGMI
                }) {
                    StatCard(
                        title: showGMI ? "GMI" : "eA1c",
                        value: showGMI ? formatGMI(simpleStats.gmi) : formatEhbA1c(simpleStats.avgGlucose),
                        unit: showGMI ? "%" : (UserDefaultsRepository.units.value == "mg/dL" ? "%" : "mmol/mol"),
                        color: .primary,
                        isInteractive: true
                    )
                }
                .buttonStyle(PlainButtonStyle())

                StatCard(
                    title: "Medel glukos",
                    value: formatGlucose(simpleStats.avgGlucose),
                    unit: UserDefaultsRepository.units.value,
                    color: .primary
                )
            }

            HStack(spacing: 16) {
                Button(action: {
                    showStdDev.toggle()
                    Storage.shared.showStdDev.value = showStdDev
                }) {
                    StatCard(
                        title: showStdDev ? "Std Avvikelse" : "CV",
                        value: showStdDev ? formatStdDev(simpleStats.stdDeviation) : formatCV(simpleStats.coefficientOfVariation),
                        unit: showStdDev ? UserDefaultsRepository.units.value : "%",
                        color: .primary,
                        isInteractive: true
                    )
                }
                .buttonStyle(PlainButtonStyle())

                if hasCarbData {
                    Button(action: {
                        showFPU.toggle()
                        Storage.shared.showFPU.value = showFPU
                    }) {
                        StatCard(
                            title: showFPU ? "FPU" : "Kolhydrater",
                            value: formatCarbs(showFPU ? simpleStats.avgFPUCarbs : simpleStats.avgCarbs),
                            unit: "g/dag",
                            color: showFPU ? .brown : .orange,
                            isInteractive: true
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                }
            }

                HStack(spacing: 16) {
                    if hasInsulinData {
                        StatCard(
                            title: "Total Daglig Dos",
                            value: formatInsulin(simpleStats.totalDailyDose),
                            unit: "E",
                            color: .blue
                        )
                    }
                    if hasInsulinData {
                        StatCard(
                            title: "Total Bolus",
                            value: formatInsulin(simpleStats.avgBolus),
                            unit: "E/dag",
                            color: .blue
                        )
                    }
                }
            
            if hasInsulinData {
                HStack(spacing: 16) {
                    Button(action: {
                        showProfileBasal.toggle()
                        Storage.shared.showProfileBasal.value = showProfileBasal
                    }) {
                        StatCard(
                            title: showProfileBasal ? "Profilbasal" : "Levererad basal",
                            value: formatBasal(showProfileBasal ? simpleStats.programmedBasal : simpleStats.actualBasal),
                            unit: "E/dag",
                            color: showProfileBasal ? .gray : .blue,
                            isInteractive: true
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        showSMB.toggle()
                        Storage.shared.showSMB.value = showSMB
                    }) {
                        StatCard(
                            title: showSMB ? "SMB" : "Manuell bolus",
                            value: formatInsulin(showSMB ? simpleStats.avgSMB : simpleStats.avgManualBolus),
                            unit: "E/dag",
                            color: showSMB ? .cyan : .blue,
                            isInteractive: true
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.top, 12)
    }

    private func formatGMI(_ value: Double?) -> String {
        guard let value = value else { return "---" }
        return String(format: "%.1f", value)
    }

    private func formatEhbA1c(_ avgGlucose: Double?) -> String {
        guard let avgGlucose = avgGlucose else { return "---" }

        let avgGlucoseMgdL: Double
        if UserDefaultsRepository.units.value == "mg/dL" {
            avgGlucoseMgdL = avgGlucose
        } else {
            avgGlucoseMgdL = avgGlucose * 18.0182
        }

        let ehba1cPercent = (avgGlucoseMgdL + 46.7) / 28.7

        if UserDefaultsRepository.units.value == "mg/dL" {
            return String(format: "%.1f", ehba1cPercent)
        } else {
            let ehba1cMmolMol = (ehba1cPercent - 2.15) * 10.929
            return String(format: "%.0f", ehba1cMmolMol)
        }
    }

    private func formatGlucose(_ value: Double?) -> String {
        guard let value = value else { return "---" }
        if UserDefaultsRepository.units.value == "mg/dL" {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }

    private func formatStdDev(_ value: Double?) -> String {
        guard let value = value else { return "---" }
        if UserDefaultsRepository.units.value == "mg/dL" {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }

    private func formatInsulin(_ value: Double?) -> String {
        guard let value = value else { return "---" }
        return String(format: "%.2f", value)
    }

    private func formatCarbs(_ value: Double?) -> String {
        guard let value = value else { return "---" }
        return String(format: "%.0f", value)
    }

    private func formatCV(_ value: Double?) -> String {
        guard let value = value else { return "---" }
        return String(format: "%.1f", value)
    }
    private func formatBasal(_ value: Double?) -> String {
        guard let value = value else { return "---" }
        return String(format: "%.2f", value)
    }
}
