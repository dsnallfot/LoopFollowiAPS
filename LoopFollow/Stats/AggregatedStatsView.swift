// LoopFollow
// AggregatedStatsView.swift

import SwiftUI
import UIKit

@available(iOS 26.0, *)
struct AggregatedStatsView: View {
    @ObservedObject var viewModel: AggregatedStatsViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showGMI: Bool
    @State private var showStdDev: Bool
    @State private var showAvgGlucose: Bool
    @State private var showFPU: Bool
    @State private var showSMB: Bool
    @State private var showDextroAmount: Bool
    @State private var showProfileBasal: Bool
    @State private var showLowPercentage: Bool
    @State private var selectedPeriod: Int
    @State private var isLoadingData = false
    @State private var lastForcedReloadAt: Date? = nil
    private let forcedReloadThrottleSeconds: TimeInterval = 5 * 60
    @State private var showingDailyStats = false
    @State private var showAllTooltips = false
    @State private var tooltipResetToken = 0
    
    init(viewModel: AggregatedStatsViewModel) {
        self.viewModel = viewModel
        _showGMI = State(initialValue: Storage.shared.showGMI.value)
        _showStdDev = State(initialValue: Storage.shared.showStdDev.value)
        _showAvgGlucose = State(initialValue: Storage.shared.showAvgGlucose.value)
        _showFPU = State(initialValue: Storage.shared.showFPU.value)
        _showSMB = State(initialValue: Storage.shared.showSMB.value)
        _showDextroAmount = State(initialValue: Storage.shared.showDextroAmount.value)
        _showProfileBasal = State(initialValue: Storage.shared.showProfileBasal.value)
        _showLowPercentage = State(initialValue: Storage.shared.showLowPercentage.value)
        
        let savedPeriod = UserDefaults.standard.object(forKey: "AggregatedStatsSelectedPeriod") as? Int ?? 14
        _selectedPeriod = State(initialValue: savedPeriod)
        _dailyStatsVM = StateObject(wrappedValue: DailyStatsViewModel(
            dataService: viewModel.dataService,
            daysBack: 90,
            todayTDDOverride: nil
        ))
    }
    
    var body: some View {
        ZStack {
                ThemeBackground()
        if #available(iOS 16.0, *) {
            VStack(spacing: 0) {
                // Fixed segment picker header
                VStack(spacing: 8) {
                    Picker("Period", selection: $selectedPeriod) {
                        Text("Idag").tag(0)
                        Text("1 d").tag(1)
                        Text("3 d").tag(3)
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
                        refreshIfNeeded(forceReload: (newValue == 0 || newValue == 1))
                    }
                }
                //.background(Color(.systemBackground))
                .background(Color.clear)
                .zIndex(1)
                
                ScrollView {
                    VStack(spacing: 20) {
                        TIRView(viewModel: viewModel.tirStats)
                            .padding(.horizontal)
                            .padding(.top, 12)
                        
                        StatsGridView(
                            simpleStats: viewModel.simpleStats,
                            showGMI: $showGMI,
                            showStdDev: $showStdDev,
                            showAvgGlucose: $showAvgGlucose,
                            showFPU: $showFPU,
                            showSMB: $showSMB,
                            showDextroAmount: $showDextroAmount,
                            showProfileBasal: $showProfileBasal,
                            showLowPercentage: $showLowPercentage,
                            showAllTooltips: $showAllTooltips,
                            tooltipResetToken: $tooltipResetToken,
                            isTodayOnly: selectedPeriod == 0,
                            isOneDayOnly: selectedPeriod < 2,
                            showTrends: selectedPeriod != 90,
                            periodLabel: periodLabel(for: selectedPeriod)
                        )
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
                ToolbarItem(placement: .topBarLeading) {
                    if isLoadingData {
                        ProgressView()
                    } else {
                        Button(action: {
                            refreshIfNeeded(forceReload: true, overrideThrottle: true)
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        showAllTooltips.toggle()
                        if !showAllTooltips {
                            tooltipResetToken += 1
                        }
                    }) {
                        Image(systemName: showAllTooltips ? "ellipsis.bubble.fill" : "ellipsis.bubble")
                    }
                }
                
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingDailyStats = true
                    } label: {
                        Image(systemName: "tablecells")
                    }
                }
                
                ToolbarSpacer(placement: .topBarTrailing)
                
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Klar") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                refreshIfNeeded(forceReload: shouldForceReloadOnOpen)
            }
            .onChange(of: scenePhase) { newPhase in
                guard newPhase == .active else { return }
                if shouldForceReloadOnOpen {
                    refreshIfNeeded(forceReload: true)
                }
            }
            .sheet(isPresented: $showingDailyStats) {
                DailyStatsView(viewModel: dailyStatsVM)
            }
        } else {
            // Fallback on earlier versions
        }
    }
}
    
