// LoopFollow
// DailyStatsView.swift

import SwiftUI
import UIKit
import WebKit
import Charts

@available(iOS 26.0, *)
struct DailyStatsView: View {
    @ObservedObject var viewModel: DailyStatsViewModel
    var showsDoneButton: Bool = true
    @Environment(\.dismiss) private var dismiss
    
    @State private var exportURL: URL?
    @State private var showingTitrSummary: Bool = true
    @State private var selectedDateForReport: Date?
    @State private var showNightscoutAlert: Bool = false
    @State private var showNightscoutReport: Bool = false
    @State private var showDatabaseInfo: Bool = false
    @State private var showWeekdayFilter: Bool = false
    @State private var showRealCRandTitrChart: Bool = false
    @State private var showClippyHistoryStats: Bool = false
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = " yy-MM-dd"
        return df
    }()
    
    // Kolumnbredder för raka marginaler – proportionella mot skärmbredden (efter 10 pt horisontell padding)
    private let totalBaseColumnWidth: CGFloat = 356 // 26+54+36+36+36+30+30+30+32+36+10
    
    private func scaledColumnWidth(base: CGFloat) -> CGFloat {
        // Tillgänglig bredd efter 10 pt padding på vardera sida (matchar .padding(.horizontal, 10))
        let screenWidth = UIScreen.main.bounds.width
        let availableWidth = max(screenWidth - 30, 0)
        return (base / totalBaseColumnWidth) * availableWidth
    }
    
    private var weekdayWidth: CGFloat { scaledColumnWidth(base: 26) }
    private var dateWidth: CGFloat { scaledColumnWidth(base: 54) }
    private var carbsWidth: CGFloat { scaledColumnWidth(base: 35) }
    private var insulinWidth: CGFloat { scaledColumnWidth(base: 35) }
    private var meanWidth: CGFloat { scaledColumnWidth(base: 36) }
    private var lowWidth: CGFloat { scaledColumnWidth(base: 30) }
    private var titrWidth: CGFloat { scaledColumnWidth(base: 30) }
    private var tirWidth: CGFloat { scaledColumnWidth(base: 30) }
    private var stdWidth: CGFloat { scaledColumnWidth(base: 32) }
    private var profileWidth: CGFloat { scaledColumnWidth(base: 35) }
    private var emojiWidth: CGFloat { scaledColumnWidth(base: 14) }
    
    private let columnSpacing: CGFloat = 1
    
    @available(iOS 26.0, *)
    var body: some View {
        ZStack {
            ThemeBackground()
            coreContent
                .navigationTitle("Dag")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showWeekdayFilter = true
                        } label: {
                            let (symbolName, symbolColor): (String, Color) = {
                                if viewModel.usePumpChangeDays {
                                    // Pumpbytesdagar-filter aktivt
                                    return ("fuelpump", .blue)
                                }
                                if viewModel.useSensorChangeDays {
                                    // Sensorbytesdagar-filter aktivt
                                    return ("sensor.tag.radiowaves.forward", .blue)
                                }
                                if viewModel.useSickDays {
                                    // Sjukdagar-filter aktivt
                                    return ("medical.thermometer", .blue)
                                }
                                if viewModel.useNonSickDays {
                                    // Ej sjukdagar-filter aktivt
                                    return ("figure.taichi", .blue)
                                }

                                let weekdayCount = viewModel.selectedWeekdays.count
                                switch weekdayCount {
                                case 7:
                                    // Alla dagar valda – standardkalender, neutral färg
                                    return ("7.calendar", .primary)
                                case 0:
                                    // Inga dagar valda – varna med badge
                                    return ("calendar.badge.exclamationmark", .blue)
                                case 1...6:
                                    // 1–6 dagar valda – använd siffra + kalender
                                    return ("\(weekdayCount).calendar", .blue)
                                default:
                                    // Fallback
                                    return ("calendar", .primary)
                                }
                            }()
                            
                            Image(systemName: symbolName)
                                .foregroundColor(symbolColor)
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if let url = viewModel.writeCSVToDisk() {
                                exportURL = url
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showDatabaseInfo = true
                        } label: {
                            Image(systemName: "internaldrive")
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showClippyHistoryStats = true
                        } label: {
                            Image(systemName: "target")
                        }
                    }
                    
                    ToolbarSpacer(placement: .topBarTrailing)

                    if showsDoneButton {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Klar") {
                                dismiss()
                            }
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        viewModel.loadDailyStats()
                    }
                    LogManager.shared.log(
                        category: .analysis,
                        message: "SUMMARY appear – rows=\(viewModel.rows.count), sufficient=\(viewModel.rowsWithSufficientGlucose.count), daysToAnalyze=\(viewModel.dataService.daysToAnalyze)",
                        isDebug: true
                    )
                }
                .sheet(isPresented: $showClippyHistoryStats) {
                    ClippyHistoryView()
                }
                .sheet(
                    isPresented: Binding(
                        get: { exportURL != nil },
                        set: { isPresented in
                            if !isPresented {
                                exportURL = nil
                            }
                        }
                    )
                ) {
                    if let url = exportURL {
                        ActivityView(activityItems: [url])
                    }
                }
                .sheet(isPresented: $showDatabaseInfo) {
                    databaseInfoContent
                }
                .sheet(isPresented: $showWeekdayFilter) {
                    NavigationStack {
                        WeekdayFilterView(
                            selectedWeekdays: Binding(
                                get: { viewModel.selectedWeekdays },
                                set: { viewModel.selectedWeekdays = $0 }
                            ),
                            usePumpChangeDays: Binding(
                                get: { viewModel.usePumpChangeDays },
                                set: { viewModel.usePumpChangeDays = $0 }
                            ),
                            useSensorChangeDays: Binding(
                                get: { viewModel.useSensorChangeDays },
                                set: { viewModel.useSensorChangeDays = $0 }
                            ),
                            useSickDays: Binding(
                                get: { viewModel.useSickDays },
                                set: { viewModel.useSickDays = $0 }
                            ),
                            useNonSickDays: Binding(
                                get: { viewModel.useNonSickDays },
                                set: { viewModel.useNonSickDays = $0 }
                            )
                        )
                        .navigationTitle("Filtrera tabellen")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
                .fullScreenCover(isPresented: $showNightscoutReport) {
                    if let date = selectedDateForReport {
                        NightscoutDayReportView(date: date)
                    }
                }
                .alert("Fel", isPresented: .constant(viewModel.errorMessage != nil), actions: {
                    Button("OK", role: .cancel) { viewModel.errorMessage = nil }
                }, message: {
                    Text(viewModel.errorMessage ?? "")
                })
                .overlay(nightscoutAlertOverlay)
        }
    }
    
    struct HighlightInfo {
        let bestID: AnyHashable?
        let worstID: AnyHashable?
    }

    @ViewBuilder
    private var coreContent: some View {
        // För-highlighting av bästa/sämsta dag baserat på aktuell TITR/TIR-vy
        let daysInScope = viewModel.numberOfDaysInScope
        
        // Samma filtrering som tabellen använder (endast dagar med tightRangePercent)
        let filteredRowsForHighlight = viewModel.filteredRowsForDisplay
            .filter { $0.tightRangePercent != nil }
        
        let highlightInfo: HighlightInfo = {
            // Endast highlight om vi har fler än 1 dag (dvs 7, 14, 30, 90 – inte 1 dag)
            guard daysInScope > 1 else {
                return HighlightInfo(bestID: nil, worstID: nil)
            }
            
            // Välj rätt procent att optimera på: TITR eller TIR beroende på showingTitrSummary
            let metricRows: [(AnyHashable, Double)] = filteredRowsForHighlight.compactMap { row in
                let metric = showingTitrSummary ? row.tightRangePercent : row.timeInRangePercent
                guard let metric else { return nil }
                return (AnyHashable(row.id), metric)
            }
            
            guard metricRows.count > 1 else {
                return HighlightInfo(bestID: nil, worstID: nil)
            }
            
            let best = metricRows.max(by: { $0.1 < $1.1 })
            let worst = metricRows.min(by: { $0.1 < $1.1 })
            
            return HighlightInfo(bestID: best?.0, worstID: worst?.0)
        }()
        Group {
            if viewModel.isLoading && viewModel.rows.isEmpty {
                ProgressView("Beräknar daglig statistik…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    averagesSection
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                    summarySection
                        .padding(.horizontal, 15)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 0) {
                        headerRow
                            .padding(.vertical, 6)
                        Divider()

                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(filteredRowsForHighlight.enumerated()), id: \.element.id) { index, row in
                                    HStack(spacing: columnSpacing) {
                                        Text(weekdaySymbol(for: row.date))
                                            .frame(width: weekdayWidth, alignment: .leading)
                                            .font(.system(size: 10, weight: .semibold).monospaced())
                                            .foregroundColor(.secondary)
                                        
                                        Text(dateFormatter.string(from: row.date))
                                            .frame(width: dateWidth, alignment: .center)
                                            .font(.system(size: 10).monospacedDigit())
                                        
                                        numberCell(row.totalCarbs, width: carbsWidth, decimals: 0)
                                        numberCell(row.insulinTDD, width: insulinWidth)
                                        meanCell(row.meanGlucoseMmol)
                                        lowCell(row.lowPercent)
                                        titrCell(row.tightRangePercent)
                                        tirCell(row.timeInRangePercent)
                                        stdDevCell(stdDev: row.stdDevMmol, mean: row.meanGlucoseMmol)
                                        numberCell(row.profileBasal, width: profileWidth)
                                        emojiCell(row.emojiDayInfo, width: emojiWidth)
                                    }
                                    .padding(.vertical, 8)
                                    .background({
                                        // Bas: varannan rad ljusgrå
                                        let baseColor: Color = index % 2 == 0
                                        ? Color(.systemGray.withAlphaComponent(0.15))
                                        : Color.clear
                                        
                                        // Highlight: bästa / sämsta dag enligt aktuell TITR/TIR-vy
                                        let isBest = highlightInfo.bestID != nil && AnyHashable(row.id) == highlightInfo.bestID
                                        let isWorst = highlightInfo.worstID != nil && AnyHashable(row.id) == highlightInfo.worstID
                                        
                                        if isBest {
                                            return Color.green.opacity(0.25)
                                        } else if isWorst {
                                            return Color.red.opacity(0.25)
                                        } else {
                                            return baseColor
                                        }
                                    }())
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedDateForReport = row.date
                                        showNightscoutAlert = true
                                    }
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.top, 10)

                    // Bar chart (TDD + KH) for the same days as the table
                    if !filteredRowsForHighlight.isEmpty {
                        Divider()
                            .padding(.horizontal, 15)

                        dailyBarsSection(rows: filteredRowsForHighlight)
                            .padding(.horizontal, 15)
                            .padding(.top, 15)
                            .padding(.bottom, 12)
                    }
                }
            }
        }
    }

    // Öppnar MealAnalysisView för den valda dagen med start kl 00:00
    private func presentLoopFollowDayReport() {
        guard let selectedDateForReport else { return }

        // Säkerställ att vi använder dagens start (00:00)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDateForReport)
        let endOfDay = startOfDay + 24 * 60 * 60

        // Hitta MainViewController via root UITabBarController för att bygga events
        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first(where: { $0.isKeyWindow }),
            let tabBar = window.rootViewController as? UITabBarController,
            let tabViewControllers = tabBar.viewControllers
        else {
            return
        }

        var mainVC: MainViewController?

        for vc in tabViewControllers {
            if let nav = vc as? UINavigationController {
                if let candidate = nav.viewControllers.first(where: { $0 is MainViewController }) as? MainViewController {
                    mainVC = candidate
                    break
                }
            } else if let candidate = vc as? MainViewController {
                mainVC = candidate
                break
            }
        }

        guard let mainVC else { return }

        // Bygg events via MainViewController
        let events = mainVC.buildEventsForMealAnalysis()

        let analysisVC = MealAnalysisView(
            events: events,
            initialStart: startOfDay,
            initialEnd: endOfDay,
            modalWithTimestamp: true,
            modalTitleString: "Dagens utfall",
            preSelectedSegment: nil
        )
        let nav = UINavigationController(rootViewController: analysisVC)
        nav.modalPresentationStyle = .formSheet

        // Presentera från den översta vyn (t.ex. DailyStatsView's hosting controller),
        // så att vi kommer tillbaka hit när modalen stängs.
        if let rootVC = window.rootViewController {
            let presenter = DailyStatsView.topViewController(from: rootVC)
            presenter?.present(nav, animated: true)
        }
    }

    private var nightscoutAlertOverlay: some View {
        Color.clear
            .allowsHitTesting(false)
            .alert(
                "Visa dagsrapport?",
                isPresented: $showNightscoutAlert
            ) {
                Button("Avbryt", role: .cancel) { }
                Button("Visa i Loop Follow") {
                    presentLoopFollowDayReport()
                }
                Button("Öppna i Nightscout") {
                    showNightscoutReport = true
                }
            } message: {
                if let date = selectedDateForReport {
                    Text("Datum: \(dateFormatter.string(from: date))")
                } else {
                    Text("Visa daglig rapport.")
                }
            }
    }

    @ViewBuilder
    private var databaseInfoContent: some View {
        NavigationStack {
            ZStack {
                ThemeBackground()

                VStack(spacing: 16) {
                    if let mainVC = viewModel.mainViewController {
                        // Formatter for date/time rows
                        let dateTimeFormatter: DateFormatter = {
                            let df = DateFormatter()
                            df.dateFormat = "yyyy-MM-dd HH:mm"
                            return df
                        }()

                        // Precompute texts to keep the view tree simple
                        let lastUpdatedText: String = {
                            if let lastUpdated = mainVC.statsCacheLastUpdated {
                                return dateTimeFormatter.string(from: lastUpdated)
                            } else {
                                return "—"
                            }
                        }()

                        let oldestTimestamp: TimeInterval? = {
                            let oldestBG = mainVC.statsBGData.min(by: { $0.date < $1.date })?.date
                            let oldestBolus = mainVC.statsBolusData.min(by: { $0.date < $1.date })?.date
                            let oldestSMB = mainVC.statsSMBData.min(by: { $0.date < $1.date })?.date
                            let oldestCarb = mainVC.statsCarbData.min(by: { $0.date < $1.date })?.date
                            let oldestBasal = mainVC.statsBasalData.min(by: { $0.date < $1.date })?.date
                            let oldestBGCheck = mainVC.statsBGCheckData.min()

                            return [oldestBG, oldestBolus, oldestSMB, oldestCarb, oldestBasal, oldestBGCheck]
                                .compactMap { $0 }
                                .min()
                        }()

                        let oldestEntryText: String = {
                            if let oldest = oldestTimestamp {
                                let oldestDate = Date(timeIntervalSince1970: oldest)
                                return dateTimeFormatter.string(from: oldestDate)
                            } else {
                                return "—"
                            }
                        }()

                        let newestTimestamp: TimeInterval? = {
                            let newestBG = mainVC.statsBGData.max(by: { $0.date < $1.date })?.date
                            let newestBolus = mainVC.statsBolusData.max(by: { $0.date < $1.date })?.date
                            let newestSMB = mainVC.statsSMBData.max(by: { $0.date < $1.date })?.date
                            let newestCarb = mainVC.statsCarbData.max(by: { $0.date < $1.date })?.date
                            let newestBasal = mainVC.statsBasalData.max(by: { $0.date < $1.date })?.date
                            let newestBGCheck = mainVC.statsBGCheckData.max()

                            return [newestBG, newestBolus, newestSMB, newestCarb, newestBasal, newestBGCheck]
                                .compactMap { $0 }
                                .max()
                        }()

                        let newestEntryText: String = {
                            if let newest = newestTimestamp {
                                let newestDate = Date(timeIntervalSince1970: newest)
                                return dateTimeFormatter.string(from: newestDate)
                            } else {
                                return "—"
                            }
                        }()

                        // Metadata rows
                        Group {
                            HStack {
                                Text("Databas uppdaterad:")
                                Spacer()
                                Text(lastUpdatedText)
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Äldsta post:")
                                Spacer()
                                Text(oldestEntryText)
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Nyaste post:")
                                Spacer()
                                Text(newestEntryText)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.footnote)

                        Divider()
                            .padding(.vertical, 4)

                        // Content rows with leading label and trailing value
                        Group {
                            HStack {
                                Text("Glukosavläsningar:")
                                Spacer()
                                Text("\(mainVC.statsBGData.count) st")
                            }
                            HStack {
                                Text("Fingerstick:")
                                Spacer()
                                Text("\(mainVC.statsBGCheckData.count) st")
                            }
                            HStack {
                                Text("Manuell bolus:")
                                Spacer()
                                Text("\(mainVC.statsBolusData.count) st")
                            }
                            HStack {
                                Text("SMB:")
                                Spacer()
                                Text("\(mainVC.statsSMBData.count) st")
                            }
                            HStack {
                                Text("Måltider (Kolhydrater):")
                                Spacer()
                                Text("\(mainVC.statsCarbData.count) st")
                            }
                            HStack {
                                Text("Temp basal:")
                                Spacer()
                                Text("\(mainVC.statsBasalData.count) st")
                            }
                        }
                        .font(.body)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Group {
                            HStack {
                                Text("Glukosavläsningar per dag:")
                                Spacer()
                                Text(String(format: "%.0f st", Double(mainVC.statsBGData.count) / 91.0))
                            }
                            HStack {
                                Text("Fingerstick per dag:")
                                Spacer()
                                Text(String(format: "%.1f st", Double(mainVC.statsBGCheckData.count) / 91.0))
                            }
                            HStack {
                                Text("Manuell bolus per dag:")
                                Spacer()
                                Text(String(format: "%.0f st", Double(mainVC.statsBolusData.count) / 91.0))
                            }
                            HStack {
                                Text("SMB per dag:")
                                Spacer()
                                Text(String(format: "%.0f st", Double(mainVC.statsSMBData.count) / 91.0))
                            }
                            HStack {
                                Text("Måltider (Kolhydrater) per dag:")
                                Spacer()
                                Text(String(format: "%.0f st", Double(mainVC.statsCarbData.count) / 91.0))
                            }
                            HStack {
                                Text("Temp basal per dag:")
                                Spacer()
                                Text(String(format: "%.0f st", Double(mainVC.statsBasalData.count) / 91.0))
                            }
                        }
                        .font(.body)

                    } else {
                        Text("Ingen data tillgänglig.")
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Databasens innehåll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Klar") {
                        showDatabaseInfo = false
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    // MARK: - Bar Chart (TDD + Carbs)

    private func dailyBarsSection(rows: [DailyStatRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if showRealCRandTitrChart {
                    Text(showingTitrSummary ? "TITR" : "TIR")
                        .fontWeight(.semibold)
                        .font(.subheadline)
                        .foregroundColor(Color.green.opacity(0.85))
                    Text("och")
                        .fontWeight(.medium)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text("Verklig insulinkvot")
                        .fontWeight(.semibold)
                        .font(.subheadline)
                        .foregroundColor(Color(.mint).opacity(0.9))
                    Text("per dag")
                        .fontWeight(.medium)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                } else {
                    Text("TDD")
                        .fontWeight(.semibold)
                        .font(.subheadline)
                        .foregroundColor(Color(UIColor.insulin).opacity(0.9))
                    Text("och")
                        .fontWeight(.medium)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text("Kolhydrater")
                        .fontWeight(.semibold)
                        .font(.subheadline)
                        .foregroundColor(Color(UIColor.carbs).opacity(0.9))
                    Text("per dag")
                        .fontWeight(.medium)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.up.chevron.down")
                    .foregroundColor(.secondary)
                    .fontWeight(.regular)
                    .font(.system(size: 14))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRealCRandTitrChart.toggle()
                }
            }

            if showRealCRandTitrChart {
                RealCRandTITRChartView(rows: rows, showingTitrSummary: showingTitrSummary)
                    .frame(height: 180)
                    .clipped()
            } else {
                DailyCarbsTDDBarChartView(rows: rows)
                    .frame(height: 180)
                    .clipped()
            }
        }
    }

    private var summarySection: some View {
        let daysInScope = viewModel.numberOfDaysInScope
        let daysMeetingTitr = viewModel.numberOfDaysMeetingTitrTarget
        let daysMeetingTir = viewModel.numberOfDaysMeetingTirTarget
        let titrThresholdPercentString = String(format: "%.0f%%", viewModel.titrTargetThreshold * 100)
        let tirThresholdPercentString = String(format: "%.0f%%", viewModel.tirTargetThreshold * 100)
        let daysInScopeString = "\(daysInScope)"
        let daysMeetingTitrString = "\(daysMeetingTitr)"
        let daysMeetingTirString = "\(daysMeetingTir)"

        return Group {
            if daysInScope > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        VStack(alignment: .leading, spacing: 4) {
                            // Rad 1: “Du nådde ditt mål på XX% tid i ...”
                            HStack(spacing: 0) {
                                Text("Du nådde målet ")
                                Text(showingTitrSummary ? titrThresholdPercentString : tirThresholdPercentString)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.green.opacity(0.8))
                                Text(showingTitrSummary ? " tid i tight målområde" : " tid i målområde ")
                                Spacer(minLength: 0)

                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundColor(.secondary)
                            }

                            // Rad 2: intervallet i grått
                            HStack(spacing: 0) {
                            Text(showingTitrSummary ? "(3.9–7.8 mmol/L) " : "(3.9–10.0 mmol/L) ")
                                .foregroundColor(.secondary)
                                Text("under ")
                                Text(showingTitrSummary ? daysMeetingTitrString : daysMeetingTirString)
                                    .fontWeight(.bold)
                                Text(" av ")
                                Text(daysInScopeString)
                                    .fontWeight(.bold)
                                Text(" dagar.")
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)

                    if showingTitrSummary {
                        titrStreakBar
                    } else {
                        tirStreakBar
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingTitrSummary.toggle()
                    }
                }
            } else {
                Text("Ingen daglig statistik att visa ännu.")
            }
        }
        .font(.system(size: 14))
        .multilineTextAlignment(.leading)
    }

    /// Visar en enkel streak/gap-rad där varje dag i perioden representeras av en stapel.
    /// Grön = dag når TITR-målet, transparent = dag under målet.
    /// Endast dagar där vi har TITR-data (tightRangePercent != nil) ritas ut.
    private var titrStreakBar: some View {
        // Sortera dagar i kronologisk ordning (äldst till nyast) för vänster-till-höger-läsning
        // och filtrera bort dagar utan TITR-data.
        let filteredRows = viewModel.filteredRowsForDisplay
            .sorted { $0.date < $1.date }
            .filter { $0.tightRangePercent != nil }

        let barHeight: CGFloat = 15
        let barSpacing: CGFloat = 1

        return GeometryReader { geometry in
            let count = max(filteredRows.count, 1)
            let totalSpacing = barSpacing * CGFloat(max(count - 1, 0))
            let barWidth = max((geometry.size.width - totalSpacing) / CGFloat(count), 2)

            HStack(spacing: barSpacing) {
                ForEach(Array(filteredRows.enumerated()), id: \.offset) { _, row in
                    let meetsTarget = ((row.tightRangePercent ?? 0) / 100.0) >= viewModel.titrTargetThreshold

                    Rectangle()
                        .fill(meetsTarget ? Color.green.opacity(0.8) : Color.red.opacity(0.7))
                        .frame(width: barWidth, height: barHeight)
                        .overlay(
                            Rectangle()
                                .stroke(Color.green.opacity(0.2), lineWidth: 0.5)
                        )
                }
            }
        }
        .frame(height: barHeight)
    }
    
    private var tirStreakBar: some View {
        // Sortera dagar i kronologisk ordning (äldst till nyast) för vänster-till-höger-läsning
        // och filtrera bort dagar utan TITR-data.
        let filteredRows = viewModel.filteredRowsForDisplay
            .sorted { $0.date < $1.date }
            .filter { $0.timeInRangePercent != nil }

        let barHeight: CGFloat = 15
        let barSpacing: CGFloat = 1

        return GeometryReader { geometry in
            let count = max(filteredRows.count, 1)
            let totalSpacing = barSpacing * CGFloat(max(count - 1, 0))
            let barWidth = max((geometry.size.width - totalSpacing) / CGFloat(count), 2)

            HStack(spacing: barSpacing) {
                ForEach(Array(filteredRows.enumerated()), id: \.offset) { _, row in
                    let meetsTarget = ((row.timeInRangePercent ?? 0) / 100.0) >= viewModel.tirTargetThreshold

                    Rectangle()
                        .fill(meetsTarget ? Color.green.opacity(0.8) : Color.red.opacity(0.7))
                        .frame(width: barWidth, height: barHeight)
                        .overlay(
                            Rectangle()
                                .stroke(Color.green.opacity(0.2), lineWidth: 0.5)
                        )
                }
            }
        }
        .frame(height: barHeight)
    }

    private var headerRow: some View {
        HStack(spacing: columnSpacing) {
            Text("Dag")
                .frame(width: weekdayWidth, alignment: .leading)
                .font(.system(size: 10, weight: .semibold))

            Text("Datum")
                .frame(width: dateWidth, alignment: .center)
                .font(.system(size: 10, weight: .semibold))

            Text("KH")
                .frame(width: carbsWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("TDD")
                .frame(width: insulinWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("Medel")
                .frame(width: meanWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("Låg")
                .frame(width: lowWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("TITR")
                .frame(width: titrWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))
            
            Text("TIR")
                .frame(width: tirWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("StdAv")
                .frame(width: stdWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("Basal")
                .frame(width: profileWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))
        }
    }

    private func numberCell(
        _ value: Double?,
        width: CGFloat,
        decimals: Int = 1,
        foregroundColor: Color? = nil
    ) -> some View {
        Group {
            if let value = value {
                Text(String(format: "%.\(decimals)f", value))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(foregroundColor ?? .primary)
            } else {
                Text("—")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: width, alignment: .trailing)
    }
    
    private func emojiCell(
        _ value: String?,
        width: CGFloat,
        decimals: Int = 0,
        foregroundColor: Color? = nil
    ) -> some View {
        let emoji: String = {
            guard let value else { return "" }
            let normalized = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

            if normalized.contains("magsjuka") {
                return "🤢"
            }
            if normalized.contains("forkyld") {
                return "🤧"
            }

            let words = normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }

            if words.contains("sjuk") {
                return "🤒"
            }
            return ""
        }()

        return Group {
            Text(emoji)
                .font(.system(size: 11))
        }
        .frame(width: width, alignment: .trailing)
    }

    private func lowCell(_ value: Double?) -> some View {
        let color: Color
        if let value = value {
            let fraction = value / 100.0
            if fraction <= viewModel.lowGlucoseGreatThreshold {
                color = .green
            } else if fraction <= viewModel.lowGlucoseOKThreshold {
                color = .orange
            } else {
                color = .red
            }
        } else {
            color = .secondary
        }
        return numberCell(value, width: lowWidth, decimals: 1, foregroundColor: color)
    }

    private func titrCell(_ value: Double?) -> some View {
        let color: Color
        //if showingTitrSummary {
            if let value = value {
                let fraction = value / 100.0
                color = fraction >= viewModel.titrTargetThreshold ? .green : .red
            } else {
                color = .secondary
            }
        //} else {
        //    color = .secondary
        //}
        return numberCell(value, width: titrWidth, decimals: 0, foregroundColor: color)
    }
    
    private func tirCell(_ value: Double?) -> some View {
        let color: Color
        //if !showingTitrSummary {
        if let value = value {
            let fraction = value / 100.0
            color = fraction >= viewModel.tirTargetThreshold ? .green : .red
        } else {
            color = .secondary
        }
        //} else {
        //    color = .secondary
        //}
        return numberCell(value, width: tirWidth, decimals: 0, foregroundColor: color)
    }

    private func meanCell(_ value: Double?) -> some View {
        let color: Color
        if let value = value {
            if value <= viewModel.bgAverageGreatThreshold {
                color = .green
            } else if value <= viewModel.bgAverageOKThreshold {
                color = .orange
            } else {
                color = .red
            }
        } else {
            color = .secondary
        }
        return numberCell(value, width: meanWidth, decimals: 1, foregroundColor: color)
    }

    private func stdDevCell(stdDev: Double?, mean: Double?) -> some View {
        let color: Color
        if let stdDev = stdDev, stdDev > 0 {
            if stdDev <= viewModel.stdDevGreatThreshold {
                color = .green
            } else if stdDev <= viewModel.stdDevOkThreshold {
                color = .orange
            } else {
                color = .red
            }
        } else {
            color = .secondary
        }
        return numberCell(stdDev, width: stdWidth, decimals: 1, foregroundColor: color)
    }
    /// Hjälpfunktion för att hitta den översta presenterade viewcontrollern,
    /// oavsett om vi är i en TabBar, NavigationController eller presenterad stack.
    private static func topViewController(from root: UIViewController?) -> UIViewController? {
        if let nav = root as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }
    
    // MARK: - Averages Section

    private var averagesSection: some View {
        // Vi baserar oss på samma scope som tabellen (rowsWithSufficientGlucose)
        let avgCarbs = viewModel.averageCarbs
        let avgTDD = viewModel.averageTDD
        let avgMean = viewModel.averageMeanGlucose
        let avgLow = viewModel.averageLowPercent
        let avgTitr = viewModel.averageTitr
        let avgTir = viewModel.averageTir
        let avgStd = viewModel.averageStdDev
        //let avgBasal = viewModel.averageProfileBasal

        return HStack(spacing: 0) {
            averageBadge(
                title: "KH",
                value: avgCarbs.map { String(format: "%.0f g", $0) } ?? "—",
                background: Color(UIColor.carbs).opacity(avgCarbs == nil ? 0.25 : 0.8)
            )

            Spacer(minLength: 0)

            averageBadge(
                title: "TDD",
                value: avgTDD.map { String(format: "%.1f E", $0) } ?? "—",
                background: Color(UIColor.insulin).opacity(avgTDD == nil ? 0.25 : 0.8)
            )
            
            Spacer(minLength: 0)
/*
            averageBadge(
                title: "Basal",
                value: avgBasal.map { String(format: "%.1f E", $0) } ?? "—",
                background: Color(UIColor.insulin).opacity(avgBasal == nil ? 0.25 : 0.8)
            )

            Spacer(minLength: 0)
*/
            // Medel BG
            let meanColor: Color = {
                guard let v = avgMean else { return .gray.opacity(0.4) }
                if v <= viewModel.bgAverageGreatThreshold {
                    return .green.opacity(0.8)
                } else if v <= viewModel.bgAverageOKThreshold {
                    return .orange.opacity(0.8)
                } else {
                    return .red.opacity(0.8)
                }
            }()
            averageBadge(
                title: "MEDEL",
                value: avgMean.map { String(format: "%.1f", $0) } ?? "—",
                background: meanColor
            )

            Spacer(minLength: 0)

            // Låg %
            let lowColor: Color = {
                guard let p = avgLow else { return .gray.opacity(0.4) }
                let fraction = (p / 100.0)
                if fraction <= viewModel.lowGlucoseGreatThreshold {
                    return .green.opacity(0.8)
                } else if fraction <= viewModel.lowGlucoseOKThreshold {
                    return .orange.opacity(0.8)
                } else {
                    return .red.opacity(0.8)
                }
            }()

            // TITR / TIR (beroende på showingTitrSummary)
            let titrText = avgTitr.map { String(format: "%.0f %%", $0) } ?? "—"
            let tirText = avgTir.map { String(format: "%.0f %%", $0) } ?? "—"
            let combinedText = showingTitrSummary ? titrText : tirText
            let titrTirColor: Color = {
                if showingTitrSummary {
                    guard let p = avgTitr else { return .gray.opacity(0.4) }
                    let fraction = p / 100.0
                    return fraction >= viewModel.titrTargetThreshold ? .green.opacity(0.8) : .red.opacity(0.8)
                } else {
                    guard let p = avgTir else { return .gray.opacity(0.4) }
                    let fraction = p / 100.0
                    return fraction >= viewModel.tirTargetThreshold ? .green.opacity(0.8) : .red.opacity(0.8)
                }
            }()
            
            averageBadge(
                title: "LÅG",
                value: avgLow.map { String(format: "%.1f %%", $0) } ?? "—",
                background: lowColor
            )

            Spacer(minLength: 0)
            
            averageBadge(
                title: showingTitrSummary ? "TITR" : "TIR",
                value: combinedText,
                background: titrTirColor
            )

            Spacer(minLength: 0)

            // Std Av
            let stdColor: Color = {
                guard let s = avgStd else { return .gray.opacity(0.4) }
                if s <= viewModel.stdDevGreatThreshold {
                    return .green.opacity(0.8)
                } else if s <= viewModel.stdDevOkThreshold {
                    return .orange.opacity(0.8)
                } else {
                    return .red.opacity(0.8)
                }
            }()
            averageBadge(
                title: "STD.AV",
                value: avgStd.map { String(format: "%.1f", $0) } ?? "—",
                background: stdColor
            )
        }
        .frame(height: 35)
    }

    // MARK: - Average Badge Helper

    private func averageBadge(title: String, value: String, background: Color) -> some View {
        ZStack {
            Capsule()
                .fill(background)
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                Text(value)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: 56, height: 35) // utan basal-pill
        //.frame(width: 47, height: 32) // med basal-pill
    }

}


// MARK: - DailyCarbsTDDBarChartView

@available(iOS 26.0, *)
private struct DailyCarbsTDDBarChartView: UIViewRepresentable {
    let rows: [DailyStatRow]

    func makeUIView(context: Context) -> UIView {
        // IMPORTANT: we need touch handling for highlight + marker.
        // NonInteractiveContainerView blocks touches, so use a plain UIView.
        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.isUserInteractionEnabled = true

        let chartView = BarChartView()
        chartView.backgroundColor = .clear
        // Plot-area background (only inside the data/grid rect, not outside axes/labels)
        chartView.drawGridBackgroundEnabled = true
        chartView.gridBackgroundColor = UIColor.systemBackground.withAlphaComponent(0.5)
        chartView.drawBordersEnabled = false

        chartView.rightAxis.enabled = true
        chartView.leftAxis.enabled = true

        chartView.chartDescription.enabled = false
        chartView.legend.enabled = false

        chartView.isUserInteractionEnabled = true
        chartView.drawMarkers = true

        // Disable zoom/scale
        chartView.pinchZoomEnabled = false
        chartView.doubleTapToZoomEnabled = false
        chartView.scaleXEnabled = false
        chartView.scaleYEnabled = false

        // Highlight on tap
        chartView.highlightPerTapEnabled = true
        chartView.highlightFullBarEnabled = false

        // Axes
        let xAxis = chartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.drawAxisLineEnabled = false
        xAxis.drawGridLinesEnabled = true
        xAxis.gridLineWidth = 0.5
        xAxis.gridColor = NSUIColor.label.withAlphaComponent(0.15)
        xAxis.granularityEnabled = true
        // Important for grouped bars: center labels under each day-group
        xAxis.centerAxisLabelsEnabled = true

        let leftAxis = chartView.leftAxis
        leftAxis.drawAxisLineEnabled = false
        leftAxis.drawGridLinesEnabled = false
        leftAxis.axisMinimum = 0

        let rightAxis = chartView.rightAxis
        rightAxis.drawAxisLineEnabled = false
        rightAxis.drawGridLinesEnabled = false
        rightAxis.axisMinimum = 0

        // Marker
        chartView.marker = DailyBarsMarker(font: .systemFont(ofSize: 11, weight: .semibold))

        containerView.addSubview(chartView)
        chartView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chartView.topAnchor.constraint(equalTo: containerView.topAnchor),
            chartView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            chartView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            chartView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        return containerView
    }

    func updateUIView(_ containerView: UIView, context: Context) {
        guard let chartView = containerView.subviews.first as? BarChartView else { return }

        let calendar = Calendar.current
        let sorted = rows.sorted { $0.date < $1.date }
        let n = sorted.count

        guard n > 0 else {
            chartView.data = nil
            chartView.notifyDataSetChanged()
            chartView.setNeedsDisplay()
            return
        }

        // Prepare x labels dd/MM with <= 7 labels (evenly spread)
        let dateFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "dd/MM"
            return df
        }()
        let labels = sorted.map { dateFormatter.string(from: $0.date) }

        let labelIndices: [Int] = {
            guard n > 0 else { return [] }
            if n <= 7 { return Array(0..<n) }

            // Aim for exactly 7 indices, evenly spread across 0...(n-1)
            var out: [Int] = []
            out.reserveCapacity(7)
            for i in 0..<7 {
                let t = Double(i) / 6.0
                let idx = Int((t * Double(n - 1)).rounded())
                out.append(max(0, min(n - 1, idx)))
            }

            // De-dupe while preserving order
            var seen = Set<Int>()
            var unique: [Int] = []
            for i in out {
                if seen.insert(i).inserted { unique.append(i) }
            }

            // If rounding caused fewer than 7, fill by stepping forward
            var cursor = 0
            while unique.count < 7 && unique.count < n {
                if !seen.contains(cursor) {
                    unique.append(cursor)
                    seen.insert(cursor)
                }
                cursor += 1
            }
            return unique.sorted()
        }()


        // Build entries
        let tddEntries: [BarChartDataEntry] = sorted.enumerated().map { idx, row in
            BarChartDataEntry(x: Double(idx), y: row.insulinTDD ?? 0)
        }
        let carbsEntries: [BarChartDataEntry] = sorted.enumerated().map { idx, row in
            BarChartDataEntry(x: Double(idx), y: row.totalCarbs ?? 0)
        }

        // Y axis ranges with top margin
        let maxTDD = (sorted.compactMap { $0.insulinTDD }.max() ?? 0)
        let maxCarbs = (sorted.compactMap { $0.totalCarbs }.max() ?? 0)
        let leftMax = max(1, maxTDD * 1.12)
        let rightMax = max(1, maxCarbs * 1.12)

        chartView.leftAxis.axisMaximum = leftMax
        chartView.rightAxis.axisMaximum = rightMax

        // Data sets
        let tddSet = BarChartDataSet(entries: tddEntries, label: "TDD")
        tddSet.axisDependency = .left
        tddSet.colors = [NSUIColor.insulin.withAlphaComponent(0.8)]
        tddSet.drawValuesEnabled = false
        tddSet.highlightEnabled = true

        let carbsSet = BarChartDataSet(entries: carbsEntries, label: "KH")
        carbsSet.axisDependency = .right
        carbsSet.colors = [NSUIColor.carbs.withAlphaComponent(0.8)]
        carbsSet.drawValuesEnabled = false
        carbsSet.highlightEnabled = true

        // Grouped bars
        let data = BarChartData(dataSets: [tddSet, carbsSet])
        let groupSpace = 0.26
        let barSpace = 0.04
        let barWidth = (1.0 - groupSpace) / 2.0 - barSpace
        data.barWidth = barWidth

        let startX = 0.0
        data.groupBars(fromX: startX, groupSpace: groupSpace, barSpace: barSpace)

        let groupWidth = data.groupWidth(groupSpace: groupSpace, barSpace: barSpace)

        // X-axis: one tick per day-group
        chartView.xAxis.granularity = groupWidth
        chartView.xAxis.axisMinimum = startX
        chartView.xAxis.axisMaximum = startX + groupWidth * Double(n)

        // Labels (<= 7 shown, evenly spread)
        // X-axis labels
        // Keep the existing behavior for <= 7 days (looks perfect), but hide labels entirely for larger ranges.
        if n <= 7 {
            chartView.xAxis.drawLabelsEnabled = true
            chartView.xAxis.valueFormatter = DailyBarsXAxisFormatter(
                labels: labels,
                shownIndices: Set(labelIndices),
                startX: startX,
                groupWidth: groupWidth
            )
            chartView.xAxis.setLabelCount(n, force: true)
        } else {
            // Hide labels for 14/30/90 etc. to avoid odd spacing artifacts.
            chartView.xAxis.drawLabelsEnabled = false
            chartView.xAxis.valueFormatter = DefaultAxisValueFormatter(block: { _, _ in "" })
            chartView.xAxis.setLabelCount(0, force: true)
        }

        chartView.xAxis.setLabelCount(min(7, n), force: false)

        // Ensure marker knows which chart it belongs to
        (chartView.marker as? MarkerView)?.chartView = chartView

        chartView.data = data
        chartView.notifyDataSetChanged()
        chartView.setNeedsDisplay()
    }
}

// MARK: - Real CR + TITR Line Chart

@available(iOS 26.0, *)
private struct RealCRandTITRChartView: UIViewRepresentable {
    let rows: [DailyStatRow]
    let showingTitrSummary: Bool

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.isUserInteractionEnabled = true

        let chartView = LineChartView()
        chartView.backgroundColor = .clear

        // Plot-area background (only inside the data/grid rect, not outside axes/labels)
        chartView.drawGridBackgroundEnabled = true
        chartView.gridBackgroundColor = UIColor.systemBackground.withAlphaComponent(0.5)
        chartView.drawBordersEnabled = false

        chartView.chartDescription.enabled = false
        chartView.legend.enabled = false

        chartView.isUserInteractionEnabled = true
        chartView.drawMarkers = true

        // Disable zoom/scale
        chartView.pinchZoomEnabled = false
        chartView.doubleTapToZoomEnabled = false
        chartView.scaleXEnabled = false
        chartView.scaleYEnabled = false

        // Highlight on tap
        chartView.highlightPerTapEnabled = true

        // X axis
        let xAxis = chartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.drawAxisLineEnabled = false
        xAxis.drawGridLinesEnabled = true
        xAxis.gridLineWidth = 0.5
        xAxis.gridColor = NSUIColor.label.withAlphaComponent(0.15)
        xAxis.granularityEnabled = true
        xAxis.granularity = 1

        // Left axis: TITR/TIR 0–100
        let leftAxis = chartView.leftAxis
        leftAxis.drawAxisLineEnabled = false
        leftAxis.drawGridLinesEnabled = true
        leftAxis.gridLineWidth = 0.5
        leftAxis.gridColor = NSUIColor.label.withAlphaComponent(0.12)
        leftAxis.axisMinimum = 0
        leftAxis.axisMaximum = 100
        leftAxis.granularityEnabled = true
        leftAxis.granularity = 20
        leftAxis.labelCount = 6
        leftAxis.valueFormatter = RealCRLeftAxisFormatter()

        // Right axis: Real CR (dynamic)
        let rightAxis = chartView.rightAxis
        rightAxis.drawAxisLineEnabled = false
        rightAxis.drawGridLinesEnabled = false
        rightAxis.axisMinimum = 0

        // Use a dedicated marker for this chart
        chartView.marker = RealCRandTITRMarker(font: .systemFont(ofSize: 11, weight: .semibold))

        containerView.addSubview(chartView)
        chartView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chartView.topAnchor.constraint(equalTo: containerView.topAnchor),
            chartView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            chartView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            chartView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        return containerView
    }

    func updateUIView(_ containerView: UIView, context: Context) {
        guard let chartView = containerView.subviews.first as? LineChartView else { return }

        let sorted = rows.sorted { $0.date < $1.date }
        let n = sorted.count

        guard n > 0 else {
            chartView.data = nil
            chartView.notifyDataSetChanged()
            chartView.setNeedsDisplay()
            return
        }

        // Prepare x labels dd/MM with <= 7 labels (evenly spread)
        let dateFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "dd/MM"
            return df
        }()
        let labels = sorted.map { dateFormatter.string(from: $0.date) }

        let shownIndices: Set<Int> = {
            guard n > 0 else { return [] }
            if n <= 7 { return Set(0..<n) }

            // Aim for ~7 shown indices evenly spread
            var out: [Int] = []
            out.reserveCapacity(7)
            for i in 0..<7 {
                let t = Double(i) / 6.0
                let idx = Int((t * Double(n - 1)).rounded())
                out.append(max(0, min(n - 1, idx)))
            }

            // De-dupe
            var seen = Set<Int>()
            var unique: [Int] = []
            for i in out where seen.insert(i).inserted {
                unique.append(i)
            }

            // Fill if fewer than 7
            var cursor = 0
            while unique.count < 7 && unique.count < n {
                if !seen.contains(cursor) {
                    unique.append(cursor)
                    seen.insert(cursor)
                }
                cursor += 1
            }

            return Set(unique)
        }()

        // TITR/TIR (%) on left axis
        let leftPercentEntries: [ChartDataEntry] = sorted.enumerated().compactMap { idx, row in
            let percent = showingTitrSummary ? row.tightRangePercent : row.timeInRangePercent
            guard let percent else { return nil }
            return ChartDataEntry(x: Double(idx), y: percent)
        }

        // Real CR on right axis: carbs / (tdd - profileBasal), rounded to 1 decimal
        let crEntries: [ChartDataEntry] = sorted.enumerated().compactMap { idx, row in
            guard
                let carbs = row.totalCarbs,
                let tdd = row.insulinTDD,
                let profileBasal = row.profileBasal
            else { return nil }

            let denominator = tdd - profileBasal
            guard denominator > 0 else { return nil }

            let realCR = carbs / denominator
            let rounded = (realCR * 10).rounded() / 10
            return ChartDataEntry(x: Double(idx), y: rounded)
        }

        // Right axis max
        let maxCR = max(0, crEntries.map { $0.y }.max() ?? 0)
        let rightMax = max(1, maxCR * 1.12)
        chartView.rightAxis.axisMaximum = rightMax
        chartView.rightAxis.labelCount = 5

        // Data sets styling
        let titrSet = LineChartDataSet(entries: leftPercentEntries, label: (showingTitrSummary ? "TITR" : "TIR"))
        titrSet.axisDependency = .left
        titrSet.colors = [NSUIColor.systemGreen]
        titrSet.lineWidth = 1.5
        titrSet.drawCirclesEnabled = true
        titrSet.circleRadius = 5

        // Conditional TITR/TIR point colors:
            // TITR -> green if >= 50%
            // TIR  -> green if >= 70%
            let threshold: Double = showingTitrSummary ? 50.0 : 70.0
            let titrCircleColors: [NSUIColor] = leftPercentEntries.map { entry in
                (entry.y >= threshold) ? NSUIColor.systemGreen : NSUIColor.systemRed
            }
        titrSet.circleColors = titrCircleColors

        titrSet.drawValuesEnabled = false
        titrSet.mode = .linear
        titrSet.highlightEnabled = true
        titrSet.drawCircleHoleEnabled = true
        titrSet.circleHoleRadius = 2
        titrSet.circleHoleColor = NSUIColor.white
        titrSet.drawHorizontalHighlightIndicatorEnabled = false
        titrSet.drawVerticalHighlightIndicatorEnabled = false

        let crSet = LineChartDataSet(entries: crEntries, label: "CR")
        crSet.axisDependency = .right
        crSet.colors = [NSUIColor.systemMint]
        crSet.lineWidth = 1.5
        crSet.drawCirclesEnabled = true
        crSet.circleRadius = 5
        crSet.circleColors = [NSUIColor.systemMint]
        crSet.drawValuesEnabled = false
        crSet.mode = .linear
        crSet.highlightEnabled = true
        crSet.drawCircleHoleEnabled = true
        crSet.circleHoleRadius = 2
        crSet.circleHoleColor = NSUIColor.white
        crSet.drawHorizontalHighlightIndicatorEnabled = false
        crSet.drawVerticalHighlightIndicatorEnabled = false

        let data = LineChartData(dataSets: [titrSet, crSet])

        // X-axis labels: keep <= 7 behavior, hide for larger ranges
        if n <= 7 {
            chartView.xAxis.drawLabelsEnabled = true
            chartView.xAxis.valueFormatter = RealCRXAxisFormatter(labels: labels, shownIndices: shownIndices)
            chartView.xAxis.setLabelCount(n, force: true)
        } else {
            chartView.xAxis.drawLabelsEnabled = false
            chartView.xAxis.valueFormatter = DefaultAxisValueFormatter(block: { _, _ in "" })
            chartView.xAxis.setLabelCount(0, force: true)
        }

        // Ensure marker knows which chart it belongs to
        (chartView.marker as? MarkerView)?.chartView = chartView

        chartView.data = data
        chartView.notifyDataSetChanged()
        chartView.setNeedsDisplay()
    }
}

private final class RealCRXAxisFormatter: AxisValueFormatter {
    private let labels: [String]
    private let shownIndices: Set<Int>

    init(labels: [String], shownIndices: Set<Int>) {
        self.labels = labels
        self.shownIndices = shownIndices
    }

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let idx = Int(value.rounded())
        guard idx >= 0, idx < labels.count else { return "" }
        return shownIndices.contains(idx) ? labels[idx] : ""
    }
}

private final class RealCRLeftAxisFormatter: AxisValueFormatter {
    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        // Show 0, 20, 40, 60, 80, 100
        let rounded = Int(value.rounded())
        if rounded % 20 != 0 { return "" }
        if rounded < 0 || rounded > 100 { return "" }
        return "\(rounded)"
    }
}

private final class RealCRandTITRMarker: MarkerView {
    private let label = UILabel()

    init(font: UIFont) {
        super.init(frame: CGRect(x: 0, y: 0, width: 78, height: 30))

        label.font = font
        label.textAlignment = .center
        label.textColor = .white
        backgroundColor = UIColor.systemGray4.withAlphaComponent(0.8)
        layer.cornerRadius = 6
        layer.borderWidth = 1
        layer.borderColor = UIColor.label.cgColor
        clipsToBounds = true

        addSubview(label)

        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func refreshContent(entry: ChartDataEntry, highlight: Highlight) {
        let value = entry.y

        // DataSets are added as: [TITR, Real CR]
        if highlight.dataSetIndex == 0 {
            // TITR
            label.text = String(format: "%.0f %%", value)
        } else {
            // Real CR
            label.text = String(format: "%.1f g/E", value)
        }

        layoutIfNeeded()
    }

    override func offsetForDrawing(atPoint point: CGPoint) -> CGPoint {
        // Center above the touched point
        let size = bounds.size
        return CGPoint(x: -size.width / 2, y: -size.height + 12)
    }
}

private final class DailyBarsMarker: MarkerView {
    private let label = UILabel()

    init(font: UIFont) {
        super.init(frame: CGRect(x: 0, y: 0, width: 60, height: 30))

        label.font = font
        label.textAlignment = .center
        label.textColor = .white
        backgroundColor = UIColor.systemGray4.withAlphaComponent(0.8)
        layer.cornerRadius = 6
        layer.borderWidth = 1
        layer.borderColor = UIColor.label.cgColor
        clipsToBounds = true
        
        addSubview(label)

        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func refreshContent(entry: ChartDataEntry, highlight: Highlight) {
        let value = entry.y
        if highlight.dataSetIndex == 0 {
            // TDD
            label.text = String(format: "%.1f E", value)
        } else {
            // KH
            label.text = String(format: "%.0f g", value)
        }
        layoutIfNeeded()
    }

    override func offsetForDrawing(atPoint point: CGPoint) -> CGPoint {
        // Center above the touched bar
        let size = bounds.size
        return CGPoint(x: -size.width / 2, y: -size.height + 12)
    }
}

private final class DailyBarsXAxisFormatter: AxisValueFormatter {
    private let labels: [String]
    private let shownIndices: Set<Int>
    private let startX: Double
    private let groupWidth: Double

    init(labels: [String], shownIndices: Set<Int>, startX: Double, groupWidth: Double) {
        self.labels = labels
        self.shownIndices = shownIndices
        self.startX = startX
        self.groupWidth = max(groupWidth, 0.0001)
    }

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        // With centered axis labels + grouped bars, x values are at day-group centers.
        // Map axis x -> day index using groupWidth.
        let raw = (value - startX) / groupWidth
        let idx = Int(raw.rounded())
        guard idx >= 0, idx < labels.count else { return "" }
        return shownIndices.contains(idx) ? labels[idx] : ""
    }
}

// MARK: - UIActivityViewController bridge

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

@available(iOS 16.0, *)
struct NightscoutDayReportView: View {
    let date: Date

    var body: some View {
        NightscoutDayReportControllerRepresentable(date: date)
            .ignoresSafeArea()
    }
}

struct NightscoutDayReportControllerRepresentable: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let date: Date

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = NightscoutDayReportViewController()
        vc.reportDate = date
        vc.onClose = { dismiss() }
        let nav = UINavigationController(rootViewController: vc)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        if let vc = uiViewController.viewControllers.first as? NightscoutDayReportViewController {
            vc.reportDate = date
        }
    }
}


    private func weekdaySymbol(for date: Date) -> String {
        switch Calendar.current.component(.weekday, from: date) {
        case 2: return " Mån"
        case 3: return " Tis"
        case 4: return " Ons"
        case 5: return " Tor"
        case 6: return " Fre"
        case 7: return " Lör"
        default: return " Sön"
        }
    }

