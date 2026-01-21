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

@available(iOS 16.0, *)
private struct LogSearchItem: Identifiable {
    let term: String
    var id: String { term }
}

@available(iOS 16.0, *)
struct ProfileSchedulesView: View {
    @ObservedObject var viewModel = ProfileSchedulesViewModel()
    
    @State private var selectedSection: SectionType = .targets // Default section
    @State private var showProfileUpdatedAlert: Bool = false
    @State private var selectedLogSearchItem: LogSearchItem?
    @State private var selectedMode: Mode = .profile
    @State private var showAddUserData: Bool = false

    enum Mode: String, CaseIterable {
        case profile = "Profilinställningar"
        case user = "Användare"
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

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top-level mode picker: Profil / Användare
                Picker("Mode", selection: $selectedMode) {
                    ForEach(Mode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding([.top, .horizontal])

                if selectedMode == .profile {
                    Picker("Select Section", selection: $selectedSection) {
                        ForEach(SectionType.allCases, id: \.self) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .padding(.top, 8)

                    LineChartWrapper(chartData: multiChartData, title: selectedSection.displayName)
                        .frame(height: 150)
                        .padding(.horizontal)

                    List {
                        if selectedSection == .targets {
                                Section(header: sectionHeader(title: "🟪 Mål (mmol/L)", lastChanged: viewModel.lastChangedTargetProfile)) {
                                ForEach(viewModel.targetEntries) { entry in
                                    scheduleRow(entry)
                                        .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                                        .contentShape(Rectangle())
                                        .onTapGesture { openSettingsLog(for: "Mål-profil") }
                                }
                            }
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                        }

                        if selectedSection == .basal {
                            Section(header: sectionHeader(title: "🟪 Basal (E/h)", lastChanged: viewModel.lastChangedBasalProfile)) {
                                ForEach(viewModel.basalEntries) { entry in
                                    scheduleRow(entry, isBold: entry.time == "Total daglig basal")
                                        .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                                        .contentShape(Rectangle())
                                }
                            }
                            .onTapGesture { openSettingsLog(for: "Basalprofil") }
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.1))

                            Section(header: Text("🟦 Basal IOB (E aktiv/h)")) {
                                ForEach(viewModel.basalIOBEntries) { entry in
                                    scheduleRow(entry, isBold: entry.time == "Medel basal IOB/h")
                                        .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                                        .contentShape(Rectangle())
                                }
                            }
                            .onTapGesture { openSettingsLog(for: "Basalprofil") }
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                        }

                        if selectedSection == .cr {
                            Section(header: sectionHeader(title: "🟪 Insulinkvoter (g/E)", lastChanged: viewModel.lastChangedCRProfile)) {
                                ForEach(viewModel.carbRatioEntries) { entry in
                                    scheduleRow(entry)
                                        .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                                        .contentShape(Rectangle())
                                }
                            }
                            .onTapGesture { openSettingsLog(for: "CR-profil") }
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                        }

                        if selectedSection == .isf {
                            Section(header: sectionHeader(title: "🟪 Känslighet (mmol/L/E)", lastChanged: viewModel.lastChangedISFProfile)) {
                                ForEach(viewModel.isfEntries) { entry in
                                    scheduleRow(entry)
                                        .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                                        .contentShape(Rectangle())
                                        .onTapGesture { openSettingsLog(for: "ISF-profil") }
                                }
                            }
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                        }

                            if selectedSection == .csf {
                                Section(header: Text("🟪 Kh-känslighet (mmol/L/g)")) {
                                    ForEach(viewModel.csfEntries) { entry in
                                        scheduleRow(entry)
                                            .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                                    }
                                }
                                    .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                                }

                        if selectedSection == .cHr {
                            Section(header: Text("🟪 Minsta absorption Kh (g/h)")) {
                                ForEach(viewModel.minCarbsEntries) { entry in
                                    scheduleRow(entry, isBold: entry.time == "Medelvärde")
                                        .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                                }
                            }
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                        }

                        if selectedSection == .smb {
                            Section(header: Text("🟦 Maxgräns SMB / UAMSMB (E/SMB)")) {
                                ForEach(viewModel.smbEntries) { entry in
                                    scheduleRow(entry)
                                        .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                                }
                            }
                            .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                } else {
                    UserDataViewController()
                }
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
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if selectedMode == .profile {
                    Button {
                        showProfileUpdatedAlert = true
                    } label: {
                        Image(systemName: "info")
                    }
                    .accessibilityLabel("Profil laddades ner:")
                } else {
                    Button {
                        showAddUserData = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Lägg till användardata")
                }
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
                .font(isBold ? .headline.bold() : .subheadline)
            Spacer()
            Text(entry.value)
                .font(isBold ? .headline.bold() : .subheadline)
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

    private static let shortDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    var body: some View {
        ZStack {
            //ThemeBackground()
                //.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header: profilbild + senaste profilinfo
                let imageSide = UIScreen.main.bounds.width / 4

                HStack(alignment: .top, spacing: 12) {
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
                    Spacer()

                    // Frames 2 & 3: Rubriker + värden
                    HStack(alignment: .top, spacing: 24) {
                        // Frame 2: Rubriker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Namn:")
                            Text("Född:")
                            Text("T1D sedan:")
                            Text("Längd:")
                            Text("Vikt:")
                            Text("Uppdaterades:")
                        }
                        .font(.caption2)

                        // Frame 3: Värden (senaste profil eller placeholders)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile?.name ?? "<<Förnamn Efternamn>>")
                            Text(profile?.birthDate.map { Self.shortDateFormatter.string(from: $0) } ?? "<<ÅÅ-MM-DD>>")
                            Text(profile?.t1dSince.map { Self.shortDateFormatter.string(from: $0) } ?? "<<ÅÅ-MM-DD>>")
                            Text(profile?.heightCm.map { String(format: "%.0f cm", $0) } ?? "<<XXX>> cm")
                            Text(profile?.weightKg.map { String(format: "%.1f kg", $0) } ?? "<<XX>> kg")
                            Text(profile.map { Self.shortDateFormatter.string(from: $0.updatedAt) } ?? "<<ÅÅ-MM-DD>>")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)

                        //Spacer()
                    }
                    .frame(height: imageSide, alignment: .top)
                }
                .padding(.vertical, 16)
                .padding(.leading, 36)
                .padding(.trailing, 36)

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
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if let hb = entry.hbA1c {
                    ZStack {
                        Circle()
                            .fill(hbColor(for: hb))
                            .frame(width: 26, height: 26)

                        Text(String(format: "%.0f", hb))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(Color(.systemGray4))
                            .frame(width: 26, height: 26)

                        Text("--")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
            }

            let tddString = entry.tdd.map { String(format: "%.1f", $0) } ?? "--"
            let weightString = entry.weightKg.map { String(format: "%.1f", $0) } ?? "--"
            let heightString = entry.heightCm.map { String(format: "%.0f", $0) } ?? "--"
            let insulinPerKgString = entry.insulinPerKg.map { String(format: "%.2f", $0) } ?? "--"

            Text("TDD: \(tddString) E • Vikt: \(weightString) kg • Längd: \(heightString) cm • Insulin/kg: \(insulinPerKgString) E")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
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
                        }

                        HStack {
                            Text("Längd:")
                            Spacer()
                            TextField("Ange längd", text: $heightText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("cm")
                        }

                        HStack {
                            Text("Vikt:")
                            Spacer()
                            TextField("Ange vikt", text: $weightText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("kg")
                        }

                        HStack {
                            Text("Total daglig dos (14d):")
                            Spacer()
                            TextField("Ange TDD", text: $tddText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("E")
                        }
                        
                        HStack {
                            Text("Aktuell CR (morgon):")
                            Spacer()
                            TextField("Ange CR (morgon)", text: $actualMorningCRText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("E")
                        }
                        
                        HStack {
                            Text("Aktuell CR (dag):")
                            Spacer()
                            TextField("Ange CR (dag)", text: $actualDayCRText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("E")
                        }
                        
                        HStack {
                            Text("Aktuell Basal (24h):")
                            Spacer()
                            TextField("Ange Basal", text: $actualBasalText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("E")
                        }
                        
                        HStack {
                            Text("Aktuell ISF (medel):")
                            Spacer()
                            TextField("Ange ISF", text: $actualAverageISFText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("E")
                        }
                        
                        HStack {
                            Text("Insulinbehov/kg:")
                            Spacer()
                            Text(insulinPerKg.map { String(format: "%.2f", $0) } ?? "--")
                            Text("E/kg")
                        }
                        
                        HStack {
                            Text("HbA1C:")
                            Spacer()
                            TextField("Ange HbA1C", text: $hbA1cText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text("mmol/mol")
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

                    Text("Beräknade värden")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)

                    // Kalkylerade rader (icke-editable)
                    Group {
                        HStack {
                            Text("Walsh 500-regeln CR (Dag):")
                            Spacer()
                            Text(walsh500CR.map { String(format: "%.1f", $0) } ?? "--")
                            Text("g/E")
                        }
                        .padding(.bottom, 6)

                        HStack {
                            Text("Walsh 300-regeln CR (Frukost):")
                            Spacer()
                            Text(walsh300CR.map { String(format: "%.1f", $0) } ?? "--")
                            Text("g/E")
                        }
                        .padding(.bottom, 6)

                        HStack {
                            Text("Walsh Vikt-beräkning CR:")
                            Spacer()
                            Text(walshWeightCR.map { String(format: "%.1f", $0) } ?? "--")
                            Text("g/E")
                        }
                        .padding(.bottom, 6)

                        HStack {
                            Text("Walsh 100-regeln ISF:")
                            Spacer()
                            Text(walsh100ISF.map { String(format: "%.1f", $0) } ?? "--")
                            Text("mmol/L/E")
                        }
                        .padding(.bottom, 6)

                        HStack {
                            Text("Walsh TDD:")
                            Spacer()
                            Text(walshTDD.map { String(format: "%.2f", $0) } ?? "--")
                            Text("E/dag")
                        }
                        .padding(.bottom, 6)

                        HStack {
                            Text("Walsh Basal:")
                            Spacer()
                            Text(walshBasal.map { String(format: "%.2f", $0) } ?? "--")
                            Text("E/dag")
                        }
                        .padding(.bottom, 6)

                        HStack {
                            Text("Walsh Basal/h:")
                            Spacer()
                            Text(walshBasalPerHour.map { String(format: "%.2f", $0) } ?? "--")
                            Text("E/h")
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
            : (existingEntry == nil ? "Registrera data" : "Ändra registrering")
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
                if let h = existing.heightCm { heightText = String(format: "%.0f", h) }
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
                if let h = latest.heightCm { heightText = String(format: "%.0f", h) }
                if let w = latest.weightKg { weightText = String(format: "%.1f", w) }
                if let dose = latest.tdd { tddText = String(format: "%.1f", dose) }
                if let hba1c = latest.hbA1c { hbA1cText = String(format: "%.0f", hba1c) }
                if let actualMorningCR = latest.actualMorningCR { actualMorningCRText = String(format: "%.1f", actualMorningCR) }
                if let actualDayCR = latest.actualDayCR { actualDayCRText = String(format: "%.1f", actualDayCR) }
                if let actualBasal = latest.actualBasal { actualBasalText = String(format: "%.2f", actualBasal) }
                if let actualAverageISF = latest.actualAverageISF { actualAverageISFText = String(format: "%.1f", actualAverageISF) }
                updatedDate = latest.updatedAt
            }

            // Om vi skapar en NY registrering (existingEntry == nil)
            // och updatedDate är idag -> auto-populera actual*-fält från aktuell profil
            // (men inte i read-only-läge)
            if existingEntry == nil && !isReadOnly {
                populateActualFieldsFromCurrentProfile()
            }
        }
        .onChange(of: updatedDate) { newDate in
            guard !isReadOnly else { return }
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
