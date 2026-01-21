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
        case profile = "Profil"
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
            AddUserDataView()
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

    var body: some View {
        ZStack {
            //ThemeBackground()
                //.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geometry in
                    let imageSide = geometry.size.width / 4

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

                        // Frames 2 & 3: Rubriker + placeholder-värden
                        HStack(alignment: .top, spacing: 12) {
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

                            // Frame 3: Placeholder-värden
                            VStack(alignment: .leading, spacing: 4) {
                                Text("<<Förnamn Efternamn>>")
                                Text("<<ÅÅ-MM-DD>>")
                                Text("<<ÅÅ-MM-DD>>")
                                Text("<<XXX>> cm")
                                Text("<<XX>> kg")
                                Text("<<ÅÅ-MM-DD>>")
                            }
                            .font(.caption2)
                            .foregroundColor(.secondary)

                            Spacer()
                        }
                        .frame(height: imageSide, alignment: .top)
                    }
                    .padding(.top, 16)
                    .padding(.horizontal)
                }

                Spacer()
            }
        }
        .onAppear {
            if profileImage == nil {
                profileImage = UserProfileImageManager.shared.load()
            }
        }
    }
}

// MARK: - AddUserDataView placeholder

@available(iOS 16.0, *)
private struct AddUserDataView: View {
    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("AddUserDataView")
                    .font(.headline)

                Text("Här bygger vi vidare senare.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
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
