//
//  LogView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-13.

//

import SwiftUI
import Charts

@available(iOS 26.0, *)
struct LogView: View {
    @ObservedObject var viewModel = LogViewModel()
    @State private var isChartPresented: Bool = false
    @State private var isHeartbeatPresented: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    /// Används när vyn ligger i UIKit-nav/modal
    let onDone: (() -> Void)?

    // MARK: - MultiFilter logic
    private struct MultiFilter: Identifiable {
        let id: Int
        let term: String
        let color: Color
    }

    /// Split search text by '.' into up to 3 filters: [blue, yellow, red]
    private var multiFilters: [MultiFilter] {
        let rawParts = viewModel.searchText
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let palette: [Color] = [.blue, .yellow, .red]
        return rawParts.prefix(3).enumerated().map { idx, term in
            MultiFilter(id: idx, term: term, color: palette[idx])
        }
    }

    private func matchingFilter(for line: String) -> MultiFilter? {
        guard !multiFilters.isEmpty else { return nil }
        let lower = line.lowercased()
        return multiFilters.first(where: { lower.contains($0.term.lowercased()) })
    }


    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Picker("Category", selection: $viewModel.selectedCategory) {
                    Text("Allt").tag(LogManager.Category?.none)
                    ForEach(LogManager.Category.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(LogManager.Category?.some(category))
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.horizontal)

                SearchBar(
                    text: $viewModel.searchText,
                    placeholder: viewModel.searchResultsIsHighlighted
                        ? "Highlighta i loggen"
                        : "Sök i loggen"
                )
                .padding(.horizontal)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.filteredLogEntries) { entry in
                            Text(entry.text)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 0)
                                .foregroundColor(
                                    matchingFilter(for: entry.text)?.color
                                    ?? .primary
                                )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .background(Color.clear)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: {
                    viewModel.searchResultsIsHighlighted.toggle()
                }) {
                    Image(systemName: viewModel.searchResultsIsHighlighted
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .foregroundColor(viewModel.searchResultsIsHighlighted ? .blue : .primary)

                Button(action: {
                    isHeartbeatPresented = true
                }) {
                    Image(systemName: "bolt.heart")
                }
                .accessibilityLabel("Bluetooth heartbeats")
                
                Button(action: {
                    isChartPresented = true
                }) {
                    Image(systemName: "chart.bar.xaxis.ascending")
                }
                .accessibilityLabel("chart")

                
            }
        }
        .onAppear {
            viewModel.loadLogEntries()
        }
        .sheet(isPresented: $isChartPresented) {
            // Bygg upp matchade serier per filter (upp till 3)
            let filters = multiFilters

            let series: [LogViewChart.Series] = filters.map { f in
                let matched = viewModel.filteredLogEntries.filter { entry in
                    entry.text.localizedCaseInsensitiveContains(f.term)
                }
                return .init(id: f.id, label: f.term, color: f.color, entries: matched)
            }
            
            // Bygg en rubrik som inkluderar antal per filter/färg, t.ex. "Träffar: 🟦25 🟨32 🟥122"
            let emojiForSeriesId: [Int: String] = [0: "🟦", 1: "🟨", 2: "🟥"]
            let orderedForTitle = series.sorted(by: { $0.id < $1.id })
            let titleSuffix = orderedForTitle
                .map { s in
                    let emoji = emojiForSeriesId[s.id] ?? ""
                    return "\(emoji)\(s.entries.count) "
                }
                .joined(separator: " ")

            let chartTitle = titleSuffix.isEmpty ? "Sökträffar" : "Sökträffar:  \(titleSuffix)"

            LogViewChart(
                title: chartTitle,
                // För special-statistik vill vi utgå från "hela" loggen (inte nödvändigtvis bara sökträffarna).
                allLogEntries: viewModel.allLogEntries,
                series: series
            )
        }
        .sheet(isPresented: $isHeartbeatPresented) {
            HeartbeatView()
                .presentationBackground(
                    LinearGradient(
                        colors: ThemedViewController.themeGradientColors(intensity: 1.0).map { Color($0) },
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

}

@available(iOS 16.0, *)
private struct HeartbeatView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = HeartbeatStatsViewController()
        let nav = UINavigationController(rootViewController: vc)
        
        // Gör navigation controllern helt transparent så att sheet-bakgrunden syns igenom
        nav.view.backgroundColor = .clear
        nav.view.isOpaque = false

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance
        
        vc.view.backgroundColor = .clear
        vc.view.isOpaque = false

        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) { }
}