@available(iOS 26.0, *)
private struct WeekdayFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedWeekdays: Set<Int>
    @Binding var usePumpChangeDays: Bool
    @Binding var useSensorChangeDays: Bool
    @Binding var useSickDays: Bool
    @Binding var useNonSickDays: Bool

    /// Mappar Calendar.weekday (1–7) till svenska kortnamn.
    private let weekdayOrder: [Int] = [2, 3, 4, 5, 6, 7, 1] // Mån–Sön i visningsordning
    private let weekdayLabels: [Int: String] = [
        1: "Sön",
        2: "Mån",
        3: "Tis",
        4: "Ons",
        5: "Tor",
        6: "Fre",
        7: "Lör"
    ]

    private var allWeekdaysSet: Set<Int> { Set(1...7) }

    private var anySpecialFilterActive: Bool {
        usePumpChangeDays || useSensorChangeDays || useSickDays || useNonSickDays
    }

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                // Rad 1: veckodagar + "Alla"
                VStack(alignment: .leading, spacing: 8) {
                    Text("Veckodagar")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        let allSelected = (selectedWeekdays == allWeekdaysSet) && !anySpecialFilterActive

                        // Alla-knapp
                        Button {
                            if allSelected {
                                // Avmarkera alla dagar
                                selectedWeekdays = []
                            } else {
                                // Markera alla dagar och slå av specialfilter
                                selectedWeekdays = allWeekdaysSet
                            }
                            usePumpChangeDays = false
                            useSensorChangeDays = false
                            useSickDays = false
                            useNonSickDays = false
                        } label: {
                            Text("Alla")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(width: 44, height: 32)
                                .background(
                                    Capsule()
                                        .fill(allSelected ? Color.accentColor : Color.gray.opacity(0.4))
                                )
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)

                        // Mån–Sön
                        ForEach(weekdayOrder, id: \.self) { weekday in
                            let isSelected = selectedWeekdays.contains(weekday) && !anySpecialFilterActive
                            Button {
                                if isSelected {
                                    // Tillåt att alla kan avmarkeras om man vill se en tom lista.
                                    selectedWeekdays.remove(weekday)
                                } else {
                                    selectedWeekdays.insert(weekday)
                                }
                                // Att manuellt pilla på veckodagar stänger av specialfilter
                                usePumpChangeDays = false
                                useSensorChangeDays = false
                                useSickDays = false
                                useNonSickDays = false
                            } label: {
                                Text(weekdayLabels[weekday] ?? "?")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(isSelected ? Color.accentColor : Color.gray.opacity(0.4))
                                    )
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Rad 2: Andra filter
                VStack(alignment: .leading, spacing: 8) {
                    Text("Andra filter")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Button(action: {
                            let newValue = !usePumpChangeDays
                            usePumpChangeDays = newValue

                            if newValue {
                                useSensorChangeDays = false
                                useSickDays = false
                                useNonSickDays = false
                                selectedWeekdays.removeAll()
                            } else if !useSensorChangeDays && !useSickDays && !useNonSickDays {
                                selectedWeekdays = allWeekdaysSet
                            }
                        }) {
                            HStack {
                                Text("Pumpbytesdagar")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                Capsule()
                                    .fill(usePumpChangeDays ? Color.accentColor : Color.gray.opacity(0.4))
                            )
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            let newValue = !useSensorChangeDays
                            useSensorChangeDays = newValue

                            if newValue {
                                usePumpChangeDays = false
                                useSickDays = false
                                useNonSickDays = false
                                selectedWeekdays.removeAll()
                            } else if !usePumpChangeDays && !useSickDays && !useNonSickDays {
                                selectedWeekdays = allWeekdaysSet
                            }
                        }) {
                            HStack {
                                Text("Sensorbytesdagar")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                Capsule()
                                    .fill(useSensorChangeDays ? Color.accentColor : Color.gray.opacity(0.4))
                            )
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 8) {
                        Button(action: {
                            let newValue = !useSickDays
                            useSickDays = newValue

                            if newValue {
                                usePumpChangeDays = false
                                useSensorChangeDays = false
                                useNonSickDays = false
                                selectedWeekdays.removeAll()
                            } else if !usePumpChangeDays && !useSensorChangeDays && !useNonSickDays {
                                selectedWeekdays = allWeekdaysSet
                            }
                        }) {
                            HStack {
                                Text("Sjukdagar")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                Capsule()
                                    .fill(useSickDays ? Color.accentColor : Color.gray.opacity(0.4))
                            )
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            let newValue = !useNonSickDays
                            useNonSickDays = newValue

                            if newValue {
                                usePumpChangeDays = false
                                useSensorChangeDays = false
                                useSickDays = false
                                selectedWeekdays.removeAll()
                            } else if !usePumpChangeDays && !useSensorChangeDays && !useSickDays {
                                selectedWeekdays = allWeekdaysSet
                            }
                        }) {
                            HStack {
                                Text("Ej sjukdagar")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                Capsule()
                                    .fill(useNonSickDays ? Color.accentColor : Color.gray.opacity(0.4))
                            )
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }

                Spacer()
            }
            .padding()
        }
    }
}

