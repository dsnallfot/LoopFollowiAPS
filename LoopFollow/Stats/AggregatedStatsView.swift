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
    @State private var showDextroAmount: Bool
    @State private var showProfileBasal: Bool
    @State private var selectedPeriod: Int
    @State private var isLoadingData = false

    init(viewModel: AggregatedStatsViewModel) {
        self.viewModel = viewModel
        _showGMI = State(initialValue: Storage.shared.showGMI.value)
        _showStdDev = State(initialValue: Storage.shared.showStdDev.value)
        _showFPU = State(initialValue: Storage.shared.showFPU.value)
        _showSMB = State(initialValue: Storage.shared.showSMB.value)
        _showDextroAmount = State(initialValue: Storage.shared.showDextroAmount.value)
        _showProfileBasal = State(initialValue: Storage.shared.showProfileBasal.value)

        let savedPeriod = UserDefaults.standard.object(forKey: "AggregatedStatsSelectedPeriod") as? Int ?? 14
        _selectedPeriod = State(initialValue: savedPeriod)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed segment picker header
            VStack(spacing: 8) {
                Picker("Period", selection: $selectedPeriod) {
                    Text("Idag").tag(0)
                    Text("1 d").tag(1)
                    Text("7 d").tag(7)
                    Text("14 d").tag(14)
                    Text("30 d").tag(30)
                    Text("90 d").tag(90)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .onChange(of: selectedPeriod) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "AggregatedStatsSelectedPeriod")
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
                        showDextroAmount: $showDextroAmount,
                        showProfileBasal: $showProfileBasal,
                        isTodayOnly: selectedPeriod == 0,
                        isOneDayOnly: selectedPeriod < 2
                    )
                    .padding(.horizontal)
                    
                    TIRView(viewModel: viewModel.tirStats)
                        .padding(.horizontal)

                    AGPView(viewModel: viewModel.agpStats)
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
                Button(action: {
                    isLoadingData = true
                    viewModel.updatePeriod(selectedPeriod, forceReload: true) {
                        isLoadingData = false
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Klar") {
                    dismiss()
                }
            }
        }
        .onAppear {
            isLoadingData = true
            viewModel.updatePeriod(selectedPeriod, forceReload: true) {
                isLoadingData = false
            }
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
    @Binding var showDextroAmount: Bool
    @Binding var showProfileBasal: Bool
    let isTodayOnly: Bool
    let isOneDayOnly: Bool

    private var hasInsulinData: Bool {
        simpleStats.totalDailyDose != nil || simpleStats.avgBolus != nil || simpleStats.actualBasal != nil
    }

    private var hasCarbData: Bool {
        simpleStats.avgCarbs != nil
    }
    
    private var hasBGCheckData: Bool {
        simpleStats.avgBGCheck != nil
    }
    
    private var hasLowTreatmentsData: Bool {
        simpleStats.avgLowTreatments != nil
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
                    StatCard(
                        title: "Verklig insulinkvot",
                        value: formatCarbRatio(simpleStats.realCarbRatio),
                        unit: "g/E",
                        color: .mint
                    )
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                }
            }
            if hasInsulinData && hasCarbData {
            HStack(spacing: 16) {
                StatCard(
                    title: isTodayOnly ? "Insulin Totalt" : "Insulin Totalt (TDD)",
                    value: formatInsulin(simpleStats.totalDailyDose),
                    unit: isTodayOnly || isOneDayOnly ? "E" : "E/dag",
                    color: .blue
                )
                Button(action: {
                    showFPU.toggle()
                    Storage.shared.showFPU.value = showFPU
                }) {
                    StatCard(
                        title: showFPU ? "Varav FPU" : "Kolhydrater Totalt",
                        value: formatCarbs(showFPU ? simpleStats.avgFPUCarbs : simpleStats.avgCarbs),
                        unit: isTodayOnly || isOneDayOnly ? "g" : "g/dag",
                        color: showFPU ? .brown : .orange,
                        isInteractive: true
                    )
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
            
            if hasInsulinData && hasCarbData {
                HStack(spacing: 16) {
                            StatCard(
                                title: "Bolus Totalt",
                                value: formatInsulin(simpleStats.avgBolus),
                                unit: isTodayOnly || isOneDayOnly ? "E" : "E/dag",
                                color: .blue,
                            )
                    StatCard(
                        title: "Måltidsbolus Netto",
                        value: formatInsulin(simpleStats.netMealBolus),
                        unit: isTodayOnly || isOneDayOnly ? "E" : "E/dag",
                        color: .mint,
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
                            title: showProfileBasal ? "Profilbasal" : "Levererad Basal",
                            value: formatBasal(showProfileBasal ? simpleStats.programmedBasal : simpleStats.actualBasal),
                            unit: isTodayOnly || isOneDayOnly ? "E" : "E/dag",
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
                            title: showSMB ? "SMB" : "Manuell Bolus",
                            value: formatInsulin(showSMB ? simpleStats.avgSMB : simpleStats.avgManualBolus),
                            unit: isTodayOnly || isOneDayOnly ? "E" : "E/dag",
                            color: showSMB ? .cyan : .indigo,
                            isInteractive: true
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                
                    
                }
            }
            
                HStack(spacing: 16) {
                    if hasBGCheckData {
                        StatCard(
                            title: "Fingerstick",
                            value: formatBGCheck(simpleStats.avgBGCheck),
                            unit: isTodayOnly || isOneDayOnly ? "st" : "st/dag",
                            color: .red
                        )
                    }
                    if hasLowTreatmentsData {
                        Button(action: {
                            showDextroAmount.toggle()
                            Storage.shared.showDextroAmount.value = showDextroAmount
                        }) {
                            StatCard(
                                title: showDextroAmount ? "Dextro Mängd" : "Dextro Behandlingar",
                                value: showDextroAmount ? formatCarbs(simpleStats.avgLowTreatmentAmount)
                                                        : formatLowTreatment(simpleStats.avgLowTreatments),
                                unit: showDextroAmount ? (isTodayOnly || isOneDayOnly ? "g" : "g/dag")
                                                       : (isTodayOnly || isOneDayOnly ? "ggr" : "ggr/dag"),
                                color: .red,
                                isInteractive: true
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
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
    private func formatCarbRatio(_ value: Double?) -> String {
        guard let value = value else { return "---" }
        return String(format: "%.1f", value)
    }
    private func formatLowTreatment(_ value: Double?) -> String {
        guard let value = value else { return "---" }
        if isTodayOnly || isOneDayOnly {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
    private func formatBGCheck(_ value: Double?) -> String {
        guard let value = value else { return "---" }
        if isTodayOnly || isOneDayOnly {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
}