@available(iOS 16.0, *)
private final class HeartbeatStatsViewController: ThemedTableViewController {

    private struct DayValue {
        let date: Date
        let dateString: String
        let count: Int
    }

    private enum PeriodOption: CaseIterable {
        case d1, d7, d14, d30, d90

        var days: Int {
            switch self {
            case .d1:  return 1
            case .d7:  return 7
            case .d14: return 14
            case .d30: return 30
            case .d90: return 90
            }
        }

        var title: String {
            switch self {
            case .d1:  return "1 d"
            case .d7:  return "7 d"
            case .d14: return "14 d"
            case .d30: return "30 d"
            case .d90: return "90 d"
            }
        }
    }

    private enum StatRow: Int, CaseIterable {
        case today
        case average
        case bestDay
        case worstDay

        var label: String {
            switch self {
            case .today:   return "Heartbeats idag"
            case .average: return "Medel per dag"
            case .bestDay: return "Bästa dag"
            case .worstDay: return "Sämsta dag"
            }
        }
    }

    private let expectedPerDay = 288
    private var selectedPeriod: PeriodOption = .d7
    private var selectedValues: [DayValue] = []

    private lazy var periodControl: UISegmentedControl = {
        let items = PeriodOption.allCases.map { $0.title }
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = PeriodOption.allCases.firstIndex(of: selectedPeriod) ?? 1
        sc.addTarget(self, action: #selector(periodChanged(_:)), for: .valueChanged)
        return sc
    }()

    private let chartView: BarChartView = {
        let v = BarChartView()
        v.legend.enabled = false
        v.chartDescription.enabled = false
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

    private let numberFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "sv_SE")
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 1
        return nf
    }()

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private let axisDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "dd/MM"
        return formatter
    }()

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
    
    // 🟩 Tvingar tabellen att förbli helt transparent
        override func updateBackgroundForCurrentMode() {
            view.backgroundColor = .clear
            tableView.backgroundColor = .clear
            tableView.backgroundView = nil
            tableView.isOpaque = false
        }

    override func viewDidLoad() {
        super.viewDidLoad()
                
        updateBackgroundForCurrentMode()
        title = "Heartbeats"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissSelf)
        )

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HeartbeatStatCell")
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.isOpaque = false
        tableView.layer.backgroundColor = UIColor.clear.cgColor

        tableView.contentInsetAdjustmentBehavior = .automatic

        setupChartHeader()
        applyPeriod(selectedPeriod)
    }

    private func setupChartHeader() {
        let container = UIView()
        container.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 340)
        container.backgroundColor = .clear
        //container.isOpaque = false

        chartView.backgroundColor = .clear
        periodControl.backgroundColor = .clear

        container.addSubview(periodControl)
        container.addSubview(chartView)

        periodControl.translatesAutoresizingMaskIntoConstraints = false
        chartView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            periodControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            periodControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            periodControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            chartView.topAnchor.constraint(equalTo: periodControl.bottomAnchor, constant: 16),
            chartView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            chartView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            chartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
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

    @objc private func periodChanged(_ sender: UISegmentedControl) {
        let index = sender.selectedSegmentIndex
        guard index >= 0 && index < PeriodOption.allCases.count else { return }
        applyPeriod(PeriodOption.allCases[index])
    }

    private func applyPeriod(_ period: PeriodOption) {
        selectedPeriod = period
        selectedValues = buildValues(daysBack: period.days)
        loadChartData()
        tableView.reloadData()
    }

    private func buildValues(daysBack: Int) -> [DayValue] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let historyByDate = Dictionary(
            uniqueKeysWithValues: Storage.shared.bluetoothPingDailyHistory.map { ($0.date, $0.count) }
        )

        let currentDateString = Storage.shared.bluetoothPingCurrentDate.value
        let currentCount = Storage.shared.bluetoothPingCurrentCount.value

        var values: [DayValue] = []
        values.reserveCapacity(daysBack)

        for offset in stride(from: daysBack - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dateString = dayFormatter.string(from: day)
            let storedCount = historyByDate[dateString] ?? 0
            let count = (dateString == currentDateString) ? currentCount : storedCount
            values.append(DayValue(date: day, dateString: dateString, count: count))
        }

        return values
    }

    private func loadChartData() {
        guard !selectedValues.isEmpty else {
            chartView.data = nil
            chartView.setNeedsDisplay()
            return
        }

        let entries = selectedValues.enumerated().map { idx, value in
            BarChartDataEntry(x: Double(idx), y: Double(value.count))
        }

        let dataSet = BarChartDataSet(entries: entries, label: "")
        dataSet.setColor(.systemTeal.withAlphaComponent(0.7))
        dataSet.drawValuesEnabled = false
        dataSet.barBorderColor = .black
        dataSet.barBorderWidth = 0.5

        let data = BarChartData(dataSet: dataSet)
        chartView.data = data
        chartView.autoScaleMinMaxEnabled = false
        chartView.notifyDataSetChanged()

        chartView.drawGridBackgroundEnabled = true
        chartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)

        let labels = selectedValues.map { axisDateFormatter.string(from: $0.date) }
        let xAxis = chartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.granularity = 1
        xAxis.granularityEnabled = true
        xAxis.valueFormatter = IndexAxisValueFormatter(values: labels)
        xAxis.setLabelCount(min(6, labels.count), force: false)

        let yAxis = chartView.leftAxis
        yAxis.axisMinimum = 0
        yAxis.axisMaximum = Double(expectedPerDay)
        yAxis.granularity = 24
        yAxis.granularityEnabled = true
        yAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
            String(format: "%.0f st", value)
        }

        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.5)
        xAxis.gridColor = gridLineColor
        xAxis.gridLineWidth = 0.5
        xAxis.gridLineDashLengths = [2, 2]

        yAxis.gridColor = gridLineColor
        yAxis.gridLineWidth = 0.5
        yAxis.gridLineDashLengths = [2, 2]

        chartView.rightAxis.enabled = false
        chartView.setNeedsDisplay()
    }

    private func valueText(for row: StatRow) -> String {
        guard !selectedValues.isEmpty else { return "–" }

        switch row {
        case .today:
            let todayString = dayFormatter.string(from: Date())
            let todayCount = Storage.shared.bluetoothPingCurrentDate.value == todayString
                ? Storage.shared.bluetoothPingCurrentCount.value
                : 0
            let expected = expectedHeartbeats(for: Date())
            return countExpectedPercentText(count: todayCount, expected: expected)

        case .average:
            let activeValues = selectedValues.filter { $0.count > 0 }
            guard !activeValues.isEmpty else { return "–" }

            let totalCount = activeValues.reduce(0) { $0 + $1.count }
            let totalExpected = activeValues.reduce(0) { $0 + expectedHeartbeats(for: $1.date) }
            let dayCount = activeValues.count

            let averageCount = Int((Double(totalCount) / Double(dayCount)).rounded())
            let averageExpected = Int((Double(totalExpected) / Double(dayCount)).rounded())
            return countExpectedPercentText(count: averageCount, expected: averageExpected)

        case .bestDay:
            let activeValues = selectedValues.filter { $0.count > 0 }
            guard let best = activeValues.max(by: { successRatio(for: $0) < successRatio(for: $1) }) else { return "–" }
            return dayValueText(best)

        case .worstDay:
            let activeValues = selectedValues.filter { $0.count > 0 }
            guard let worst = activeValues.min(by: { successRatio(for: $0) < successRatio(for: $1) }) else { return "–" }
            return dayValueText(worst)
        }
    }

    private func expectedHeartbeats(for date: Date) -> Int {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())

        guard calendar.isDate(day, inSameDayAs: today) else {
            return expectedPerDay
        }

        let elapsedSeconds = max(0, Date().timeIntervalSince(today))
        let expectedSoFar = Int(elapsedSeconds / 300.0)
        return min(expectedPerDay, max(0, expectedSoFar))
    }

    private func successRatio(for value: DayValue) -> Double {
        let expected = expectedHeartbeats(for: value.date)
        guard expected > 0 else { return 0 }
        return Double(value.count) / Double(expected)
    }

    private func percentText(count: Int, expected: Int) -> String {
        guard expected > 0 else { return "0%" }
        let percent = (Double(count) / Double(expected)) * 100.0
        return String(format: "%.0f%%", percent)
    }

    private func countExpectedPercentText(count: Int, expected: Int) -> String {
        return "\(count) av \(expected) (\(percentText(count: count, expected: expected)))"
    }

    private func dayValueText(_ value: DayValue) -> String {
        let expected = expectedHeartbeats(for: value.date)
        return "\(value.dateString)  \(value.count) st (\(percentText(count: value.count, expected: expected)))"
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return StatRow.allCases.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "HeartbeatStatCell")
        cell.selectionStyle = .none

        // Match TrioRestartsStatsViewController: transparent cell with a subtle
        // rounded grouped-section background so the statistics table is framed.
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.backgroundView = nil
        if #available(iOS 14.0, *) {
            var bg = UIBackgroundConfiguration.clear()
            bg.backgroundColor = .systemGray.withAlphaComponent(0.15)
            cell.backgroundConfiguration = bg
        }
        cell.textLabel?.backgroundColor = .clear
        cell.detailTextLabel?.backgroundColor = .clear
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.font = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)

        let row = StatRow.allCases[indexPath.row]
        cell.textLabel?.text = row.label
        cell.detailTextLabel?.text = valueText(for: row)

        return cell
    }
}
private struct LogViewChart: View {
    let title: String
    let allLogEntries: [LogEntry]
    struct Series: Identifiable {
        let id: Int
        let label: String
        let color: Color
        let entries: [LogEntry]
    }
    let series: [Series]