@available(iOS 26.0, *)
struct ClippyHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showStats = false

    private enum RowItem {
        case reached(ClippyDailyTargetHistoryEntry)
        case missed(Date)
    }

    private var sortedHistory: [ClippyDailyTargetHistoryEntry] {
        Storage.shared.clippyDailyTargetHistory.sorted { $0.date > $1.date }
    }

    private var rows: [RowItem] {
        guard !sortedHistory.isEmpty else { return [] }

        let calendar = Calendar.current
        var result: [RowItem] = []

        for index in sortedHistory.indices {
            let entry = sortedHistory[index]
            let entryDate = Date(timeIntervalSince1970: entry.date)
            result.append(.reached(entry))

            guard index < sortedHistory.count - 1 else { continue }

            let nextEntry = sortedHistory[index + 1]
            let nextDate = Date(timeIntervalSince1970: nextEntry.date)

            let currentStartOfDay = calendar.startOfDay(for: entryDate)
            let nextStartOfDay = calendar.startOfDay(for: nextDate)

            guard let daysBetween = calendar.dateComponents([.day], from: nextStartOfDay, to: currentStartOfDay).day,
                  daysBetween > 1 else {
                continue
            }

            for offset in 1..<daysBetween {
                if let missingDay = calendar.date(byAdding: .day, value: -offset, to: currentStartOfDay) {
                    result.append(.missed(missingDay))
                }
            }
        }

        return result
    }

    private static let rowFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "yyyy-MM-dd, HH:mm"
        return formatter
    }()

    private static let missedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                ThemeBackground()
                    .ignoresSafeArea()

                if rows.isEmpty {
                    ContentUnavailableView {
                        Label("Ingen Clippy-historik", systemImage: "star.fill")
                    } description: {
                        Text("Det finns inga sparade tider ännu.")
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                VStack(spacing: 0) {
                                    HStack(alignment: .center, spacing: 12) {
                                        switch row {
                                        case .reached(let entry):
                                            HStack(spacing: 8) {
                                                Image(systemName: "star.fill")
                                                    .foregroundStyle(.yellow)
                                                    .frame(width: 18)
                                                Text("Mål nåddes")
                                            }

                                            Spacer(minLength: 8)

                                            Text(Self.rowFormatter.string(from: Date(timeIntervalSince1970: entry.date)))
                                                .font(.system(size: 13).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.trailing)

                                        case .missed(let date):
                                            HStack(spacing: 8) {
                                                Image(systemName: "xmark")
                                                    .foregroundStyle(.red)
                                                    .frame(width: 18)
                                                Text("Mål nåddes ej")
                                            }

                                            Spacer(minLength: 8)

                                            Text("\(Self.missedFormatter.string(from: date)), 00:00")
                                                .font(.system(size: 13).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.trailing)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        presentLoopFollowDayReport(for: reportDate(for: row))
                                    }

                                    if index < rows.count - 1 {
                                        Divider().opacity(0.8)
                                            .padding(.leading, 44)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Daglig 12h TITR Målgång")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showStats = true
                    } label: {
                        Image(systemName: "chart.bar.xaxis.ascending")
                    }
                }
                ToolbarSpacer(placement: .topBarTrailing)
                
                ToolbarItemGroup(placement: .topBarTrailing) {

                    Button("Klar") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showStats) {
                ClippyHistoryStatsView()
            }
        }
    }
    
    private func reportDate(for row: RowItem) -> Date {
        switch row {
        case .reached(let entry):
            return Date(timeIntervalSince1970: entry.date)
        case .missed(let date):
            return date
        }
    }

    private func presentLoopFollowDayReport(for selectedDate: Date) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = startOfDay + 24 * 60 * 60

        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first(where: { $0.isKeyWindow }),
            let tabBar = window.rootViewController as? UITabBarController,
            let tabViewControllers = tabBar.viewControllers
        else {
            return
        }

        var mainVC: MainViewController?

        for vc in tabViewControllers {
            if let nav = vc as? UINavigationController {
                if let candidate = nav.viewControllers.first(where: { $0 is MainViewController }) as? MainViewController {
                    mainVC = candidate
                    break
                }
            } else if let candidate = vc as? MainViewController {
                mainVC = candidate
                break
            }
        }

        guard let mainVC else { return }

        let events = mainVC.buildEventsForMealAnalysis()

        let analysisVC = MealAnalysisView(
            events: events,
            initialStart: startOfDay,
            initialEnd: endOfDay,
            modalWithTimestamp: true,
            modalTitleString: "Dagens utfall",
            preSelectedSegment: nil
        )

        let nav = UINavigationController(rootViewController: analysisVC)
        nav.modalPresentationStyle = .formSheet

        if let rootVC = window.rootViewController {
            let presenter = topViewController(from: rootVC)
            presenter?.present(nav, animated: true)
        }
    }

    private func topViewController(from root: UIViewController?) -> UIViewController? {
        if let nav = root as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }
}