    private var shouldForceReloadOnOpen: Bool {
        // Kort fönster = volatil statistik => alltid hämta senaste när vyn visas
        selectedPeriod == 0 || selectedPeriod == 1
    }

    private func refreshIfNeeded(forceReload: Bool, overrideThrottle: Bool = false) {
        // Prevent overlapping reloads from rapid taps/period switching
        guard !isLoadingData else { return }

        let now = Date()
        let shouldForce: Bool
        if forceReload {
            if overrideThrottle {
                shouldForce = true
                lastForcedReloadAt = now
            } else if let last = lastForcedReloadAt, now.timeIntervalSince(last) < forcedReloadThrottleSeconds {
                // Too soon since last forced reload; fall back to cached/ensureDataAvailable
                shouldForce = false
            } else {
                shouldForce = true
                lastForcedReloadAt = now
            }
        } else {
            shouldForce = false
        }

        isLoadingData = true
        DispatchQueue.main.async {
            viewModel.updatePeriod(selectedPeriod, forceReload: shouldForce) {
                isLoadingData = false
            }
        }
    }
    
    @StateObject private var dailyStatsVM = DailyStatsViewModel(
        dataService: .placeholder,
        daysBack: 90,
        todayTDDOverride: nil
    )

    private func periodLabel(for period: Int) -> String {
        switch period {
        case 0:
            return "idag"
        case 1:
            return "1 dag"
        case 3:
            return "3 dagar"
        case 7:
            return "7 dagar"
        case 14:
            return "14 dagar"
        case 30:
            return "30 dagar"
        case 90:
            return "90 dagar"
        default:
            return "föregående period"
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let unit: String?
    let color: Color
    var isInteractive: Bool = false
    var trendArrow: StatsTrendArrow? = nil
    var tooltipCurrent: Double? = nil
    var tooltipPrevious: Double? = nil
    var periodLabel: String? = nil
    @Binding var showAllTooltips: Bool
    @Binding var tooltipResetToken: Int

    @State private var showTooltip: Bool = false
    private var isTooltipVisible: Bool {
        showAllTooltips || showTooltip
    }

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

                    Spacer(minLength: 4)

                    if let arrow = trendArrow, arrow != .none {
                        Text(arrow.rawValue)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(color)
                            .padding(.leading, 4)
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
        .background(Color(.systemBackground.withAlphaComponent(0.5)))
        .cornerRadius(15)
        .overlay {
            if isTooltipVisible {
                ZStack {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color(uiColor: .systemBlue))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(title)
                                .font(.caption)
                                .fontWeight(.bold)
                                .tint(.primary)
                            Spacer()
                            if let arrow = trendArrow, arrow != .none {
                                Text(arrow.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    //.foregroundColor(color)
                                    .foregroundColor(.primary)
                            }
                        }
                        if let arrow = trendArrow, arrow != .none {
                            if let percentText = tooltipPercentChangeText {
                                Text(percentText)
                                    .font(.caption2)
                                    .tint(.primary)
                            } else {
                                Text("Ingen trenddata")
                                    .font(.caption2)
                                    .tint(.primary)
                            }
                        } else {
                            Text("Ingen trenddata")
                                .font(.caption2)
                                .tint(.primary)
                        }

                        if let pair = tooltipValuePair {
                            /*Text("Förändring:")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .tint(.primary)*/

                            Text(tooltipChangeString(for: pair))
                                .font(.caption2)
                                .tint(.primary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onLongPressGesture {
            withAnimation {
                showTooltip.toggle()
            }
        }
        .onChange(of: tooltipResetToken) { _ in
            showTooltip = false
        }
    }

    private var tooltipValuePair: (prev: Double, curr: Double)? {
        if let current = tooltipCurrent,
           let previous = tooltipPrevious,
           previous != 0 {
            return (previous, current)
        }
        return nil
    }

    private var tooltipPercentChangeText: String? {
        guard let pair = tooltipValuePair else { return nil }
        let pct = (pair.curr - pair.prev) / pair.prev * 100.0
        
        let rawLabel = periodLabel ?? "föregående period"
        let label: String
        let format: String
        
        switch rawLabel {
        case "idag":
            // För idag jämför vi mot samma tidsfönster igår
            label = "igår"
            format = "%+.1f%% vs samma tid %@"
        case "1 dag":
            // För 1 dag använder vi igår utan "fg"
            label = "24 timmar"
            format = "%+.1f%% vs fg %@"
        default:
            // Standardtext för övriga perioder
            label = rawLabel
            format = "%+.1f%% vs fg %@"
        }
        
        return String(format: format, pct, label)
    }
    
    private func tooltipChangeString(for pair: (prev: Double, curr: Double)) -> String {
        if let unit = unit {
            return String(format: "%.1f ⇢ %.1f %@", pair.prev, pair.curr, unit)
        } else {
            return String(format: "%.1f ⇢ %.1f", pair.prev, pair.curr)
        }
    }
}
    /*private func formatBasal(_ value: Double?) -> String {
        guard let value = value else { return "---" }
        return String(format: "%.2f", value)
    }*/

struct StatsGridView: View {
    @ObservedObject var simpleStats: SimpleStatsViewModel
    @Binding var showGMI: Bool
    @Binding var showStdDev: Bool
    @Binding var showAvgGlucose: Bool
    @Binding var showFPU: Bool
    @Binding var showSMB: Bool
    @Binding var showDextroAmount: Bool
    @Binding var showProfileBasal: Bool
    @Binding var showLowPercentage: Bool
    @Binding var showAllTooltips: Bool
    @Binding var tooltipResetToken: Int
    let isTodayOnly: Bool
    let isOneDayOnly: Bool
    let showTrends: Bool
    let periodLabel: String

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
                    // Beräkna GMI/eHbA1c för nuvarande och föregående period
                    let currentGMI = gmiValue(from: simpleStats.avgGlucose)
                    let previousGMI = gmiValue(from: simpleStats.prevAvgGlucose)
                    let currentEHb = eHbA1cPercent(from: simpleStats.avgGlucose)
                    let previousEHb = eHbA1cPercent(from: simpleStats.prevAvgGlucose)

                    let arrow: StatsTrendArrow? = {
                        guard showTrends else { return nil }
                        if showGMI {
                            return StatsTrendCalculator.arrow(current: currentGMI, previous: previousGMI)
                        } else {
                            return StatsTrendCalculator.arrow(current: currentEHb, previous: previousEHb)
                        }
                    }()

                    StatCard(
                        title: showGMI ? "GMI" : "eA1c",
                        value: showGMI
                            ? formatGMI(simpleStats.gmi)
                            : formatEhbA1c(simpleStats.avgGlucose),
                        unit: showGMI ? "%"
                             : (UserDefaultsRepository.units.value == "mg/dL" ? "%" : "mmol/mol"),
                        color: .primary,
                        isInteractive: true,
                        trendArrow: arrow,
                        tooltipCurrent: showGMI ? currentGMI : currentEHb,
                        tooltipPrevious: showGMI ? previousGMI : previousEHb,
                        periodLabel: periodLabel,
                        showAllTooltips: $showAllTooltips,
                        tooltipResetToken: $tooltipResetToken
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                    Button(action: {
                        showAvgGlucose.toggle()
                        Storage.shared.showAvgGlucose.value = showAvgGlucose
                    }) {
                        StatCard(
                            title: showAvgGlucose ? "Medel glukos" : "Högsta glukos",
                            value: showAvgGlucose ? formatGlucose(simpleStats.avgGlucose) : formatGlucose(simpleStats.highGlucose),
                            unit: UserDefaultsRepository.units.value,
                            color: .primary,
                            isInteractive: true,
                            trendArrow: showTrends
                                ? (showAvgGlucose ? simpleStats.avgGlucoseTrend : simpleStats.highGlucoseTrend)
                                : nil,
                            tooltipCurrent: showAvgGlucose ? simpleStats.avgGlucose : simpleStats.highGlucose,
                            tooltipPrevious: showAvgGlucose ? simpleStats.prevAvgGlucose : simpleStats.prevHighGlucose,
                            periodLabel: periodLabel,
                            showAllTooltips: $showAllTooltips,
                            tooltipResetToken: $tooltipResetToken
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
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
                        isInteractive: true,
                        trendArrow: showTrends
                            ? (showStdDev ? simpleStats.stdDeviationTrend : simpleStats.cvTrend)
                            : nil,
                        tooltipCurrent: showStdDev ? simpleStats.stdDeviation : simpleStats.coefficientOfVariation,
                        tooltipPrevious: showStdDev ? simpleStats.prevStdDeviation : simpleStats.prevCoefficientOfVariation,
                        periodLabel: periodLabel,
                        showAllTooltips: $showAllTooltips,
                        tooltipResetToken: $tooltipResetToken
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                if hasCarbData {
                    StatCard(
                        title: "Verklig insulinkvot",
                        value: formatCarbRatio(simpleStats.realCarbRatio),
                        unit: "g/E",
                        color: .mint,
                        trendArrow: showTrends ? simpleStats.realCarbRatioTrend : nil,
                        tooltipCurrent: simpleStats.realCarbRatio,
                        tooltipPrevious: simpleStats.prevRealCarbRatio,
                        periodLabel: periodLabel,
                        showAllTooltips: $showAllTooltips,
                        tooltipResetToken: $tooltipResetToken
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
                    color: .blue,
                    trendArrow: showTrends ? simpleStats.totalDailyDoseTrend : nil,
                    tooltipCurrent: simpleStats.totalDailyDose,
                    tooltipPrevious: simpleStats.prevTotalDailyDose,
                    periodLabel: periodLabel,
                    showAllTooltips: $showAllTooltips,
                    tooltipResetToken: $tooltipResetToken
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
                        isInteractive: true,
                        trendArrow: showTrends ? simpleStats.avgCarbsTrend : nil,
                        tooltipCurrent: showFPU ? simpleStats.avgFPUCarbs : simpleStats.avgCarbs,
                        tooltipPrevious: showFPU ? simpleStats.prevAvgFPUCarbs : simpleStats.prevAvgCarbs,
                        periodLabel: periodLabel,
                        showAllTooltips: $showAllTooltips,
                        tooltipResetToken: $tooltipResetToken
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
                        trendArrow: showTrends ? simpleStats.avgBolusTrend : nil,
                        tooltipCurrent: simpleStats.avgBolus,
                        tooltipPrevious: simpleStats.prevAvgBolus,
                        periodLabel: periodLabel,
                        showAllTooltips: $showAllTooltips,
                        tooltipResetToken: $tooltipResetToken
                    )
                    StatCard(
                        title: "Måltidsbolus Netto",
                        value: formatInsulin(simpleStats.netMealBolus),
                        unit: isTodayOnly || isOneDayOnly ? "E" : "E/dag",
                        color: .mint,
                        trendArrow: showTrends ? simpleStats.netMealBolusTrend : nil,
                        tooltipCurrent: simpleStats.netMealBolus,
                        tooltipPrevious: simpleStats.prevNetMealBolus,
                        periodLabel: periodLabel,
                        showAllTooltips: $showAllTooltips,
                        tooltipResetToken: $tooltipResetToken
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
                            isInteractive: true,
                            trendArrow: showTrends
                                ? (showProfileBasal ? simpleStats.programmedBasalTrend : simpleStats.actualBasalTrend)
                                : nil,
                            tooltipCurrent: showProfileBasal ? simpleStats.programmedBasal : simpleStats.actualBasal,
                            tooltipPrevious: showProfileBasal ? simpleStats.prevProgrammedBasal : simpleStats.prevActualBasal,
                            periodLabel: periodLabel,
                            showAllTooltips: $showAllTooltips,
                            tooltipResetToken: $tooltipResetToken
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
                            isInteractive: true,
                            trendArrow: showTrends
                                ? (showSMB ? simpleStats.avgSMBTrend : simpleStats.avgManualBolusTrend)
                                : nil,
                            tooltipCurrent: showSMB ? simpleStats.avgSMB : simpleStats.avgManualBolus,
                            tooltipPrevious: showSMB ? simpleStats.prevAvgSMB : simpleStats.prevAvgManualBolus,
                            periodLabel: periodLabel,
                            showAllTooltips: $showAllTooltips,
                            tooltipResetToken: $tooltipResetToken
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
                HStack(spacing: 16) {
                        Button(action: {
                            showLowPercentage.toggle()
                            Storage.shared.showLowPercentage.value = showLowPercentage
                        }) {
                        StatCard(
                            title: showLowPercentage ? "Låga glukosvärden" : "Fingerstick",
                            value: showLowPercentage ? formatGlucose(simpleStats.avgLowPercentage) : formatBGCheck(simpleStats.avgBGCheck),
                            unit: showLowPercentage ? "%" : isTodayOnly || isOneDayOnly ? "st" : "st/dag",
                            color: .red,
                            isInteractive: true,
                            trendArrow: showTrends
                                ? (showLowPercentage ? simpleStats.avgLowPercentageTrend : simpleStats.avgBGCheckTrend)
                                : nil,
                            tooltipCurrent: showLowPercentage ? simpleStats.avgLowPercentage : simpleStats.avgBGCheck,
                            tooltipPrevious: showLowPercentage ? simpleStats.prevAvgLowPercentage : simpleStats.prevAvgBGCheck,
                            periodLabel: periodLabel,
                            showAllTooltips: $showAllTooltips,
                            tooltipResetToken: $tooltipResetToken
                        )
                        .buttonStyle(PlainButtonStyle())
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
                                isInteractive: true,
                                trendArrow: showTrends
                                    ? (showDextroAmount ? simpleStats.avgLowTreatmentAmountTrend
                                                        : simpleStats.avgLowTreatmentsTrend)
                                    : nil,
                                tooltipCurrent: showDextroAmount ? simpleStats.avgLowTreatmentAmount : simpleStats.avgLowTreatments,
                                tooltipPrevious: showDextroAmount ? simpleStats.prevAvgLowTreatmentAmount : simpleStats.prevAvgLowTreatments,
                                periodLabel: periodLabel,
                                showAllTooltips: $showAllTooltips,
                                tooltipResetToken: $tooltipResetToken
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                }
        }
        //.padding(.top, 12)
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
    
    private func gmiValue(from avgGlucose: Double?) -> Double? {
        guard let avgGlucose = avgGlucose else { return nil }

        let avgGlucoseMgdL: Double
        if UserDefaultsRepository.units.value == "mg/dL" {
            avgGlucoseMgdL = avgGlucose
        } else {
            avgGlucoseMgdL = avgGlucose * 18.0182
        }

        // GMI i % enligt din formel
        return 3.31 + (0.02392 * avgGlucoseMgdL)
    }

    private func eHbA1cPercent(from avgGlucose: Double?) -> Double? {
        guard let avgGlucose = avgGlucose else { return nil }

        let avgGlucoseMgdL: Double
        if UserDefaultsRepository.units.value == "mg/dL" {
            avgGlucoseMgdL = avgGlucose
        } else {
            avgGlucoseMgdL = avgGlucose * 18.0182
        }
        
        let ehba1cPercent = (avgGlucoseMgdL + 46.7) / 28.7

        if UserDefaultsRepository.units.value == "mg/dL" {
            return ehba1cPercent
        } else {
            let ehba1cMmolMol = (ehba1cPercent - 2.15) * 10.929
            return ehba1cMmolMol
        }


        // eHbA1c i % (samma grund som din formatter använder innan ev mmol/mol-konvertering)
        //return (avgGlucoseMgdL + 46.7) / 28.7
    }
}
