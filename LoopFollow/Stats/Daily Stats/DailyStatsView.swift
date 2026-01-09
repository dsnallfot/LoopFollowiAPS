// LoopFollow
// DailyStatsView.swift

import SwiftUI
import UIKit
import WebKit

@available(iOS 16.0, *)
struct DailyStatsView: View {
    @ObservedObject var viewModel: DailyStatsViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var exportURL: URL?
    @State private var showingTitrSummary: Bool = true
    @State private var selectedDateForReport: Date?
    @State private var showNightscoutAlert: Bool = false
    @State private var showNightscoutReport: Bool = false
    @State private var showDatabaseInfo: Bool = false
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = " yyyy-MM-dd"
        return df
    }()
    
    // Kolumnbredder för raka marginaler
    private let dateWidth: CGFloat = 66
    private let carbsWidth: CGFloat = 36
    private let insulinWidth: CGFloat = 36
    private let meanWidth: CGFloat = 36
    private let lowWidth: CGFloat = 36
    private let titrWidth: CGFloat = 36
    private let tirWidth: CGFloat = 36
    private let stdWidth: CGFloat = 36
    private let profileWidth: CGFloat = 36
    private let emptyWidth: CGFloat = 10
    
    private let columnSpacing: CGFloat = 1
    
    var body: some View {
        ZStack {
                ThemeBackground()
        NavigationStack {
            coreContent
                .navigationTitle("Daglig statistik")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if let url = viewModel.writeCSVToDisk() {
                                exportURL = url
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showDatabaseInfo = true
                        } label: {
                            Image(systemName: "internaldrive")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Klar") {
                            dismiss()
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
        let filteredRowsForHighlight = viewModel.rowsWithSufficientGlucose
            .filter { $0.tightRangePercent != nil }
        
        let highlightInfo: HighlightInfo = {
            // Endast highlight om vi har fler än 1 dag (dvs 7, 14, 30, 90 – inte "Idag"/1 dag)
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
                    summarySection
                        .padding(.horizontal, 10)
                        .padding(.top, 8)

                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            headerRow
                                .padding(.vertical, 6)
                            Divider()

                            ScrollView(.vertical) {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(filteredRowsForHighlight.enumerated()), id: \.element.id) { index, row in
                                        HStack(spacing: columnSpacing) {
                                            Text(dateFormatter.string(from: row.date))
                                                .frame(width: dateWidth, alignment: .leading)
                                                .font(.system(size: 10).monospacedDigit())

                                            numberCell(row.totalCarbs, width: carbsWidth, decimals: 0)
                                            numberCell(row.insulinTDD, width: insulinWidth)
                                            meanCell(row.meanGlucoseMmol)
                                            lowCell(row.lowPercent)
                                            titrCell(row.tightRangePercent)
                                            tirCell(row.timeInRangePercent)
                                            stdDevCell(stdDev: row.stdDevMmol, mean: row.meanGlucoseMmol)
                                            numberCell(row.profileBasal, width: profileWidth)
                                            emptyCell(row.emptyInfo, width: emptyWidth)
                                        }
                                        .padding(.vertical, 8)
                                        .background({
                                            // Bas: varannan rad ljusgrå
                                            let baseColor: Color = index % 2 == 0
                                            ? Color(.systemBackground.withAlphaComponent(0.3))
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
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
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
            modalWithTimestamp: true,
            modalTitleString: "Dagens utfall"
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
        ZStack {
            ThemeBackground()
            VStack(spacing: 16) {
                Text("Databasens innehåll")
                    .font(.title2)
                    .padding(.top)
                
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
                            Text("Blodsockervärden:")
                            Spacer()
                            Text("\(mainVC.statsBGData.count)")
                        }
                        HStack {
                            Text("Fingerstick:")
                            Spacer()
                            Text("\(mainVC.statsBGCheckData.count)")
                        }
                        HStack {
                            Text("Manuell bolus:")
                            Spacer()
                            Text("\(mainVC.statsBolusData.count)")
                        }
                        HStack {
                            Text("SMB:")
                            Spacer()
                            Text("\(mainVC.statsSMBData.count)")
                        }
                        HStack {
                            Text("Kolhydrater:")
                            Spacer()
                            Text("\(mainVC.statsCarbData.count)")
                        }
                        HStack {
                            Text("Temp basal:")
                            Spacer()
                            Text("\(mainVC.statsBasalData.count)")
                        }
                    }
                    .font(.body)
                } else {
                    Text("Ingen data tillgänglig.")
                }
                
                Spacer()
                
                Button("Stäng") {
                    showDatabaseInfo = false
                }
                .padding(.bottom)
            }
            .padding()
        }
    }

    // MARK: - Subviews

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
                                Text("Du nådde ditt mål på ")
                                Text(showingTitrSummary ? titrThresholdPercentString : tirThresholdPercentString)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.green.opacity(0.8))
                                Text(showingTitrSummary ? " tid i tight målområde" : " tid i målområde ")
                            }

                            // Rad 2: intervallet i grått
                            HStack(spacing: 0) {
                            Text(showingTitrSummary ? "(3.9–7.8 mmol/L) " : "(3.9–10.0 mmol/L) ")
                                .foregroundColor(.secondary)
                                Text("under ")
                                Text(showingTitrSummary ? daysMeetingTitrString : daysMeetingTirString)
                                    .fontWeight(.bold)
                                Text(" av de senaste ")
                                Text(daysInScopeString)
                                    .fontWeight(.bold)
                                Text(" dagarna.")
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)

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
        let filteredRows = viewModel.rowsWithSufficientGlucose
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
        let filteredRows = viewModel.rowsWithSufficientGlucose
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
            Text("Datum")
                .frame(width: dateWidth, alignment: .leading)
                .font(.system(size: 10, weight: .semibold))

            Text("Kolh")
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

            Text("Std.av")
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
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(foregroundColor ?? .primary)
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: width, alignment: .trailing)
    }
    
    private func emptyCell(
        _ value: String?,
        width: CGFloat,
        decimals: Int = 0,
        foregroundColor: Color? = nil
    ) -> some View {
        Group {
            if value != nil {
                Text("")
            } else {
                Text("")
            }
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