@available(iOS 26.0, *)
struct ClippyHistoryStatsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ClippyHistoryStatsViewControllerRepresentable()
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Klar") {
                            dismiss()
                        }
                    }
                }
                .navigationTitle("Daglig 12h TITR målgångstid")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

@available(iOS 26.0, *)
private struct ClippyHistoryStatsViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ClippyHistoryStatsViewController {
        ClippyHistoryStatsViewController()
    }

    func updateUIViewController(_ uiViewController: ClippyHistoryStatsViewController, context: Context) {
    }
}

@available(iOS 26.0, *)
private final class ClippyHistoryStatsViewController: ThemedTableViewController {

    private enum PeriodOption: CaseIterable {
        case d7, d14, d30, d90

        var days: Int {
            switch self {
            case .d7:  return 7
            case .d14: return 14
            case .d30: return 30
            case .d90: return 90
            }
        }

        var title: String {
            switch self {
            case .d7:  return "7 d"
            case .d14: return "14 d"
            case .d30: return "30 d"
            case .d90: return "90 d"
            }
        }
    }

    private let allHistory: [ClippyDailyTargetHistoryEntry] = Storage.shared.clippyDailyTargetHistory
        .sorted { $0.date < $1.date }

    private var selectedPeriod: PeriodOption = .d14
    private var selectedDays: [Date] = []
    private var reachedEntries: [ChartDataEntry] = []
    private var missedEntries: [ChartDataEntry] = []
    private var reachedHistoryByDay: [Date: ClippyDailyTargetHistoryEntry] = [:]

