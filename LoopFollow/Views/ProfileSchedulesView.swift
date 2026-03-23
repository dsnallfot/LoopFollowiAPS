//
//  ProfileSchedulesView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-26.

//

import SwiftUI
import Charts
import PhotosUI
import UIKit
import HealthKit
import UniformTypeIdentifiers

@available(iOS 26.0, *)
private struct LogSearchItem: Identifiable {
    let term: String
    var id: String { term }
}

@available(iOS 26.0, *)
struct ProfileSchedulesView: View {
    var onDone: (() -> Void)? = nil
    @ObservedObject var viewModel = ProfileSchedulesViewModel()
    
    @State private var selectedSection: SectionType = .targets // Default section
    @State private var showProfileUpdatedAlert: Bool = false
    @State private var selectedLogSearchItem: LogSearchItem?
    @State private var selectedMode: Mode = .user
    @State private var showAddUserData: Bool = false
    @State private var showStatsView: Bool = false
    @State private var showTrainingStats: Bool = false
    @State private var isExportingUserCSV: Bool = false
    @State private var isImportingUserCSV: Bool = false
    @State private var userCSVDocument: UserProfileCSVDocument = UserProfileCSVDocument(text: "")
    @State private var userCSVImportError: String?
    @State private var showAddSickDay: Bool = false
    @State private var showSickDayCalendar: Bool = false
    @State private var sickDayToDelete: SickDayHistoryEntry?
    
