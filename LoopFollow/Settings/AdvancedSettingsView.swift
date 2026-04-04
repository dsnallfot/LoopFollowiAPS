//
//  AdvancedSettingsView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-23.

//

import SwiftUI
import UIKit
import Charts

@available(iOS 26.0, *)
struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: AdvancedSettingsViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var showClippyHistory = false

    @available(iOS 26.0, *)
    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // MARK: - Avancerade inställningar
                    Text("Avancerade inställningar")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        themedRow {
                            Toggle("Ladda ner behandlingar", isOn: $viewModel.downloadTreatments)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Ladda ner prognoser", isOn: $viewModel.downloadPrediction)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Rendera basal", isOn: $viewModel.graphBasal)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Rendera bolusar", isOn: $viewModel.graphBolus)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Rendera måltider", isOn: $viewModel.graphCarbs)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Rendera andra behandlingar", isOn: $viewModel.graphOtherTreatments)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Stepper(value: $viewModel.bgUpdateDelay, in: 1...30, step: 1) {
                                Text("BG fördröjning (sek): \(viewModel.bgUpdateDelay)")
                            }
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Tillåt Clippy-info", isOn: $viewModel.allowClippy)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            HStack {
                                Text("Clippy historik")
                                Spacer()
                                Button {
                                    showClippyHistory = true
                                } label: {
                                    Text("Visa")
                                        .frame(width: 70, alignment: .center)
                                }
                                .buttonStyle(.glassProminent)
                            }
                        }
                    }
                    .themedCardBackground(opacity: 0.15)

                    // MARK: - Loggalternativ
                    Text("Loggalternativ")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)

                    VStack(spacing: 0) {
                        themedRow {
                            Toggle("Visa debugloggar", isOn: $viewModel.debugLogLevel)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Visa temporära debugloggar", isOn: $viewModel.tempDebugLogLevel)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Ladda upp appstart till NS", isOn: $viewModel.uploadAppStartNote)
                        }
                    }
                    .themedCardBackground(opacity: 0.15)
                    
                    Text("Manuell arkivering/export")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    
                    VStack(spacing: 0) {
                        themedRow {
                            HStack {
                                Text("Spara fg månad")
                                Spacer()
                            Button {
                                viewModel.archivePreviousMonth()
                            } label: {
                                Text("Arkivera")
                                    .frame(width: 70, alignment: .center)
                            }
                            .buttonStyle(.glassProminent)
                        }
                            
                        }
                        if !viewModel.lastArchiveDebugMessage.isEmpty {
                            Divider().opacity(0.8)
                            themedRow {
                                Text(viewModel.lastArchiveDebugMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            HStack {
                                Text("Skapa zip för hela arkivet")
                                Spacer()
                            Button {
                                viewModel.exportArchiveZipAndShare()
                            } label: {
                                Text("Export")
                                    .frame(width: 70, alignment: .center)
                            }
                            .buttonStyle(.glassProminent)
                        }
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            HStack {
                                Text("Skapa zip för fg månad")
                                Spacer()
                                Button {
                                    viewModel.exportLatestArchivedMonthZipAndShare()
                                } label: {
                                    Text("Export")
                                        .frame(width: 70, alignment: .center)
                                }
                                .buttonStyle(.glassProminent)
                            }

                        }
                        if !viewModel.lastArchiveExportMessage.isEmpty {
                            Divider().opacity(0.8)
                            themedRow {
                                Text(viewModel.lastArchiveExportMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .themedCardBackground(opacity: 0.15)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showClippyHistory) {
            ClippyHistoryView()
        }
        .sheet(isPresented: $viewModel.isPresentingArchiveShareSheet, onDismiss: {
            viewModel.handleArchiveShareSheetDismissed()
        }) {
            if let url = viewModel.archiveShareURL {
                ActivityView(activityItems: [url])
            }
        }
    }

    @ViewBuilder
    private func themedRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .tint(Color(uiColor: .systemGreen))
    }
}

@available(iOS 26.0, *)
private struct ClippyHistoryView: View {
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
            .navigationTitle("Clippy historik")
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
}

@available(iOS 26.0, *)
private struct ClippyHistoryStatsView: View {
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
                .navigationTitle("Målgång tid")
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

        setupChartHeader()
        applyPeriod(selectedPeriod)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        0
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

        reachedEntries = []
        missedEntries = []

        for (index, day) in selectedDays.enumerated() {
            if let entry = historyByDay[day] {
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
}