    @Environment(\.dismiss) private var dismiss

    struct ChartPoint: Identifiable {
        let id: Int
        let seriesId: Int
        let date: Date
        let minuteOfHour: Double
    }

    private var pointsBySeries: [(series: Series, points: [ChartPoint])] {
        let now = Date()
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)

        // Datumformatter för loggens prefix: [HH:mm:ss]
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "sv_SE")
        timeFormatter.dateFormat = "HH:mm:ss"

        let todayStart = dayStart

        func parseDate(from line: String) -> Date? {
            // Förväntat format: "[21:34:12] ..."
            guard let firstOpen = line.firstIndex(of: "["),
                  let firstClose = line[firstOpen...].firstIndex(of: "]") else {
                return nil
            }

            let timeString = String(line[line.index(after: firstOpen)..<firstClose])
            guard let timeOnly = timeFormatter.date(from: timeString) else {
                return nil
            }

            // Kombinera tid med dagens datum
            let comps = calendar.dateComponents([.hour, .minute, .second], from: timeOnly)
            guard var combined = calendar.date(byAdding: comps, to: todayStart) else {
                return nil
            }

            // Begränsa till innevarande dygn: 00:00 -> 00:00 nästa dygn
            guard combined >= dayStart && combined < nextDayStart else {
                return nil
            }

            return combined
        }

        return series.map { s in
            let pts: [ChartPoint] = s.entries.compactMap { entry in
                guard let d = parseDate(from: entry.text) else { return nil }
                let minute = Double(calendar.component(.minute, from: d))
                return ChartPoint(id: entry.id, seriesId: s.id, date: d, minuteOfHour: minute)
            }
            .sorted(by: { $0.date < $1.date })

            return (series: s, points: pts)
        }
    }

    // MARK: - Specialare: BLE Ping success-rate (oavsett blå/gul/röd-filter)

    private struct StatRow: Identifiable {
        let id: String
        let label: String
        let value: String
    }

    private func parseTimeToday(from line: String, calendar: Calendar, todayStart: Date, dayStart: Date, nextDayStart: Date, timeFormatter: DateFormatter) -> Date? {
        // Förväntat format: "[21:34:12] ..."
        guard let firstOpen = line.firstIndex(of: "["),
              let firstClose = line[firstOpen...].firstIndex(of: "]") else {
            return nil
        }

        let timeString = String(line[line.index(after: firstOpen)..<firstClose])
        guard let timeOnly = timeFormatter.date(from: timeString) else {
            return nil
        }

        // Kombinera tid med dagens datum
        let comps = calendar.dateComponents([.hour, .minute, .second], from: timeOnly)
        guard let combined = calendar.date(byAdding: comps, to: todayStart) else {
            return nil
        }

        // Begränsa till innevarande dygn: 00:00 -> 00:00 nästa dygn
        guard combined >= dayStart && combined < nextDayStart else {
            return nil
        }

        return combined
    }

    private var specialStatsRows: [StatRow] {
        let now = Date()
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)

        // Datumformatter för loggens prefix: [HH:mm:ss]
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "sv_SE")
        timeFormatter.dateFormat = "HH:mm:ss"

        let todayStart = dayStart

        // 1) BLE Ping lyckades: räkna faktiska loggar med "Bluetooth ping received" inom dagens intervall
        let pingNeedle = "Bluetooth ping received"

        let pingActual = allLogEntries.reduce(into: 0) { acc, entry in
            guard entry.text.localizedCaseInsensitiveContains(pingNeedle) else { return }
            guard let d = parseTimeToday(from: entry.text,
                                         calendar: calendar,
                                         todayStart: todayStart,
                                         dayStart: dayStart,
                                         nextDayStart: nextDayStart,
                                         timeFormatter: timeFormatter) else { return }
            // Fram till NU
            guard d <= now else { return }
            acc += 1
        }

        // 2) Förväntade: 1 per 5-minutersfönster från midnatt till NU
        let elapsed = max(0, now.timeIntervalSince(dayStart))
        let expected = max(1, Int(elapsed / 300.0) )//+ 1)

        let percent: Double = expected > 0 ? (Double(pingActual) / Double(expected)) * 100.0 : 0
        let percentString = String(format: "%.0f%%", percent)

        let pingValue = "\(pingActual)/\(expected) (\(percentString))"

        // 3) Antal omstarter: räkna loggar med "App started" idag
        let restartNeedle = "App started"
        let restartCount = allLogEntries.reduce(into: 0) { acc, entry in
            guard entry.text.localizedCaseInsensitiveContains(restartNeedle) else { return }
            guard let d = parseTimeToday(from: entry.text,
                                         calendar: calendar,
                                         todayStart: todayStart,
                                         dayStart: dayStart,
                                         nextDayStart: nextDayStart,
                                         timeFormatter: timeFormatter) else { return }
            guard d <= now else { return }
            acc += 1
        }

        let restartValue = "\(restartCount) st"
        
        // 4) Antal errors: räkna loggar med "error" och/eller "failed" idag
        let errorNeedle1 = "error"
        let errorNeedle2 = "failed"
        let errorCount = allLogEntries.reduce(into: 0) { acc, entry in
            let text = entry.text
            guard text.localizedCaseInsensitiveContains(errorNeedle1)
                    || text.localizedCaseInsensitiveContains(errorNeedle2) else { return }
            guard let d = parseTimeToday(from: text,
                                         calendar: calendar,
                                         todayStart: todayStart,
                                         dayStart: dayStart,
                                         nextDayStart: nextDayStart,
                                         timeFormatter: timeFormatter) else { return }
            guard d <= now else { return }
            acc += 1
        }

        let errorValue = "\(errorCount) st"

        return [
            StatRow(id: "ble_ping", label: "BLE ping lyckades:", value: pingValue),
            StatRow(id: "app_restarts", label: "Antal omstarter app:", value: restartValue),
            StatRow(id: "errors", label: "Antal errors & failed:", value: errorValue)
        ]
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                ZStack {
                    ThemeBackground()
                        .ignoresSafeArea()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        let anyPoints = pointsBySeries.contains(where: { !$0.points.isEmpty })
                        
                        if !anyPoints {
                            Text("Inga matchande loggrader att plotta.")
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        } else {
                            ScatterLogChartView(series: pointsBySeries)
                                .frame(maxWidth: .infinity)
                                .frame(height: 480)
                                .padding(.horizontal)
                            HStack{
                                Spacer()
                                Text("Y-axel: minut i timmen (0–60)   •   X-axel: 00:00 → 24:00 (idag)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 8)
                                    .padding(.bottom, 20)
                                Spacer()
                            }
                            Text("Systemstatus idag")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            // Tabell med special-statistik
                            VStack(spacing: 4) {
                                ForEach(specialStatsRows) { row in
                                    HStack {
                                        Text(row.label)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        Text(row.value)
                                            .font(.body)
                                            .monospacedDigit()
                                            .foregroundColor(.primary)
                                            .frame(alignment: .trailing)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .background(Color.clear)
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Klar") {
                            dismiss()
                        }
                    }
                }
            }
        } else {
            // Fallback on earlier versions
        }
    }
}