    private lazy var periodControl: UISegmentedControl = {
        let items = PeriodOption.allCases.map { $0.title }
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = PeriodOption.allCases.firstIndex(of: selectedPeriod) ?? 1
        sc.addTarget(self, action: #selector(periodChanged(_:)), for: .valueChanged)
        return sc
    }()

    private let timeChartView: ScatterChartView = {
        let v = ScatterChartView()
        v.chartDescription.enabled = false
        v.legend.enabled = true
        v.rightAxis.enabled = false
        v.minOffset = 8
        v.pinchZoomEnabled = false
        v.doubleTapToZoomEnabled = true
        v.scaleXEnabled = true
        v.scaleYEnabled = false
        v.dragEnabled = true
        v.highlightPerTapEnabled = false
        v.highlightPerDragEnabled = false
        v.drawMarkers = false
        v.maxVisibleCount = 1000000
        return v
    }()

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateBackgroundForCurrentMode()
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.isOpaque = false
        tableView.layer.backgroundColor = UIColor.clear.cgColor
        title = "Clippyhistorik"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ClippyHistoryStatsCell")

        setupChartHeader()
        applyPeriod(selectedPeriod)
    }

    private enum Row: Int, CaseIterable {
        case reachedPercentage
        case reachedDays
        case fastestReached
        case slowestReached
        case averageReached
        case longestReachedStreak
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    @objc private func periodChanged(_ sender: UISegmentedControl) {
        let index = sender.selectedSegmentIndex
        guard index >= 0 && index < PeriodOption.allCases.count else { return }
        applyPeriod(PeriodOption.allCases[index])
    }