    private static let sickDayDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private static let sickDayMonthSectionFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "MMMM yyyy"
        return df
    }()

    enum Mode: String, CaseIterable {
        case user = "Hälsodata"
        case sick = "Sjukdagar"
        case training = "Träning"
        case profile = "Profil"
    }

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
    
    private func openSettingsLog(for term: String) {
        selectedLogSearchItem = LogSearchItem(term: term)
    }
    
    private func presentSickDayAnalysis(for entry: SickDayHistoryEntry) {
        let entryDate = Date(timeIntervalSince1970: entry.date)
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: entryDate)
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate)

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

        guard let mainVC, let endDate else {
            return
        }

        let events = mainVC.buildEventsForMealAnalysis()

        let analysisVC = MealAnalysisView(
            events: events,
            initialStart: startDate,
            initialEnd: endDate,
            modalWithTimestamp: true,
            modalTitleString: entry.notes,
            preSelectedSegment: 6
        )

        let nav = UINavigationController(rootViewController: analysisVC)
        nav.modalPresentationStyle = .formSheet
        window.rootViewController?.present(nav, animated: true)
    }

    private func presentTrainingAnalysis(for session: TrainingSessionEntry) {
        let entryDate = session.startDate
        let calendar = Calendar.current
        let startDate = entryDate//calendar.startOfDay(for: entryDate)
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate)

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

        guard let mainVC, let endDate else {
            return
        }

        let events = mainVC.buildEventsForMealAnalysis()

        let analysisVC = MealAnalysisView(
            events: events,
            initialStart: startDate,
            initialEnd: endDate,
            modalWithTimestamp: true,
            modalTitleString: session.trainingType,
            preSelectedSegment: 2
        )

        let nav = UINavigationController(rootViewController: analysisVC)
        nav.modalPresentationStyle = .formSheet
        window.rootViewController?.present(nav, animated: true)
    }

    @ViewBuilder
    private var modePickerView: some View {
        Picker("Mode", selection: $selectedMode) {
            ForEach(Mode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.top)
        .padding(.bottom, 6)
        .padding(.horizontal)
    }
    
    private var groupedSickDayEntries: [(title: String, countText: String, entries: [SickDayHistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: viewModel.sickDayEntries) { entry in
            let date = Date(timeIntervalSince1970: entry.date)
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
        }

        return grouped
            .sorted { $0.key > $1.key }
            .map { monthDate, entries in
                let title = Self.sickDayMonthSectionFormatter.string(from: monthDate).capitalized
                let sortedEntries = entries.sorted { $0.date > $1.date }
                let count = sortedEntries.count
                let countText = count == 1 ? "1 dag" : "\(count) dagar"
                return (title: title, countText: countText, entries: sortedEntries)
            }
    }

    private var hasSickDayEntries: Bool {
        !viewModel.sickDayEntries.isEmpty
    }

    @ViewBuilder
    private var sickDayModeContent: some View {
        if hasSickDayEntries {
            List {
                ForEach(groupedSickDayEntries, id: \.title) { section in
                    Section(
                        header:
                            HStack {
                                Text(section.title)
                                Spacer()
                                Text(section.countText)
                                    .foregroundColor(.secondary)
                            }
                    ) {
                        ForEach(section.entries, id: \.date) { entry in
                            HStack {
                                Text(entry.notes)
                                    .font(.subheadline.monospacedDigit())
                                Spacer()
                                Text(Self.sickDayDateFormatter.string(from: Date(timeIntervalSince1970: entry.date)))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                presentSickDayAnalysis(for: entry)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    sickDayToDelete = entry
                                } label: {
                                    Label("Radera", systemImage: "trash")
                                }
                            }
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        } else {
            ContentUnavailableView(
                "Inga sjukdagar registrerade",
                systemImage: "medical.thermometer",
                description: Text("Automatiskt fångade eller manuellt tillagda sjukdagar kommer att visas här.")
            )
        }
    }
    
    @ViewBuilder
    private var trainingModeContent: some View {
        TrainingSessionsView(
            sessions: viewModel.trainingSessions,
            onTapSession: { session in
                presentTrainingAnalysis(for: session)
            }
        )
    }

    @ViewBuilder
    private var profileModeContent: some View {
        Picker("Select Section", selection: $selectedSection) {
            ForEach(SectionType.allCases, id: \.self) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)

        LineChartWrapper(chartData: multiChartData, title: selectedSection.displayName)
            .frame(height: 220)
            .padding(.horizontal)

        List {
            if selectedSection == .targets {
                Section(header: sectionHeader(title: "🟪 Mål (mmol/L)", lastChanged: viewModel.lastChangedTargetProfile)) {
                    ForEach(viewModel.targetEntries) { entry in
                        scheduleRow(entry)
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
                            .contentShape(Rectangle())
                            .onTapGesture { openSettingsLog(for: "Mål-profil") }
                    }
                }
                .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
            }

            if selectedSection == .basal {
                Section(header: sectionHeader(title: "🟪 Basal (E/h)", lastChanged: viewModel.lastChangedBasalProfile)) {
                    ForEach(viewModel.basalEntries) { entry in
                        scheduleRow(entry, isBold: entry.time == "Total daglig basal")
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
                            .contentShape(Rectangle())
                    }
                }
                .onTapGesture { openSettingsLog(for: "Basalprofil") }
                .listRowBackground(Color(UIColor.systemGray).opacity(0.15))

                Section(header: Text("🟦 Basal IOB (E aktiv/h)")) {
                    ForEach(viewModel.basalIOBEntries) { entry in
                        scheduleRow(entry, isBold: entry.time == "Medel basal IOB/h")
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
                            .contentShape(Rectangle())
                    }
                }
                .onTapGesture { openSettingsLog(for: "Basalprofil") }
                .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
            }

            if selectedSection == .cr {
                Section(header: sectionHeader(title: "🟪 Insulinkvoter (g/E)", lastChanged: viewModel.lastChangedCRProfile)) {
                    ForEach(viewModel.carbRatioEntries) { entry in
                        scheduleRow(entry)
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
                            .contentShape(Rectangle())
                    }
                }
                .onTapGesture { openSettingsLog(for: "CR-profil") }
                .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
            }

            if selectedSection == .isf {
                Section(header: sectionHeader(title: "🟪 Känslighet (mmol/L/E)", lastChanged: viewModel.lastChangedISFProfile)) {
                    ForEach(viewModel.isfEntries) { entry in
                        scheduleRow(entry)
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
                            .contentShape(Rectangle())
                            .onTapGesture { openSettingsLog(for: "ISF-profil") }
                    }
                }
                .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
            }

            if selectedSection == .csf {
                Section(header: Text("🟪 Kh-känslighet (mmol/L/g)")) {
                    ForEach(viewModel.csfEntries) { entry in
                        scheduleRow(entry)
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
                    }
                }
                .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
            }

            if selectedSection == .cHr {
                Section(header: Text("🟪 Minsta absorption Kh (g/h)")) {
                    ForEach(viewModel.minCarbsEntries) { entry in
                        scheduleRow(entry, isBold: entry.time == "Medelvärde")
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
                    }
                }
                .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
            }

            if selectedSection == .smb {
                Section(header: Text("🟦 Maxgräns SMB / UAMSMB (E/SMB)")) {
                    ForEach(viewModel.smbEntries) { entry in
                        scheduleRow(entry)
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
                    }
                }
                .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @available(iOS 26.0, *)
    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                modePickerView

                if selectedMode == .profile {
                    profileModeContent
                } else if selectedMode == .sick {
                    sickDayModeContent
                } else if selectedMode == .training {
                    trainingModeContent
                } else {
                    UserDataViewController()
                }
            }
        }
        .navigationTitle(selectedMode.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedMode) { _, newMode in
            if newMode == .sick {
                viewModel.reloadSickDays()
            } else if newMode == .training {
                viewModel.reloadTrainingSessions()
            }
        }
        .sheet(item: $selectedLogSearchItem) { item in
            ZStack {
                // Lägg till bakgrunden här för att fylla hela modalen
                ThemeBackground()
                    .ignoresSafeArea()
                
                // Din wrapper ovanpå bakgrunden
                SettingsLogModal(initialSearchText: item.term)
            }
        }
        .sheet(isPresented: $showAddUserData) {
            NavigationStack {
                AddUserDataView()
            }
        }
        .sheet(isPresented: $showStatsView) {
            NavigationStack {
                UserDataStatsView()
            }
        }
        .sheet(isPresented: $showAddSickDay) {
            NavigationStack {
                AddSickDayView()
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSickDayCalendar) {
            NavigationStack {
                SickDayCalendarView(entries: viewModel.sickDayEntries)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedMode == .profile {
                    Button {
                        showProfileUpdatedAlert = true
                    } label: {
                        Image(systemName: "info")
                    }
                    .accessibilityLabel("Profil laddades ner:")
                } else if selectedMode == .user {
                    HStack {
                        Button {
                            showAddUserData = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .padding(.leading, 2)
                        .accessibilityLabel("Lägg till användardata")

                        Button {
                            let csv = Storage.shared.exportUserProfilesCSV()
                            userCSVDocument = UserProfileCSVDocument(text: csv)
                            isExportingUserCSV = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Exportera användardata (CSV)")

                        Button {
                            isImportingUserCSV = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel("Importera användardata (CSV)")
                    }
                } else if selectedMode == .sick {
                    HStack(spacing: 14) {
                        Button {
                            showAddSickDay = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Lägg till sjukdag")
                        
                        Button {
                            showSickDayCalendar = true
                        } label: {
                            Image(systemName: "calendar")
                        }
                        .accessibilityLabel("Visa sjukdagshistorik som kalender")
                    }
                } else if selectedMode == .training {
                    Button {
                        showTrainingStats = true
                    } label: {
                        Image(systemName: "chart.bar.xaxis.ascending")
                    }
                    .accessibilityLabel("Visa träningsstatistik")
                }
            }
        }
        .sheet(isPresented: $showTrainingStats) {
            NavigationStack {
                TrainingStatsView(sessions: viewModel.trainingSessions)
            }
        }
        .alert(
            "Profil uppdaterades \n\(ProfileManager.shared.profileCreatedAtFormatted ?? "Okänt")",
            isPresented: $showProfileUpdatedAlert
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("""
            
            Senaste ändringsdatum
            • Målprofil: \(fmt(viewModel.lastChangedTargetProfile))
            • Basalprofil: \(fmt(viewModel.lastChangedBasalProfile))
            • CR-profil: \(fmt(viewModel.lastChangedCRProfile))
            • ISF-profil: \(fmt(viewModel.lastChangedISFProfile))
            """)
        }
        .alert("Radera sjukdag", isPresented: Binding(
            get: { sickDayToDelete != nil },
            set: { newValue in
                if !newValue {
                    sickDayToDelete = nil
                }
            }
        )) {
            Button("Radera", role: .destructive) {
                if let entry = sickDayToDelete {
                    viewModel.deleteSickDay(entry)
                }
                sickDayToDelete = nil
            }
            Button("Avbryt", role: .cancel) {
                sickDayToDelete = nil
            }
        } message: {
            if let entry = sickDayToDelete {
                Text("Vill du verkligen radera sjukdagen \(Self.sickDayDateFormatter.string(from: Date(timeIntervalSince1970: entry.date))) med noteringen \"\(entry.notes)\"?")
            } else {
                Text("Vill du verkligen radera denna sjukdag?")
            }
        }
        .fileExporter(
            isPresented: $isExportingUserCSV,
            document: userCSVDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "UserProfiles"
        ) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                userCSVImportError = "Export misslyckades: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $isImportingUserCSV,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    var dataURL = url
                    var needsStop = false
                    if dataURL.startAccessingSecurityScopedResource() {
                        needsStop = true
                    }
                    defer {
                        if needsStop {
                            dataURL.stopAccessingSecurityScopedResource()
                        }
                    }

                    let data = try Data(contentsOf: dataURL)
                    if let csvString = String(data: data, encoding: .utf8) {
                        Storage.shared.importUserProfilesCSV(from: csvString)
                    } else {
                        userCSVImportError = "Kunde inte läsa CSV-filen (ogiltig textkodning)."
                    }
                } catch {
                    userCSVImportError = "Kunde inte läsa CSV-filen: \(error.localizedDescription)"
                }
            case .failure(let error):
                userCSVImportError = "Import misslyckades: \(error.localizedDescription)"
            }
        }
        .alert("Fel vid CSV-import/export", isPresented: Binding(
            get: { userCSVImportError != nil },
            set: { newValue in
                if !newValue {
                    userCSVImportError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) { userCSVImportError = nil }
        } message: {
            Text(userCSVImportError ?? "Okänt fel")
        }
    }
    
    private var shortDateFormatter: DateFormatter {
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }

    private func fmt(_ date: Date?) -> String {
        guard let date else { return "N/A" }
        return shortDateFormatter.string(from: date)
    }

    @ViewBuilder
    private func scheduleRow(_ entry: ScheduleEntry, isBold: Bool = false) -> some View {
        HStack {
            Text(entry.time)
                .font(isBold ? .headline.bold().monospacedDigit() : .subheadline.monospacedDigit())
            Spacer()
            Text(entry.value)
                .font(isBold ? .headline.bold().monospacedDigit() : .subheadline.monospacedDigit())
        }
    }
    
    @ViewBuilder
    private func sectionHeader(title: String, lastChanged: Date?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let d = lastChanged {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                    Text(d.formatted(.dateTime.year().month().day()))
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }
}

private struct TrainingSessionRow: View {
    let session: TrainingSessionEntry

    private static let startFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "yyyy-MM-dd, HH:mm"
        return df
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(leftText)
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.primary)

            Spacer(minLength: 8)

            Text(Self.startFormatter.string(from: session.startDate))
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var leftText: String {
        let durationText: String
        if session.isOngoing {
            durationText = "Pågår"
        } else if let minutes = session.durationMinutes {
            durationText = "\(minutes) min"
        } else {
            durationText = "Pågår"
        }

        return "\(session.trainingType) (\(durationText))"
    }
}

@available(iOS 17.0, *)
private struct TrainingSessionsView: View {
    let sessions: [TrainingSessionEntry]
    let onTapSession: (TrainingSessionEntry) -> Void

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "Inga träningssessioner registrerade",
                    systemImage: "figure.run",
                    description: Text("Registrerade träningssessioner från Nightscout-noteringar kommer att visas här.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            TrainingSessionRow(session: session)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onTapSession(session)
                                }

                            if index < sessions.count - 1 {
                                Divider()
                                    .padding(.leading, 18)
                                    .padding(.trailing, 18)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Color(UIColor.systemGray).opacity(0.15))
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .background(Color.clear)
            }
        }
        .navigationTitle("Träningssessioner")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.clear)
    }
}

// MARK: - User profile image persistence

private final class UserProfileImageManager {
    static let shared = UserProfileImageManager()
    private let key = "UserProfileImageData"

    private init() {}

    func save(image: UIImage) {
        if let data = image.jpegData(compressionQuality: 0.9) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() -> UIImage? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return UIImage(data: data)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - UserDataViewController

@available(iOS 16.0, *)
private struct UserDataViewController: View {
    @State private var profileImage: UIImage?
    @State private var selectedItem: PhotosPickerItem?
    @State private var profile: UserProfileEntry?
    @State private var profiles: [UserProfileEntry] = []
    @State private var editingEntry: UserProfileEntry?
    @State private var profileToDelete: UserProfileEntry?
    @State private var showDeleteAlert: Bool = false
    @State private var viewingEntry: UserProfileEntry?
    @State private var showDeleteImageAlert: Bool = false

    private static let shortDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    // Helper to format date and append (Xår Yd) age if in past
    private static func formattedDateWithAge(_ date: Date?) -> String {
        guard let date else { return "ÅÅ-MM-DD" }

        let base = shortDateFormatter.string(from: date)
        let now = Date()
        let calendar = Calendar.current

        // If the date is in the future, just return the formatted date without age.
        guard date <= now else {
            return base
        }

        // First compute full years between date and now.
        let yearComponents = calendar.dateComponents([.year], from: date, to: now)
        let years = yearComponents.year ?? 0

        // Then compute remaining days after subtracting those full years.
        let dateAfterYears = calendar.date(byAdding: .year, value: years, to: date) ?? date
        let dayComponents = calendar.dateComponents([.day], from: dateAfterYears, to: now)
        let days = dayComponents.day ?? 0

        return String(format: "%@ (%då %dd)", base, years, days)
    }

    var body: some View {
        ZStack {
            //ThemeBackground()
                //.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header: profilbild + senaste profilinfo
                let imageSide = UIScreen.main.bounds.width / 4

                HStack(alignment: .top, spacing: 8) {
                    // Frame 1: Profilbild
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        ZStack {
                            Circle()
                                .fill(Color(.systemBackground).opacity(0.5))

                            if let img = profileImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                            }
                        }
                        .frame(width: imageSide, height: imageSide)
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .onChange(of: selectedItem) { newItem in
                        guard let item = newItem else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                await MainActor.run {
                                    self.profileImage = uiImage
                                    UserProfileImageManager.shared.save(image: uiImage)
                                }
                            }
                        }
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                            if profileImage != nil {
                                showDeleteImageAlert = true
                            }
                        }
                    )
                    Spacer()

                    // Frames 2 & 3: Rubriker + värden
                    HStack(alignment: .top, spacing: 12) {
                        // Frame 2: Rubriker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Namn:")
                            Text("Född:")
                            Text("T1D debut:")
                            Text("Längd:")
                            Text("Vikt (BMI):")
                            Text("Uppdaterades:")
                        }
                        .font(.caption2.monospacedDigit())

                        // Frame 3: Värden (senaste profil eller placeholders)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile?.name ?? "För- Efternamn")
                            Text(Self.formattedDateWithAge(profile?.birthDate))
                            Text(Self.formattedDateWithAge(profile?.t1dSince))
                            Text(profile?.heightCm.map { String(format: "%.1f cm", $0) } ?? "-- cm")
                            Text({
                                if let weight = profile?.weightKg,
                                   let heightCm = profile?.heightCm,
                                   heightCm > 0 {
                                    let heightM = heightCm / 100.0
                                    let bmi = weight / (heightM * heightM)
                                    return String(format: "%.1f kg (%.1f)", weight, bmi)
                                } else if let weight = profile?.weightKg {
                                    return String(format: "%.1f kg", weight)
                                } else {
                                    return "-- kg"
                                }
                            }())
                            Text(profile.map { Self.shortDateFormatter.string(from: $0.updatedAt) } ?? "ÅÅ-MM-DD")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)

                        //Spacer()
                    }
                    .frame(height: imageSide, alignment: .top)
                }
                .padding(.vertical, 16)
                .padding(.leading, 24)
                .padding(.trailing, 16)
                Divider()

                // Sektion: tabell med historik
                if profiles.isEmpty {
                    Text("Ingen data finns registrerad ännu. Klicka på + uppe till vänster för att göra en första registrering.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List {
                        ForEach(profiles) { entry in
                            UserProfileRow(entry: entry)
                                .listRowBackground(Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewingEntry = entry
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        profileToDelete = entry
                                        showDeleteAlert = true
                                    } label: {
                                        Label("Radera", systemImage: "trash")
                                    }

                                    Button {
                                        editingEntry = entry
                                    } label: {
                                        Label("Redigera", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .listStyle(.plain)
                }
                if profiles.isEmpty {
                    Spacer()
                }
            }
            .padding(.top, 12)
        }
        .onAppear {
            if profileImage == nil {
                profileImage = UserProfileImageManager.shared.load()
            }
            reloadProfiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: .userProfileUpdated)) { _ in
            reloadProfiles()
        }
        .sheet(item: $editingEntry) { entry in
            NavigationStack {
                AddUserDataView(existingEntry: entry)
            }
        }
        .sheet(item: $viewingEntry) { entry in
            NavigationStack {
                AddUserDataView(existingEntry: entry, isReadOnly: true)
            }
        }
        .alert("Radera data", isPresented: $showDeleteAlert) {
            Button("Radera", role: .destructive) {
                if let toDelete = profileToDelete {
                    var stored = Storage.shared.userProfiles
                    stored.removeAll { $0.updatedAt == toDelete.updatedAt && $0.name == toDelete.name }
                    Storage.shared.userProfiles = stored
                    reloadProfiles()
                    profileToDelete = nil
                }
            }
            Button("Avbryt", role: .cancel) {
                profileToDelete = nil
            }
        } message: {
            if let toDelete = profileToDelete {
                Text("Vill du verkligen radera data registrerat \(Self.shortDateFormatter.string(from: toDelete.updatedAt))?")
            } else {
                Text("Vill du verkligen radera denna post?")
            }
        }
        .alert("Radera bild", isPresented: $showDeleteImageAlert) {
            Button("Radera", role: .destructive) {
                profileImage = nil
                UserProfileImageManager.shared.clear()
            }
            Button("Avbryt", role: .cancel) { }
        } message: {
            Text("Vill du radera nuvarande profilbild?")
        }
    }
    private func reloadProfiles() {
        let stored = Storage.shared.userProfiles.sorted { $0.updatedAt > $1.updatedAt }
        profiles = stored
        profile = stored.first
    }
}

@available(iOS 16.0, *)
private struct UserProfileRow: View {
    let entry: UserProfileEntry

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Self.dateFormatter.string(from: entry.updatedAt))
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(.semibold)

                Spacer()

                if let hb = entry.hbA1c {
                    ZStack {
                        Circle()
                            .fill(hbColor(for: hb))
                            .frame(width: 30, height: 30)

                        Text(String(format: "%.0f", hb))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .offset(x: 0, y: 13)
                } else {
                    ZStack {
                        Circle()
                            .fill(Color(.systemGray4))
                            .frame(width: 30, height: 30)

                        Text("--")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .offset(x: 0, y: 12)
                }
            }

            let tddString = entry.tdd.map { String(format: "%.1f", $0) } ?? "--"
            let weightString = entry.weightKg.map { String(format: "%.1f", $0) } ?? "--"
            let heightString = entry.heightCm.map { String(format: "%.1f", $0) } ?? "--"
            let insulinPerKgString = entry.insulinPerKg.map { String(format: "%.2f", $0) } ?? "--"

            Text("TDD: \(tddString) E • Vikt: \(weightString) kg • \(insulinPerKgString) E/kg/d • Längd: \(heightString) cm")
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func hbColor(for hbA1c: Double) -> Color {
        if hbA1c <= 48 {
            return Color(UIColor.systemGreen)
        } else if hbA1c <= 52 {
            return Color(UIColor.systemOrange)
        } else {
            return Color(UIColor.systemRed)
        }
    }
}

@available(iOS 16.0, *)
private struct UserDataStatsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMetric: Metric = .hba1c

    enum Metric: String, CaseIterable, Identifiable {
        case hba1c = "HbA1c"
        case weight = "Vikt"
        case height = "Längd"
        case bmi = "BMI"
        case tdd = "TDD"
        var id: String { rawValue }
    }

    enum ComparisonMetric: String, CaseIterable, Identifiable {
        case tdd = "TDD"
        case basal = "Basal"
        case isf = "ISF"
        case morningCR = "Morgon"
        case dayCR = "Dag"

        var id: String { rawValue }
    }

    @State private var selectedComparison: ComparisonMetric = .tdd

    private var sortedProfiles: [UserProfileEntry] {
        Storage.shared.userProfiles
            .sorted { $0.updatedAt < $1.updatedAt }
    }

    private struct ChartConfig {
        let entries: [ChartDataEntry]
        let dates: [Date]
        let style: LineChartStyle
    }

    private struct WalshChartConfig {
        let walshEntries: [ChartDataEntry]
        let actualEntries: [ChartDataEntry]
        let dates: [Date]
        let walshLabel: String
        let actualLabel: String
    }

    /// Bygger entries + datum + style för aktuell metric
    private var chartConfig: ChartConfig? {
        let valueExtractor: (UserProfileEntry) -> Double?
        let baseColor: NSUIColor
        let circleColorProvider: ((Double) -> NSUIColor)?

        switch selectedMetric {
        case .hba1c:
            valueExtractor = { $0.hbA1c }
            baseColor = .systemGray
            circleColorProvider = { value in
                if value <= 48 {
                    return .systemGreen
                } else if value <= 52 {
                    return .systemOrange
                } else {
                    return .systemRed
                }
            }

        case .weight:
            valueExtractor = { $0.weightKg }
            baseColor = .systemBrown
            circleColorProvider = nil

        case .height:
            valueExtractor = { $0.heightCm }
            baseColor = .cyan
            circleColorProvider = nil

        case .bmi:
            valueExtractor = { entry in
                guard let weight = entry.weightKg,
                      let heightCm = entry.heightCm,
                      heightCm > 0 else { return nil }
                let heightM = heightCm / 100.0
                return weight / (heightM * heightM)
            }
            baseColor = .systemYellow
            circleColorProvider = nil

        case .tdd:
            valueExtractor = { $0.tdd }
            baseColor = .systemBlue
            circleColorProvider = nil
        }

        var entries: [ChartDataEntry] = []
        var dates: [Date] = []

        // 🔹 Första datumet blir x = 0
        guard let firstDate = sortedProfiles.first?.updatedAt else {
            return nil
        }
        let secondsPerDay: Double = 60 * 60 * 24

        for entry in sortedProfiles {
            guard let value = valueExtractor(entry) else { continue }
            let daysSinceStart = entry.updatedAt.timeIntervalSince(firstDate) / secondsPerDay
            entries.append(ChartDataEntry(x: daysSinceStart, y: value))
            dates.append(entry.updatedAt)
        }

        guard !entries.isEmpty else { return nil }

        let style = LineChartStyle(
            lineColor: baseColor,
            showCircles: true,
            circleRadius: 6,
            circleColor: circleColorProvider
        )

        return ChartConfig(entries: entries, dates: dates, style: style)
    }

    /// Bygger entries för jämförelse mellan Walsh-baseline och inställt värde
    private var walshChartConfig: WalshChartConfig? {
        let walshExtractor: (UserProfileEntry) -> Double?
        let actualExtractor: (UserProfileEntry) -> Double?
        let walshLabel: String
        let actualLabel: String

        switch selectedComparison {
        case .tdd:
            walshExtractor = { $0.walshTDD }
            actualExtractor = { $0.tdd }
            walshLabel = "Walsh TDD"
            actualLabel = "Aktuell TDD (14d)"
        case .basal:
            walshExtractor = { $0.walshBasal }
            actualExtractor = { $0.actualBasal }
            walshLabel = "Walsh Basal"
            actualLabel = "Aktuell Basal"
        case .isf:
            walshExtractor = { $0.walsh100ISF }
            actualExtractor = { $0.actualAverageISF }
            walshLabel = "Walsh 100-regeln ISF"
            actualLabel = "Aktuell ISF (medel)"
        case .morningCR:
            walshExtractor = { $0.walsh300CR }
            actualExtractor = { $0.actualMorningCR }
            walshLabel = "Walsh 300-regeln CR"
            actualLabel = "Aktuell CR morgon"
        case .dayCR:
            walshExtractor = { $0.walsh500CR }
            actualExtractor = { $0.actualDayCR }
            walshLabel = "Walsh 500-regeln CR"
            actualLabel = "Aktuell CR dag"
        }

        guard let firstDate = sortedProfiles.first?.updatedAt else {
            return nil
        }
        let secondsPerDay: Double = 60 * 60 * 24

        var walshEntries: [ChartDataEntry] = []
        var actualEntries: [ChartDataEntry] = []
        let dates: [Date] = sortedProfiles.map { $0.updatedAt }

        for entry in sortedProfiles {
            let daysSinceStart = entry.updatedAt.timeIntervalSince(firstDate) / secondsPerDay

            if let walshValue = walshExtractor(entry) {
                walshEntries.append(ChartDataEntry(x: daysSinceStart, y: walshValue))
            }
            if let actualValue = actualExtractor(entry) {
                actualEntries.append(ChartDataEntry(x: daysSinceStart, y: actualValue))
            }
        }

        guard !walshEntries.isEmpty || !actualEntries.isEmpty else { return nil }

        return WalshChartConfig(
            walshEntries: walshEntries,
            actualEntries: actualEntries,
            dates: dates,
            walshLabel: walshLabel,
            actualLabel: actualLabel
        )
    }

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(spacing: 12) {
                // Övre graf – enskild metric över tid
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(Metric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if let chartConfig = chartConfig {
                    StatsLineChartWrapper(
                        entries: chartConfig.entries,
                        dates: chartConfig.dates,
                        title: selectedMetric.rawValue,
                        style: chartConfig.style
                    )
                    .frame(height: 250)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                } else {
                    Text("Ingen data att visa ännu.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding()
                        .padding(.bottom, 10)
                }

                // Nedre graf – Walsh baseline vs inställt värde
                if let walshConfig = walshChartConfig {
                    Picker("WalshMetric", selection: $selectedComparison) {
                        ForEach(ComparisonMetric.allCases) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    Text("Jämförelse aktuella inställningar vs Walsh baseline")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.top, 4)
                        .padding(.bottom, -8)

                    WalshComparisonLineChartWrapper(
                        walshEntries: walshConfig.walshEntries,
                        actualEntries: walshConfig.actualEntries,
                        dates: walshConfig.dates,
                        title: selectedComparison.rawValue,
                        walshLabel: walshConfig.walshLabel,
                        actualLabel: walshConfig.actualLabel
                    )
                    .frame(height: 270)
                    .padding(.horizontal)
                } else {
                    Text("Ingen Walsh-data att jämföra ännu.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                Spacer()
            }
        }
        .navigationTitle("Utveckling över tid")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Klar") { dismiss() }
            }
        }
    }
}

@available(iOS 16.0, *)
private struct AddSickDayView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date = Date()
    @State private var selectedType: SickDayType = .forkyld

    enum SickDayType: String, CaseIterable, Identifiable {
        case forkyld = "🤧 Förkyld"
        case magsjuka = "🤢 Magsjuka"
        case sjuk = "🤒 Sjuk"

        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                DatePicker(
                    "Datum",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)
                .environment(\.locale, Locale(identifier: "sv_SE"))
                .labelsHidden()

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(SickDayType.allCases) { type in
                        Button {
                            selectedType = type
                        } label: {
                            HStack {
                                Text(type.rawValue)
                                    .font(.body.monospacedDigit())
                                Spacer()
                                if selectedType == type {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(UIColor.systemGray).opacity(0.15))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Lägg till sjukdag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Spara") {
                    Storage.shared.addManualSickDay(for: selectedDate, notes: selectedType.rawValue)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - AddUserDataView placeholder

@available(iOS 16.0, *)
private struct AddUserDataView: View {
    @Environment(\.dismiss) private var dismiss
    var existingEntry: UserProfileEntry? = nil
    var isReadOnly: Bool = false

    @State private var name: String = ""
    @State private var birthDate: Date = Date()
    @State private var t1dSinceDate: Date = Date()
    @State private var updatedDate: Date = Date()
    @State private var heightText: String = ""
    @State private var weightText: String = ""
    @State private var tddText: String = ""
    @State private var actualMorningCRText: String = ""
    @State private var actualDayCRText: String = ""
    @State private var actualBasalText: String = ""
    @State private var actualAverageISFText: String = ""
    @State private var hbA1cText: String = ""

    private var heightCm: Double? {
        Double(heightText.replacingOccurrences(of: ",", with: "."))
    }

    private var weightKg: Double? {
        Double(weightText.replacingOccurrences(of: ",", with: "."))
    }

    private var tdd: Double? {
        Double(tddText.replacingOccurrences(of: ",", with: "."))
    }
    
    private var hbA1c: Double? {
        Double(hbA1cText.replacingOccurrences(of: ",", with: "."))
    }
    
    private var actualMorningCR: Double? {
        Double(actualMorningCRText.replacingOccurrences(of: ",", with: "."))
    }
    
    private var actualDayCR: Double? {
        Double(actualDayCRText.replacingOccurrences(of: ",", with: "."))
    }
    
    private var actualAverageISF: Double? {
        Double(actualAverageISFText.replacingOccurrences(of: ",", with: "."))
    }
    
    private var actualBasal: Double? {
        Double(actualBasalText.replacingOccurrences(of: ",", with: "."))
    }

    private var insulinPerKg: Double? {
        guard let tdd, let weightKg, weightKg > 0 else { return nil }
        return tdd / weightKg
    }

    private var walsh500CR: Double? {
        guard let weightKg, weightKg > 0 else { return nil }
        return 500.0 / (weightKg * 0.55)
    }

    private var walsh300CR: Double? {
        guard let weightKg, weightKg > 0 else { return nil }
        return 300.0 / (weightKg * 0.55)
    }

    private var walshWeightCR: Double? {
        guard let weightKg, weightKg > 0 else { return nil }
        return (2.6 * weightKg / 0.45359237) / (weightKg * 0.55)
    }

    private var walsh100ISF: Double? {
        guard let weightKg, weightKg > 0 else { return nil }
        return 100.0 / (weightKg * 0.55)
    }
    
    private var walshTDD: Double? {
        guard let weightKg, weightKg > 0 else { return nil }
        return weightKg * 0.55
    }
    
    private var walshBasal: Double? {
        guard let weightKg, weightKg > 0 else { return nil }
        return (weightKg * 0.55) * 0.48
    }
    
    private var walshBasalPerHour: Double? {
        guard let weightKg, weightKg > 0 else { return nil }
        return (weightKg * 0.55) * 0.48 / 24
    }
    
    private var actualBasalPerHour: Double? {
        guard let actualBasal, actualBasal > 0 else { return nil }
        return actualBasal / 24
    }
    
    // MARK: - Walsh vs actual percentage helpers
    
    /// Returnerar en sträng som "(+12 %)" eller "(-8 %)" som visar hur mycket större/mindre Walsh är jämfört med aktuellt värde.
    private func walshPercentageString(walsh: Double?, actual: Double?) -> String? {
        guard let walsh, let actual, actual != 0 else { return nil }
        let ratio = walsh / actual
        let pct = (ratio - 1.0) * 100.0
        return String(format: "(%+0.0f %%)", pct)
    }
    
    // Walsh-värden relativt aktuella inställningar
    private var walshPercentageOfActual500CR: String? {
        walshPercentageString(walsh: walsh500CR, actual: actualDayCR)
    }
    
    private var walshPercentageOfActual300CR: String? {
        walshPercentageString(walsh: walsh300CR, actual: actualMorningCR)
    }
    
    private var walshPercentageOfActualWeightCR: String? {
        walshPercentageString(walsh: walshWeightCR, actual: actualDayCR)
    }
    
    private var walshPercentageOfActualISF: String? {
        walshPercentageString(walsh: walsh100ISF, actual: actualAverageISF)
    }
    
    private var walshPercentageOfActualTDD: String? {
        walshPercentageString(walsh: walshTDD, actual: tdd)
    }
    
    private var walshPercentageOfActualBasal: String? {
        walshPercentageString(walsh: walshBasal, actual: actualBasal)
    }
    
    private var walshPercentageOfActualBasalPerHour: String? {
        walshPercentageString(walsh: walshBasalPerHour, actual: actualBasalPerHour)
    }

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Inmatningsfält
                    Group {
                        HStack {
                            Text("Namn:")
                            Spacer()
                            TextField("Förnamn Efternamn", text: $name)
                                .multilineTextAlignment(.trailing)
                            if name == "" {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.red)
                            }
                        }

                        HStack {
                            Text("Längd:")
                            Spacer()
                            TextField("Ange längd", text: $heightText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("cm")
                            if heightText == "" {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.red)
                            }
                        }

                        HStack {
                            Text("Vikt:")
                            Spacer()
                            TextField("Ange vikt", text: $weightText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("kg")
                            if weightText == "" {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.red)
                            }
                        }

                        HStack {
                            Text("Total daglig dos (14d):")
                            Spacer()
                            TextField("Ange TDD", text: $tddText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("E")
                            if tddText == "" {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.red)
                            }
                        }
                        
                        HStack {
                            Text("Aktuell CR (morgon):")
                            Spacer()
                            TextField("Ange CR (morgon)", text: $actualMorningCRText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("g/E")
                            if actualMorningCRText == "" {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.red)
                            }
                        }
                        
                        HStack {
                            Text("Aktuell CR (dag):")
                            Spacer()
                            TextField("Ange CR (dag)", text: $actualDayCRText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("g/E")
                            if actualDayCRText == "" {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.red)
                            }
                        }
                        
                        HStack {
                            Text("Aktuell Basal (24h):")
                            Spacer()
                            TextField("Ange Basal", text: $actualBasalText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("E/d")
                            if actualBasalText == "" {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.red)
                            }
                        }
                        
                        HStack {
                            Text("Aktuell ISF (medel):")
                            Spacer()
                            TextField("Ange ISF", text: $actualAverageISFText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("mmol/L/E")
                            if actualAverageISFText == "" {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.red)
                            }
                        }
                        
                        HStack {
                            Text("Insulinbehov/kg:")
                            Spacer()
                            Text(insulinPerKg.map { String(format: "%.2f", $0) } ?? "--")
                            Text("E/kg/d")
                        }
                        
                        HStack {
                            Text("HbA1C (Blodprov):")
                            Spacer()
                            TextField("Ange HbA1C", text: $hbA1cText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text("mmol/mol")
                            if hbA1cText == "" {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Divider()
                            .padding(.top, 4)
                        
                        HStack {
                            Text("Födelsedatum:")
                            Spacer()
                            DatePicker(
                                "",
                                selection: $birthDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .environment(\.locale, Locale(identifier: "sv_SE"))
                            .labelsHidden()
                        }

                        HStack {
                            Text("T1D debutdatum:")
                            Spacer()
                            DatePicker(
                                "",
                                selection: $t1dSinceDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .environment(\.locale, Locale(identifier: "sv_SE"))
                            .labelsHidden()
                        }
                        
                        HStack {
                            Text("Data uppdaterad:")
                            Spacer()
                            DatePicker(
                                "",
                                selection: $updatedDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .environment(\.locale, Locale(identifier: "sv_SE"))
                            .labelsHidden()
                        }
                    }

                    Divider()
                        .padding(.top, 6)
                    HStack {
                        
                        Text("Walsh baseline")
                        Spacer()
                        Text("Beräknat värde (% vs inställt)")
                    }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)

                    // Kalkylerade rader (icke-editable)
                    Group {
                        HStack {
                            Text("Walsh 500-regeln CR:")
                            Spacer()
                            Text(walsh500CR.map { String(format: "%.1f", $0) } ?? "--")
                            Text("g/E")
                            if let pct = walshPercentageOfActual500CR {
                                Text(pct)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 6)

                        HStack {
                            Text("Walsh 300-regeln CR:")
                            Spacer()
                            Text(walsh300CR.map { String(format: "%.1f", $0) } ?? "--")
                            Text("g/E")
                            if let pct = walshPercentageOfActual300CR {
                                Text(pct)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 6)

                        HStack {
                            Text("Walsh Vikt-beräkning CR:")
                            Spacer()
                            Text(walshWeightCR.map { String(format: "%.1f", $0) } ?? "--")
                            Text("g/E")
                            if let pct = walshPercentageOfActualWeightCR {
                                Text(pct)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 6)

                        HStack {
                            Text("Walsh 100-regeln ISF:")
                            Spacer()
                            Text(walsh100ISF.map { String(format: "%.1f", $0) } ?? "--")
                            Text("mmol/L/E")
                            if let pct = walshPercentageOfActualISF {
                                Text(pct)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 6)

                        HStack {
                            Text("Walsh TDD:")
                            Spacer()
                            Text(walshTDD.map { String(format: "%.2f", $0) } ?? "--")
                            Text("E/dag")
                            if let pct = walshPercentageOfActualTDD {
                                Text(pct)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 6)

                        HStack {
                            Text("Walsh Basal:")
                            Spacer()
                            Text(walshBasal.map { String(format: "%.2f", $0) } ?? "--")
                            Text("E/dag")
                            if let pct = walshPercentageOfActualBasal {
                                Text(pct)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 6)

                        HStack {
                            Text("Walsh Basal/h:")
                            Spacer()
                            Text(walshBasalPerHour.map { String(format: "%.2f", $0) } ?? "--")
                            Text("E/h")
                            if let pct = walshPercentageOfActualBasalPerHour {
                                Text(pct)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .font(.subheadline)
                .padding()
            }
        }
        .navigationTitle(
            isReadOnly
            ? "Registrerad data"
            : (existingEntry == nil ? "Registrera ny data" : "Ändra registrering")
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isReadOnly {
                    Button("Klar") {
                        dismiss()
                    }
                } else {
                    Button("Spara") {
                        saveProfile()
                    }
                }
            }
        }
        .onAppear {
            if let existing = existingEntry {
                name = existing.name
                if let d = existing.birthDate { birthDate = d }
                if let d = existing.t1dSince { t1dSinceDate = d }
                if let h = existing.heightCm { heightText = String(format: "%.1f", h) }
                if let w = existing.weightKg { weightText = String(format: "%.1f", w) }
                if let dose = existing.tdd { tddText = String(format: "%.1f", dose) }
                if let hba1c = existing.hbA1c { hbA1cText = String(format: "%.0f", hba1c) }
                if let actualMorningCR = existing.actualMorningCR { actualMorningCRText = String(format: "%.1f", actualMorningCR) }
                if let actualDayCR = existing.actualDayCR { actualDayCRText = String(format: "%.1f", actualDayCR) }
                if let actualBasal = existing.actualBasal { actualBasalText = String(format: "%.2f", actualBasal) }
                if let actualAverageISF = existing.actualAverageISF { actualAverageISFText = String(format: "%.1f", actualAverageISF) }
                updatedDate = existing.updatedAt
            } else if let latest = Storage.shared.userProfiles.max(by: { $0.updatedAt < $1.updatedAt }) {
                name = latest.name
                if let d = latest.birthDate { birthDate = d }
                if let d = latest.t1dSince { t1dSinceDate = d }
                //if let h = latest.heightCm { heightText = String(format: "%.0f", h) }
                //if let w = latest.weightKg { weightText = String(format: "%.1f", w) }
                //if let dose = latest.tdd { tddText = String(format: "%.1f", dose) }
                //if let hba1c = latest.hbA1c { hbA1cText = String(format: "%.0f", hba1c) }
                if let actualMorningCR = latest.actualMorningCR { actualMorningCRText = String(format: "%.1f", actualMorningCR) }
                if let actualDayCR = latest.actualDayCR { actualDayCRText = String(format: "%.1f", actualDayCR) }
                if let actualBasal = latest.actualBasal { actualBasalText = String(format: "%.2f", actualBasal) }
                if let actualAverageISF = latest.actualAverageISF { actualAverageISFText = String(format: "%.1f", actualAverageISF) }
                updatedDate = Date()//latest.updatedAt
            }

            // Om vi skapar en NY registrering (existingEntry == nil)
            // och updatedDate är idag -> auto-populera actual*-fält från aktuell profil
            // (men inte i read-only-läge)
            if existingEntry == nil && !isReadOnly {
                populateActualFieldsFromCurrentProfile()
            }
        }
        .onChange(of: updatedDate) { newDate in
            // Auto-populera bara för NYA registreringar (existingEntry == nil) och ej i read-only-läge
            guard existingEntry == nil, !isReadOnly else { return }
            let calendar = Calendar.current
            clearActualFields()

            if calendar.isDateInToday(newDate) {
                populateActualFieldsFromCurrentProfile()
            }
        }
    }

    // MARK: - Helpers for auto-populating actual fields

    private func clearActualFields() {
        actualBasalText = ""
        actualMorningCRText = ""
        actualDayCRText = ""
        actualAverageISFText = ""
    }

    private func hourlyCR(from schedule: [ProfileManager.TimeValue<Double>]) -> [Int: Double] {
        var dict: [Int: Double] = [:]
        var last: Double?
        var scheduleByHour: [Int: Double] = [:]

        for entry in schedule {
            scheduleByHour[entry.timeAsSeconds / 3600] = entry.value
        }

        for hour in 0..<24 {
            if let new = scheduleByHour[hour] {
                last = new
            }
            if let last {
                dict[hour] = last
            }
        }
        return dict
    }

    private func hourlyISF(from schedule: [ProfileManager.TimeValue<HKQuantity>], unit: HKUnit) -> [Int: Double] {
        var dict: [Int: Double] = [:]
        var last: Double?
        var scheduleByHour: [Int: Double] = [:]

        for entry in schedule {
            scheduleByHour[entry.timeAsSeconds / 3600] = entry.value.doubleValue(for: unit)
        }

        for hour in 0..<24 {
            if let new = scheduleByHour[hour] {
                last = new
            }
            if let last {
                dict[hour] = last
            }
        }
        return dict
    }

    private func value(nearHour targetHour: Int, in dict: [Int: Double]) -> Double? {
        guard !dict.isEmpty else { return nil }
        guard let bestHour = dict.keys.min(by: { abs($0 - targetHour) < abs($1 - targetHour) }) else {
            return nil
        }
        return dict[bestHour]
    }

    private func populateActualFieldsFromCurrentProfile() {
        let calendar = Calendar.current
        guard calendar.isDateInToday(updatedDate) else { return }

        // Försök auto-populera TDD (14-dagars medelvärde) beräknad av SimpleStatsViewModel.
            if tddText.isEmpty {
                let storedTDD = UserDefaults.standard.double(forKey: "Stats14DayAverageTDD")
                if storedTDD > 0 {
                    tddText = String(format: "%.1f", storedTDD)
                }
            }
        
        let profile = ProfileManager.shared

        // actualBasal: total daglig basal från basalschemat
        if actualBasalText.isEmpty {
            var lastBasal: Double?
            var basalDict: [Int: Double] = [:]
            for entry in profile.basalSchedule {
                basalDict[entry.timeAsSeconds / 3600] = entry.value
            }

            var totalDailyBasal: Double = 0
            for hour in 0..<24 {
                if let newBasal = basalDict[hour] {
                    lastBasal = newBasal
                }
                if let basal = lastBasal {
                    totalDailyBasal += basal
                }
            }

            if totalDailyBasal > 0 {
                actualBasalText = String(format: "%.2f", totalDailyBasal)
            }
        }

        // actualMorningCR & actualDayCR från CR-schema (timme 08 och 18, närmaste)
        let crByHour = hourlyCR(from: profile.carbRatioSchedule)

        if actualMorningCRText.isEmpty, let morningCR = value(nearHour: 8, in: crByHour) {
            actualMorningCRText = String(format: "%.1f", morningCR)
        }

        if actualDayCRText.isEmpty, let dayCR = value(nearHour: 18, in: crByHour) {
            actualDayCRText = String(format: "%.1f", dayCR)
        }

        // actualAverageISF = medelvärde av ISF över dygnet
        let isfByHour = hourlyISF(from: profile.isfSchedule, unit: profile.units)
        if actualAverageISFText.isEmpty {
            let values = Array(isfByHour.values)
            if !values.isEmpty {
                let sum = values.reduce(0, +)
                let avg = sum / Double(values.count)
                actualAverageISFText = String(format: "%.1f", avg)
            }
        }
    }

    private func saveProfile() {
        let entry = UserProfileEntry(
            name: name,
            birthDate: birthDate,
            t1dSince: t1dSinceDate,
            heightCm: heightCm,
            weightKg: weightKg,
            tdd: tdd,
            hbA1c: hbA1c,
            actualBasal: actualBasal,
            actualMorningCR: actualMorningCR,
            actualDayCR: actualDayCR,
            actualAverageISF: actualAverageISF,
            updatedAt: updatedDate,
            insulinPerKg: insulinPerKg,
            walsh500CR: walsh500CR,
            walsh300CR: walsh300CR,
            walshWeightCR: walshWeightCR,
            walsh100ISF: walsh100ISF,
            walshTDD: walshTDD,
            walshBasal: walshBasal,
            walshBasalPerHour: walshBasalPerHour,
            actualBasalPerHour: actualBasalPerHour
        )

        var profiles = Storage.shared.userProfiles
        if let existing = existingEntry,
           let idx = profiles.firstIndex(where: { $0.updatedAt == existing.updatedAt && $0.name == existing.name }) {
            profiles[idx] = entry
        } else {
            profiles.append(entry)
        }
        Storage.shared.userProfiles = profiles

        NotificationCenter.default.post(name: .userProfileUpdated, object: nil)
        dismiss()
    }
}

@available(iOS 16.0, *)
private struct SettingsLogModal: UIViewControllerRepresentable {
    let initialSearchText: String

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = TrioSettingsLogView(initialSearchText: initialSearchText)
        let nav = UINavigationController(rootViewController: vc)
        
        // 1. Gör Navigationsbaren helt transparent (kopierat från din fungerande kod)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        
        // Se till att titeln syns (kan behövas om texten är vit/svart mot bakgrunden)
        // appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance
        
        // 2. Sätt bakgrunden på själva navigation viewn till transparent
        nav.view.backgroundColor = .clear
        
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        if let vc = uiViewController.viewControllers.first as? TrioSettingsLogView {
            // OBS: Detta anrop kan orsaka oönskad loop om du skriver i sökfältet
            // och SwiftUI uppdaterar vyn. Kontrollera att logiken i TrioSettingsLogView hanterar dubbletter.
            vc.setSearchTextAndFilter(initialSearchText)
        }
    }
}

extension Notification.Name {
    static let userProfileUpdated = Notification.Name("UserProfileUpdated")
}

extension UserProfileEntry: Identifiable {
    public var id: Date { updatedAt }
}

struct UserProfileCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let string = String(data: data, encoding: .utf8) {
            self.text = string
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return .init(regularFileWithContents: data)
    }
}

@available(iOS 16.0, *)
private struct SickDayCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [SickDayHistoryEntry]

    private var sickDayEntriesByDay: [Date: SickDayHistoryEntry] {
        Dictionary(
            uniqueKeysWithValues: entries.map {
                (calendar.startOfDay(for: Date(timeIntervalSince1970: $0.date)), $0)
            }
        )
    }

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "sv_SE")
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    private let monthSymbols: [String] = [
        "Januari", "Februari", "Mars",
        "April", "Maj", "Juni",
        "Juli", "Augusti", "September",
        "Oktober", "November", "December"
    ]

    private let weekdayHeaders = ["M", "T", "O", "T", "F", "L", "S"]

    private var sickDaySet: Set<Date> {
        Set(entries.map { calendar.startOfDay(for: Date(timeIntervalSince1970: $0.date)) })
    }

    private var displayYears: [Int] {
        let currentYear = calendar.component(.year, from: Date())
        let sickYears = entries.map { entry in
            calendar.component(.year, from: Date(timeIntervalSince1970: entry.date))
        }
        let earliestSickYear = sickYears.min() ?? currentYear
        let earliestDisplayYear = min(earliestSickYear, currentYear - 1)
        return Array(earliestDisplayYear...currentYear)
    }

    private func presentSickDayAnalysis(for entry: SickDayHistoryEntry) {
        let entryDate = Date(timeIntervalSince1970: entry.date)
        let startDate = calendar.startOfDay(for: entryDate)
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate)

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

        guard let mainVC, let endDate else {
            return
        }

        let events = mainVC.buildEventsForMealAnalysis()

        let analysisVC = MealAnalysisView(
            events: events,
            initialStart: startDate,
            initialEnd: endDate,
            modalWithTimestamp: true,
            modalTitleString: entry.notes,
            preSelectedSegment: 6
        )

        let nav = UINavigationController(rootViewController: analysisVC)
        nav.modalPresentationStyle = .formSheet

        func topMostPresenter(from root: UIViewController) -> UIViewController {
            var current = root
            while let presented = current.presentedViewController {
                current = presented
            }
            return current
        }

        let presenter = topMostPresenter(from: window.rootViewController ?? tabBar)
        presenter.present(nav, animated: true)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ThemeBackground()
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        Color.clear
                            .frame(height: 1)
                            .id("calendarTopAnchor")

                        ForEach(displayYears, id: \.self) { year in
                            VStack(alignment: .leading, spacing: 16) {
                                Text(String(year))
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .foregroundColor(.red)
                                    .padding(.horizontal)

                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3), spacing: 28) {
                                    ForEach(1...12, id: \.self) { month in
                                        SickDayMiniMonthView(
                                            year: year,
                                            month: month,
                                            calendar: calendar,
                                            monthName: monthSymbols[month - 1],
                                            weekdayHeaders: weekdayHeaders,
                                            sickDaySet: sickDaySet,
                                            sickDayEntriesByDay: sickDayEntriesByDay,
                                            onTapSickDay: { entry in
                                                presentSickDayAnalysis(for: entry)
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Sjukdagshistorik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") {
                        dismiss()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ScrollSickDayCalendarToCurrentYear"))) { _ in
                let currentYear = calendar.component(.year, from: Date())
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(currentYear, anchor: .top)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("ScrollSickDayCalendarToCurrentYear"), object: nil)
            }
        }
    }
}

@available(iOS 16.0, *)
private struct SickDayMiniMonthView: View {
    let year: Int
    let month: Int
    let calendar: Calendar
    let monthName: String
    let weekdayHeaders: [String]
    let sickDaySet: Set<Date>
    let sickDayEntriesByDay: [Date: SickDayHistoryEntry]
    let onTapSickDay: (SickDayHistoryEntry) -> Void

    private var monthDates: [Date?] {
        guard let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: firstDay)
        let offset = (weekday - calendar.firstWeekday + 7) % 7

        var result: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            if let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
                result.append(date)
            }
        }
        return result
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    private func isSickDay(_ date: Date) -> Bool {
        sickDaySet.contains(calendar.startOfDay(for: date))
    }

    private func sickDayEntry(for date: Date) -> SickDayHistoryEntry? {
        sickDayEntriesByDay[calendar.startOfDay(for: date)]
    }

    private func textColor(for date: Date) -> Color {
        if isSickDay(date) {
            return .white
        }
        if isToday(date) {
            return .blue
        }
        return .primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monthName)
                .font(.title3.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthDates.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let dayNumber = calendar.component(.day, from: date)

                        Text("\(dayNumber)")
                            .font(.system(size: 9, weight: isToday(date) || isSickDay(date) ? .semibold : .regular, design: .rounded))
                            .foregroundColor(textColor(for: date))
                            .frame(maxWidth: .infinity, minHeight: 15)
                            .background(
                                Group {
                                    if isSickDay(date) {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 15, height: 15)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white, lineWidth: isToday(date) ? 1 : 0)
                                            )
                                    } else if isToday(date) {
                                        Circle()
                                            .stroke(Color.white, lineWidth: 1)
                                            .frame(width: 15, height: 15)
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let entry = sickDayEntry(for: date) {
                                    onTapSickDay(entry)
                                }
                            }
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 15)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}


@available(iOS 17.0, *)
private struct TrainingStatsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPeriod: PeriodOption = .d14
    let sessions: [TrainingSessionEntry]

    private enum PeriodOption: CaseIterable {
        case d7, d14, d30, d90

        var days: Int {
            switch self {
            case .d7: return 7
            case .d14: return 14
            case .d30: return 30
            case .d90: return 90
            }
        }

        var title: String {
            switch self {
            case .d7: return "7 d"
            case .d14: return "14 d"
            case .d30: return "30 d"
            case .d90: return "90 d"
            }
        }
    }

    struct DayTotal: Identifiable {
        let id = UUID()
        let date: Date
        let metaQuestMinutes: Double
        let gympaMinutes: Double
        let highActivityMinutes: Double

        var minutes: Double {
            metaQuestMinutes + gympaMinutes + highActivityMinutes
        }
    }

    private var filteredSessions: [TrainingSessionEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDay = calendar.date(byAdding: .day, value: -(selectedPeriod.days - 1), to: today) ?? today
        let endDayExclusive = calendar.date(byAdding: .day, value: 1, to: today) ?? Date.distantFuture

        return sessions.filter { session in
            session.startDate >= startDay && session.startDate < endDayExclusive
        }
    }

    private var totalsPerDay: [DayTotal] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let startDay = calendar.date(byAdding: .day, value: -(selectedPeriod.days - 1), to: today) ?? today

        struct Bucket {
            var metaQuest: Double = 0
            var gympa: Double = 0
            var highActivity: Double = 0
        }

        var dict: [Date: Bucket] = [:]
        var days: [Date] = []

        for offset in 0..<selectedPeriod.days {
            if let day = calendar.date(byAdding: .day, value: offset, to: startDay) {
                let startOfDay = calendar.startOfDay(for: day)
                days.append(startOfDay)
                dict[startOfDay] = Bucket()
            }
        }

        for session in filteredSessions {
            let start = session.startDate
            let end = session.endDate ?? now
            let minutes = max(0, end.timeIntervalSince(start) / 60.0)
            let day = calendar.startOfDay(for: start)
            guard var bucket = dict[day] else { continue }

            switch session.category {
            case .metaQuest:
                bucket.metaQuest += minutes
            case .gympa:
                bucket.gympa += minutes
            case .highActivity:
                bucket.highActivity += minutes
            }

            dict[day] = bucket
        }

        return days.map {
            let bucket = dict[$0] ?? Bucket()
            return DayTotal(
                date: $0,
                metaQuestMinutes: bucket.metaQuest,
                gympaMinutes: bucket.gympa,
                highActivityMinutes: bucket.highActivity
            )
        }
    }

    private var totalSessionCount: Int {
        filteredSessions.count
    }

    private var averageMinutesPerSession: Double {
        guard totalSessionCount > 0 else { return 0 }
        let totalMinutes = filteredSessions.reduce(0.0) { partial, session in
            let end = session.endDate ?? Date()
            return partial + max(0, end.timeIntervalSince(session.startDate) / 60.0)
        }
        return totalMinutes / Double(totalSessionCount)
    }

    private var trainingDaysCount: Int {
        totalsPerDay.filter { $0.minutes > 0 }.count
    }

    private var averageMinutesPerTrainingDay: Double {
        guard trainingDaysCount > 0 else { return 0 }
        let totalMinutes = totalsPerDay.reduce(0.0) { $0 + $1.minutes }
        return totalMinutes / Double(trainingDaysCount)
    }

    private var percentageDaysWithTraining: Double {
        guard !totalsPerDay.isEmpty else { return 0 }
        return Double(trainingDaysCount) * 100.0 / Double(totalsPerDay.count)
    }

    private var longestTrainingStreak: Int {
        var best = 0
        var current = 0
        for item in totalsPerDay {
            if item.minutes > 0 {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private static let numberFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "sv_SE")
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 0
        return nf
    }()

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(PeriodOption.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if totalsPerDay.allSatisfy({ $0.minutes == 0 }) {
                        ContentUnavailableView(
                            "Ingen träningsdata",
                            systemImage: "chart.bar",
                            description: Text("När träningssessioner registreras visas statistik här.")
                        )
                        .padding(.top, 40)
                    } else {
                        TrainingStatsBarChartView(dayTotals: totalsPerDay)
                            .frame(height: 320)
                            .padding(.horizontal)
                            .padding(.top, 8)

                        VStack(spacing: 0) {
                            TrainingStatsRow(
                                title: "Totalt antal träningssessioner",
                                value: "\(totalSessionCount) st"
                            )
                            Divider().padding(.leading, 16)

                            TrainingStatsRow(
                                title: "Tid per träningssession",
                                value: "\(Int(averageMinutesPerSession.rounded())) min"
                            )
                            Divider().padding(.leading, 16)

                            TrainingStatsRow(
                                title: "Träningstid per träningsdag",
                                value: "\(Int(averageMinutesPerTrainingDay.rounded())) min"
                            )
                            Divider().padding(.leading, 16)

                            TrainingStatsRow(
                                title: "Andel dagar med träning",
                                value: "\(Int(percentageDaysWithTraining.rounded()))%"
                            )
                            Divider().padding(.leading, 16)

                            TrainingStatsRow(
                                title: "Längsta streak dagar med träning",
                                value: "\(longestTrainingStreak) d"
                            )
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(UIColor.systemGray).opacity(0.15))
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .navigationTitle("Träningsstatistik")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Klar") {
                    dismiss()
                }
            }
        }
    }
}

@available(iOS 17.0, *)
private struct TrainingStatsRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundColor(.primary)

            Spacer(minLength: 8)

            Text(value)
                .font(.body.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

@available(iOS 17.0, *)
@available(iOS 17.0, *)
private struct TrainingStatsBarChartView: UIViewRepresentable {
    let dayTotals: [TrainingStatsView.DayTotal]

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.isUserInteractionEnabled = true

        let chartView = BarChartView()
        chartView.backgroundColor = .clear
        chartView.drawGridBackgroundEnabled = true
        chartView.gridBackgroundColor = UIColor.systemBackground.withAlphaComponent(0.5)
        chartView.drawBordersEnabled = false
        chartView.chartDescription.enabled = false

        chartView.legend.enabled = true
        chartView.legend.verticalAlignment = .bottom
        chartView.legend.horizontalAlignment = .center
        chartView.legend.orientation = .horizontal
        chartView.legend.drawInside = false
        chartView.legend.yOffset = 8
        chartView.legend.textColor = .secondaryLabel
        chartView.legend.font = .systemFont(ofSize: 11, weight: .medium)

        chartView.rightAxis.enabled = false
        chartView.leftAxis.enabled = true

        chartView.isUserInteractionEnabled = true
        chartView.drawMarkers = false
        chartView.pinchZoomEnabled = false
        chartView.doubleTapToZoomEnabled = false
        chartView.scaleXEnabled = false
        chartView.scaleYEnabled = false
        chartView.highlightPerTapEnabled = false
        chartView.dragEnabled = false

        let xAxis = chartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.drawAxisLineEnabled = false
        xAxis.drawGridLinesEnabled = true
        xAxis.gridLineWidth = 0.5
        xAxis.gridColor = NSUIColor.label.withAlphaComponent(0.15)
        xAxis.granularityEnabled = true
        xAxis.centerAxisLabelsEnabled = false
        xAxis.labelTextColor = .secondaryLabel
        xAxis.labelFont = .systemFont(ofSize: 10, weight: .medium)

        let leftAxis = chartView.leftAxis
        leftAxis.drawAxisLineEnabled = false
        leftAxis.drawGridLinesEnabled = true
        leftAxis.gridLineWidth = 0.5
        leftAxis.gridColor = NSUIColor.label.withAlphaComponent(0.12)
        leftAxis.axisMinimum = 0
        leftAxis.labelTextColor = .secondaryLabel
        leftAxis.labelFont = .systemFont(ofSize: 10, weight: .medium)
        leftAxis.valueFormatter = DefaultAxisValueFormatter(block: { value, _ in
            String(format: "%.0f", value)
        })

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

        let sorted = dayTotals.sorted { $0.date < $1.date }
        let count = sorted.count

        guard count > 0 else {
            chartView.data = nil
            chartView.notifyDataSetChanged()
            chartView.setNeedsDisplay()
            return
        }

        let dateFormatter: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "sv_SE")
            df.dateFormat = "dd/M"
            return df
        }()

        let labels = sorted.map { dateFormatter.string(from: $0.date) }

        let shownLabelIndices: Set<Int> = {
            if count <= 14 {
                return Set(0..<count)
            }

            var result: Set<Int> = []
            for i in 0..<7 {
                let t = Double(i) / 6.0
                let idx = Int((t * Double(count - 1)).rounded())
                result.insert(max(0, min(count - 1, idx)))
            }
            return result
        }()

        let entries: [BarChartDataEntry] = sorted.enumerated().map { idx, item in
            BarChartDataEntry(
                x: Double(idx),
                yValues: [item.metaQuestMinutes, item.gympaMinutes, item.highActivityMinutes]
            )
        }

        let maxValue = sorted.map { $0.minutes }.max() ?? 0
        let axisMaximum = max(30, ceil(maxValue * 1.12 / 10.0) * 10.0)
        chartView.leftAxis.axisMaximum = axisMaximum
        chartView.leftAxis.axisMinimum = 0

        let labelCount: Int
        switch axisMaximum {
        case 0...60:
            labelCount = 6
        case 60...180:
            labelCount = 7
        default:
            labelCount = 8
        }
        chartView.leftAxis.setLabelCount(labelCount, force: false)

        let dataSet = BarChartDataSet(entries: entries, label: "Träning")
        dataSet.colors = [
            NSUIColor.systemGreen,
            NSUIColor.systemGreen.withAlphaComponent(0.5),
            NSUIColor.systemGreen.withAlphaComponent(0.2)
        ]
        dataSet.stackLabels = ["Meta Quest", "Gympa", "Hög aktivitet"]
        dataSet.drawValuesEnabled = false
        dataSet.highlightEnabled = false

        let data = BarChartData(dataSet: dataSet)
        data.barWidth = 0.62

        chartView.xAxis.axisMinimum = -0.5
        chartView.xAxis.axisMaximum = Double(count) - 0.5
        chartView.xAxis.granularity = 1.0
        chartView.xAxis.labelCount = min(count <= 14 ? count : 7, 7)
        chartView.xAxis.forceLabelsEnabled = false
        chartView.xAxis.valueFormatter = DefaultAxisValueFormatter(block: { value, _ in
            let idx = Int(value.rounded())
            guard idx >= 0, idx < labels.count else { return "" }
            guard shownLabelIndices.contains(idx) else { return "" }
            return labels[idx]
        })

        let legendEntries: [LegendEntry] = [
            {
                let e = LegendEntry(label: "Meta Quest")
                e.form = .square
                e.formColor = NSUIColor.systemGreen
                return e
            }(),
            {
                let e = LegendEntry(label: "Gympa")
                e.form = .square
                e.formColor = NSUIColor.systemGreen.withAlphaComponent(0.75)
                return e
            }(),
            {
                let e = LegendEntry(label: "Hög aktivitet")
                e.form = .square
                e.formColor = NSUIColor.systemGreen.withAlphaComponent(0.5)
                return e
            }()
        ]
        chartView.legend.setCustom(entries: legendEntries)

        chartView.data = data
        chartView.notifyDataSetChanged()
        chartView.setNeedsDisplay()
    }
}