@available(iOS 16.0, *)
private struct ScatterLogChartView: UIViewRepresentable {
    let series: [(series: LogViewChart.Series, points: [LogViewChart.ChartPoint])]

    func makeUIView(context: Context) -> ScatterChartView {
        let chartView = ScatterChartView()
        chartView.backgroundColor = .clear
        chartView.isOpaque = false

        chartView.legend.enabled = true
        chartView.legend.verticalAlignment = .bottom
        chartView.legend.horizontalAlignment = .center
        chartView.legend.orientation = .horizontal
        chartView.legend.drawInside = false
        chartView.chartDescription.enabled = false

        chartView.dragEnabled = true
        chartView.setScaleEnabled(true)
        chartView.pinchZoomEnabled = true
        chartView.highlightPerTapEnabled = false
        chartView.highlightPerDragEnabled = false
        
        chartView.drawGridBackgroundEnabled = true
        chartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)

        // Axlar
        chartView.rightAxis.enabled = false
        chartView.leftAxis.axisMinimum = 0
        chartView.leftAxis.axisMaximum = 60

        // Vi kör 5-minutersgrid (dashad) för att få stabil rendering i Charts.
        // Labels: 0, 5, 10, ... 60
        chartView.leftAxis.granularity = 5
        chartView.leftAxis.granularityEnabled = true
        chartView.leftAxis.setLabelCount(13, force: true) // 0...60 i 5-min-steg
        chartView.leftAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
            let v = Int(value.rounded())
            return String(format: "%d", v)
        }
        chartView.leftAxis.drawZeroLineEnabled = true

        // Grid styling
        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.5)
        chartView.leftAxis.gridColor = gridLineColor
        chartView.leftAxis.gridLineWidth = 0.5
        chartView.leftAxis.gridLineDashLengths = [2, 2]

        chartView.xAxis.labelPosition = .bottom

        // Vi vill ha "mindre" (dashed) grid för varje hel timme, men endast visa etiketter var 3:e timme.
        chartView.xAxis.granularityEnabled = true
        chartView.xAxis.granularity = 60 * 60 // 1 timme
        chartView.xAxis.setLabelCount(25, force: true) // 00..24

        // Grid styling
        chartView.xAxis.gridColor = gridLineColor
        chartView.xAxis.gridLineWidth = 0.5
        chartView.xAxis.gridLineDashLengths = [2, 2]

        // Extra bottenmarginal för att separera x-axel och legend visuellt
        chartView.extraBottomOffset = 6

        return chartView
    }

    func updateUIView(_ uiView: ScatterChartView, context: Context) {
        guard series.contains(where: { !$0.points.isEmpty }) else {
            uiView.data = nil
            return
        }

        let end = Date()

        // Viktigt: ordna serierna så att de ritas i rätt "lager" (0 underst, 1 mitten, 2 överst)
        let orderedSeries = series.sorted(by: { $0.series.id < $1.series.id })

        let dataSets: [ScatterChartDataSet] = orderedSeries.compactMap { s in
            guard !s.points.isEmpty else { return nil }

            let entries: [ChartDataEntry] = s.points.map { p in
                ChartDataEntry(x: p.date.timeIntervalSince1970, y: p.minuteOfHour)
            }

            let ds = ScatterChartDataSet(entries: entries, label: s.series.label)

            // Unika shapes + storlekar per filter
            switch s.series.id {
            case 0:
                // Blå: större cirkel (underst)
                ds.setScatterShape(.circle)
                ds.scatterShapeSize = 9
            case 1:
                // Yellow: triangel (mitten)
                ds.setScatterShape(.triangle)
                ds.scatterShapeSize = 8
            case 2:
                // Röd: cross (överst)
                ds.setScatterShape(.x)
                ds.scatterShapeSize = 7
            default:
                ds.setScatterShape(.circle)
                ds.scatterShapeSize = 7
            }

            ds.setColor(UIColor(s.series.color))
            ds.drawValuesEnabled = false
            return ds
        }

        uiView.data = ScatterChartData(dataSets: dataSets)

        // X-skala: innevarande dygn (00:00 -> 00:00 nästa dygn)
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: end)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)
        uiView.xAxis.axisMinimum = dayStart.timeIntervalSince1970
        uiView.xAxis.axisMaximum = nextDayStart.timeIntervalSince1970
        uiView.xAxis.setLabelCount(25, force: true)

        // Datumformatter på x-axeln
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "HH"
        uiView.xAxis.valueFormatter = EpochTimeAxisValueFormatter(dateFormatter: formatter, showOnlyEveryNthHour: 3)

        uiView.backgroundColor = .clear
        uiView.isOpaque = false
        // Säkerställ 5-minutersgrid även efter uppdatering/layout
        uiView.leftAxis.axisMinimum = 0
        uiView.leftAxis.axisMaximum = 60
        uiView.leftAxis.granularity = 5
        uiView.leftAxis.granularityEnabled = true
        uiView.leftAxis.setLabelCount(13, force: true)
        uiView.notifyDataSetChanged()
    }
}

private final class EpochTimeAxisValueFormatter: AxisValueFormatter {
    private let dateFormatter: DateFormatter
    private let showOnlyEveryNthHour: Int
    private let calendar: Calendar

    init(dateFormatter: DateFormatter, showOnlyEveryNthHour: Int = 3, calendar: Calendar = .current) {
        self.dateFormatter = dateFormatter
        self.showOnlyEveryNthHour = max(1, showOnlyEveryNthHour)
        self.calendar = calendar
    }

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        // Om axis saknas, fall tillbaka till formatter.
        guard let axis = axis else {
            let date = Date(timeIntervalSince1970: value)
            return dateFormatter.string(from: date)
        }

        // Om detta är sista tick-marken (00:00 nästa dygn), visa "24" istället för "00"
        if abs(value - axis.axisMaximum) < 1 {
            return "24"
        }

        let date = Date(timeIntervalSince1970: value)
        let hour = calendar.component(.hour, from: date)

        // Visa endast etiketter var N:e timme
        guard hour % showOnlyEveryNthHour == 0 else { return "" }
        return dateFormatter.string(from: date)
    }
}