    private func setupChartHeader() {
        let container = UIView()
        container.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 340)
        container.backgroundColor = .clear

        container.addSubview(periodControl)
        container.addSubview(timeChartView)

        periodControl.translatesAutoresizingMaskIntoConstraints = false
        timeChartView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            periodControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            periodControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            periodControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            timeChartView.topAnchor.constraint(equalTo: periodControl.bottomAnchor, constant: 12),
            timeChartView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            timeChartView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            timeChartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: 0),
        ])

        tableView.tableHeaderView = container
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let header = tableView.tableHeaderView {
            let targetSize = CGSize(width: tableView.bounds.width, height: 340)
            if header.frame.size != targetSize {
                header.frame.size = targetSize
                tableView.tableHeaderView = header
            }
        }
    }

    private func applyPeriod(_ period: PeriodOption) {
        selectedPeriod = period

        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())

        selectedDays = (0..<period.days).compactMap { offset in
            cal.date(byAdding: .day, value: -(period.days - 1 - offset), to: todayStart)
        }

        rebuildEntries()
        loadChartData()
        tableView.reloadData()
    }

    private func rebuildEntries() {
        let cal = Calendar.current
        let historyByDay: [Date: ClippyDailyTargetHistoryEntry] = Dictionary(
            uniqueKeysWithValues: allHistory.map { entry in
                let date = Date(timeIntervalSince1970: entry.date)
                return (cal.startOfDay(for: date), entry)
            }
        )

        reachedHistoryByDay = [:]
        reachedEntries = []
        missedEntries = []

        for (index, day) in selectedDays.enumerated() {
            if let entry = historyByDay[day] {
                reachedHistoryByDay[day] = entry

                let date = Date(timeIntervalSince1970: entry.date)
                let comps = cal.dateComponents([.hour, .minute, .second], from: date)
                let hour = Double(comps.hour ?? 0)
                let minute = Double(comps.minute ?? 0)
                let second = Double(comps.second ?? 0)
                let yValue = hour + (minute / 60.0) + (second / 3600.0)
                reachedEntries.append(ChartDataEntry(x: Double(index), y: yValue))
            } else {
                missedEntries.append(ChartDataEntry(x: Double(index), y: 24.0))
            }
        }
    }

    private static let fullDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "yyyy-MM-dd, HH:mm"
        return formatter
    }()

    private static let timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var reachedEntriesInSelectedPeriod: [ClippyDailyTargetHistoryEntry] {
        selectedDays.compactMap { reachedHistoryByDay[$0] }
    }

    private var reachedDayCountText: String {
        "\(reachedEntriesInSelectedPeriod.count) av \(selectedDays.count) dagar"
    }

    private var reachedPercentageText: String {
        guard selectedDays.count > 0 else { return "–" }
        let pct = Double(reachedEntriesInSelectedPeriod.count) * 100.0 / Double(selectedDays.count)
        return String(format: "%.0f %%", pct)
    }

    private var fastestReachedText: String {
        guard let fastest = reachedEntriesInSelectedPeriod.min(by: {
            let lhs = secondsSinceStartOfDay(for: Date(timeIntervalSince1970: $0.date))
            let rhs = secondsSinceStartOfDay(for: Date(timeIntervalSince1970: $1.date))
            return lhs < rhs
        }) else {
            return "–"
        }

        return Self.fullDateTimeFormatter.string(from: Date(timeIntervalSince1970: fastest.date))
    }

    private var slowestReachedText: String {
        guard let slowest = reachedEntriesInSelectedPeriod.max(by: {
            let lhs = secondsSinceStartOfDay(for: Date(timeIntervalSince1970: $0.date))
            let rhs = secondsSinceStartOfDay(for: Date(timeIntervalSince1970: $1.date))
            return lhs < rhs
        }) else {
            return "–"
        }

        return Self.fullDateTimeFormatter.string(from: Date(timeIntervalSince1970: slowest.date))
    }

    private var averageReachedText: String {
        let entries = reachedEntriesInSelectedPeriod
        guard !entries.isEmpty else { return "–" }

        let averageSeconds = entries
            .map { secondsSinceStartOfDay(for: Date(timeIntervalSince1970: $0.date)) }
            .reduce(0, +) / entries.count

        let hours = averageSeconds / 3600
        let minutes = (averageSeconds % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    private var longestReachedStreakText: String {
        let streak = longestReachedStreak()
        return "\(streak) dagar"
    }

    private func secondsSinceStartOfDay(for date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let second = comps.second ?? 0
        return (hour * 3600) + (minute * 60) + second
    }

    private func longestReachedStreak() -> Int {
        guard !selectedDays.isEmpty else { return 0 }

        var longest = 0
        var current = 0

        for day in selectedDays {
            if reachedHistoryByDay[day] != nil {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }

        return longest
    }

    private func loadChartData() {
        guard !selectedDays.isEmpty else {
            timeChartView.data = nil
            timeChartView.setNeedsDisplay()
            return
        }

        let yellowColor = UIColor.systemYellow.withAlphaComponent(0.95)
        let redColor = UIColor.systemRed.withAlphaComponent(0.95)

        let reachedSet = ScatterChartDataSet(entries: reachedEntries, label: "Mål nåddes")
        reachedSet.setColor(yellowColor)
        reachedSet.setScatterShape(.circle)
        reachedSet.scatterShapeSize = 8
        reachedSet.drawValuesEnabled = false

        let missedSet = ScatterChartDataSet(entries: missedEntries, label: "Mål nåddes ej")
        missedSet.setColor(redColor)
        missedSet.setScatterShape(.circle)
        missedSet.scatterShapeSize = 8
        missedSet.drawValuesEnabled = false

        timeChartView.data = ScatterChartData(dataSets: [reachedSet, missedSet])
        timeChartView.autoScaleMinMaxEnabled = false
        timeChartView.notifyDataSetChanged()

        timeChartView.drawGridBackgroundEnabled = true
        timeChartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)

        let legend = timeChartView.legend
        legend.enabled = true
        legend.drawInside = false
        legend.orientation = .horizontal
        legend.verticalAlignment = .bottom
        legend.horizontalAlignment = .center
        legend.xEntrySpace = 12
        legend.formToTextSpace = 6
        legend.yOffset = 6

        let reachedLegend = LegendEntry(label: "Mål nåddes")
        reachedLegend.form = .circle
        reachedLegend.formSize = 8
        reachedLegend.formColor = yellowColor

        let missedLegend = LegendEntry(label: "Mål nåddes ej")
        missedLegend.form = .circle
        missedLegend.formSize = 8
        missedLegend.formColor = redColor

        legend.setCustom(entries: [reachedLegend, missedLegend])
        timeChartView.extraBottomOffset = 8

        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "dd/MM"
        let labels = selectedDays.map { df.string(from: $0) }

        let xAxis = timeChartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.granularity = 1
        xAxis.granularityEnabled = true
        xAxis.valueFormatter = IndexAxisValueFormatter(values: labels)
        xAxis.setLabelCount(min(6, labels.count), force: false)

        let yAxis = timeChartView.leftAxis
        yAxis.axisMinimum = 0
        yAxis.axisMaximum = 24
        yAxis.granularity = 1
        yAxis.granularityEnabled = true
        yAxis.setLabelCount(25, force: false)
        yAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
            let v = Int(value.rounded())
            guard [0, 6, 12, 18, 24].contains(v) else { return "" }
            return String(format: "%02d:00", v)
        }

        yAxis.removeAllLimitLines()
        let majorLineColor = UIColor.lightGray.withAlphaComponent(0.65)
        for hour in [0.0, 6.0, 12.0, 18.0, 24.0] {
            let ll = ChartLimitLine(limit: hour)
            ll.lineWidth = 0.8
            ll.lineColor = majorLineColor
            ll.lineDashLengths = []
            ll.label = ""
            yAxis.addLimitLine(ll)
        }

        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.5)
        xAxis.gridColor = gridLineColor
        xAxis.gridLineWidth = 0.5
        xAxis.gridLineDashLengths = [2, 2]

        yAxis.gridColor = gridLineColor
        yAxis.gridLineWidth = 0.5
        yAxis.gridLineDashLengths = [2, 2]

        timeChartView.rightAxis.enabled = false
        timeChartView.setNeedsDisplay()
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "ClippyHistoryStatsCell")
        cell.selectionStyle = .none

        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.backgroundView = nil
        if #available(iOS 14.0, *) {
            var bg = UIBackgroundConfiguration.clear()
            bg.backgroundColor = .systemGray.withAlphaComponent(0.15)
            cell.backgroundConfiguration = bg
        }

        cell.textLabel?.numberOfLines = 1
        cell.detailTextLabel?.numberOfLines = 1
        cell.detailTextLabel?.textAlignment = .right
        cell.detailTextLabel?.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)

        guard let row = Row(rawValue: indexPath.row) else { return cell }

        switch row {
        case .reachedPercentage:
            cell.textLabel?.text = "Andel målgångsdagar"
            cell.detailTextLabel?.text = reachedPercentageText

        case .reachedDays:
            cell.textLabel?.text = "Mål nåddes (12h TITR)"
            cell.detailTextLabel?.text = reachedDayCountText

        case .fastestReached:
            cell.textLabel?.text = "Snabbast i mål"
            cell.detailTextLabel?.text = fastestReachedText

        case .slowestReached:
            cell.textLabel?.text = "Långsammast i mål"
            cell.detailTextLabel?.text = slowestReachedText

        case .averageReached:
            cell.textLabel?.text = "Genomsnittlig målgång"
            cell.detailTextLabel?.text = averageReachedText

        case .longestReachedStreak:
            cell.textLabel?.text = "Längsta streak målgång"
            cell.detailTextLabel?.text = longestReachedStreakText
        }

        return cell
    }
}

