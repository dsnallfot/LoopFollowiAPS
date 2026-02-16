//
//  AlarmStatsViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2026-02-15.
//

import UIKit
import Charts

final class AlarmStatsViewController: ThemedViewController {
    
    /// Called when the view controller is dismissed, so the caller can refresh its UI
    var onDismiss: (() -> Void)?

    // MARK: - UI

    private let rangeControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["7", "14", "30", "90"])
        sc.selectedSegmentIndex = 0
        return sc
    }()
    
    private let alarmFilterControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Glukoslarm", "Övriga larm", "Alla larm"])
        sc.selectedSegmentIndex = 0 // default: Glukoslarm
        return sc
    }()

    private let chartModeControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Antal", "Natt 22-06", "Tid"])
        sc.selectedSegmentIndex = 0
        return sc
    }()

    private let barChartView = BarChartView()
    private let nightLineChartView = LineChartView()
    private let scatterChartView = ScatterChartView()

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var tableHeightConstraint: NSLayoutConstraint?

    private struct StatRow {
        let title: String
        let value: String
    }

    private var statRows: [StatRow] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Alarmhistorik"
        updateBackgroundForCurrentMode()
        configureDoneButton()

        rangeControl.addTarget(self, action: #selector(didChangeControls), for: .valueChanged)
        alarmFilterControl.addTarget(self, action: #selector(didChangeControls), for: .valueChanged)
        chartModeControl.addTarget(self, action: #selector(didChangeControls), for: .valueChanged)

        setupUI()
        setupCharts()
        reloadAll()
    }
    
    private func configureDoneButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )
    }
    
    @objc private func doneTapped() {
        // Inform caller so it can refresh its UI (e.g. ModernAlarmViewController)
        onDismiss?()
        dismiss(animated: true, completion: nil)
    }

    @objc private func didChangeControls() {
        reloadAll()
    }

    // MARK: - UI setup

    private func setupUI() {
        let controlsStack = UIStackView(arrangedSubviews: [rangeControl, alarmFilterControl, chartModeControl])
        controlsStack.axis = .vertical
        controlsStack.spacing = 10

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true

        // Charts
        barChartView.translatesAutoresizingMaskIntoConstraints = false
        nightLineChartView.translatesAutoresizingMaskIntoConstraints = false
        scatterChartView.translatesAutoresizingMaskIntoConstraints = false

        // Table
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.isScrollEnabled = false
        tableView.backgroundColor = .clear
        tableView.backgroundView = tableView.backgroundView
        tableView.isOpaque = false
        tableView.layer.backgroundColor = UIColor.clear.cgColor
        tableView.tableFooterView = UIView(frame: .zero)

        // Add hierarchy
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(controlsStack)
        contentStack.addArrangedSubview(barChartView)
        contentStack.addArrangedSubview(nightLineChartView)
        contentStack.addArrangedSubview(scatterChartView)
        contentStack.addArrangedSubview(tableView)

        // Constrain scroll view to safe area
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Constrain content stack inside scroll view
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),

            // Important: lock stack width to scroll view frame width so it doesn't horizontally scroll
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -24)
        ])

        // Fixed chart heights
        NSLayoutConstraint.activate([
            barChartView.heightAnchor.constraint(equalToConstant: 260),
            nightLineChartView.heightAnchor.constraint(equalToConstant: 260),
            scatterChartView.heightAnchor.constraint(equalToConstant: 260)
        ])

        // Dynamic table height (updated after reload)
        tableHeightConstraint = tableView.heightAnchor.constraint(equalToConstant: 10)
        tableHeightConstraint?.isActive = true

        updateVisibleChart()
    }

    private func updateVisibleChart() {
        let idx = chartModeControl.selectedSegmentIndex
        let showTotal = (idx == 0)
        let showNight = (idx == 1)
        let showTime = (idx == 2)

        barChartView.isHidden = !showTotal
        nightLineChartView.isHidden = !showNight
        scatterChartView.isHidden = !showTime
    }

    // MARK: - Charts

    private func setupCharts() {
        // Bar chart (counts/day)
        barChartView.chartDescription.enabled = false
        barChartView.legend.enabled = false
        barChartView.rightAxis.enabled = false
        barChartView.dragEnabled = false
        barChartView.pinchZoomEnabled = false
        barChartView.doubleTapToZoomEnabled = false
        barChartView.scaleXEnabled = false
        barChartView.scaleYEnabled = false
        barChartView.highlightPerTapEnabled = false


        // Needed for gridBackgroundColor to actually render
        barChartView.drawGridBackgroundEnabled = true
        barChartView.backgroundColor = .clear
        barChartView.drawBordersEnabled = false

        barChartView.xAxis.labelPosition = .bottom
        barChartView.xAxis.drawGridLinesEnabled = true
        barChartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)
        barChartView.xAxis.granularity = 1
        
        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.5)
        barChartView.xAxis.gridColor = gridLineColor
        barChartView.xAxis.gridLineWidth = 0.5
        barChartView.xAxis.gridLineDashLengths = [2, 2]

        barChartView.leftAxis.axisMinimum = 0
        barChartView.leftAxis.drawGridLinesEnabled = true
        
        barChartView.leftAxis.gridColor = gridLineColor
        barChartView.leftAxis.gridLineWidth = 0.5
        barChartView.leftAxis.gridLineDashLengths = [2, 2]


        // Night line chart (night alarms per day)
        nightLineChartView.chartDescription.enabled = false
        nightLineChartView.legend.enabled = false
        nightLineChartView.rightAxis.enabled = false
        nightLineChartView.dragEnabled = false
        nightLineChartView.pinchZoomEnabled = false
        nightLineChartView.doubleTapToZoomEnabled = false
        nightLineChartView.scaleXEnabled = false
        nightLineChartView.scaleYEnabled = false
        nightLineChartView.highlightPerTapEnabled = false

        // Needed for gridBackgroundColor to actually render
        nightLineChartView.drawGridBackgroundEnabled = true
        nightLineChartView.backgroundColor = .clear
        nightLineChartView.drawBordersEnabled = false

        nightLineChartView.xAxis.labelPosition = .bottom
        nightLineChartView.xAxis.drawGridLinesEnabled = true
        nightLineChartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)
        nightLineChartView.xAxis.granularity = 1

        nightLineChartView.xAxis.gridColor = gridLineColor
        nightLineChartView.xAxis.gridLineWidth = 0.5
        nightLineChartView.xAxis.gridLineDashLengths = [2, 2]

        nightLineChartView.leftAxis.axisMinimum = 0
        nightLineChartView.leftAxis.drawGridLinesEnabled = true
        nightLineChartView.leftAxis.gridColor = gridLineColor
        nightLineChartView.leftAxis.gridLineWidth = 0.5
        nightLineChartView.leftAxis.gridLineDashLengths = [2, 2]

        // Scatter chart (time-of-day)
        scatterChartView.chartDescription.enabled = false
        scatterChartView.legend.enabled = true
        scatterChartView.rightAxis.enabled = false
        scatterChartView.dragEnabled = false
        scatterChartView.pinchZoomEnabled = false
        scatterChartView.doubleTapToZoomEnabled = false
        scatterChartView.scaleXEnabled = false
        scatterChartView.scaleYEnabled = false
        scatterChartView.highlightPerTapEnabled = false

        // Needed for gridBackgroundColor to actually render
        scatterChartView.drawGridBackgroundEnabled = true
        scatterChartView.backgroundColor = .clear
        scatterChartView.drawBordersEnabled = false

        scatterChartView.xAxis.labelPosition = .bottom
        scatterChartView.xAxis.drawGridLinesEnabled = true
        scatterChartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)
        scatterChartView.xAxis.granularity = 1
        
        scatterChartView.xAxis.gridColor = gridLineColor
        scatterChartView.xAxis.gridLineWidth = 0.5
        scatterChartView.xAxis.gridLineDashLengths = [2, 2]

        scatterChartView.leftAxis.axisMinimum = 0
        scatterChartView.leftAxis.axisMaximum = 24
        scatterChartView.leftAxis.drawGridLinesEnabled = true
        
        
        // Dashad grid för varje timme, men endast labels vid 00/06/12/18/24
        scatterChartView.leftAxis.granularity = 1
        scatterChartView.leftAxis.granularityEnabled = true
        scatterChartView.leftAxis.setLabelCount(25, force: false)
        scatterChartView.leftAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
            let v = Int(value.rounded())
            guard [0, 6, 12, 18, 24].contains(v) else { return "" }
            return String(format: "%02d:00", v)
        }
        
        scatterChartView.leftAxis.gridColor = gridLineColor
        scatterChartView.leftAxis.gridLineWidth = 0.5
        scatterChartView.leftAxis.gridLineDashLengths = [2, 2]

        // Rensa tidigare limit-lines
        scatterChartView.leftAxis.removeAllLimitLines()

        // Solida huvudlinjer vid 00/06/12/18/24
        let majorLineColor = UIColor.lightGray.withAlphaComponent(0.65)
        for hour in [0.0, 6.0, 12.0, 18.0, 24.0] {
            let ll = ChartLimitLine(limit: hour)
            ll.lineWidth = 0.8
            ll.lineColor = majorLineColor
            ll.lineDashLengths = []
            ll.label = ""
            scatterChartView.leftAxis.addLimitLine(ll)
        }
    }

    // MARK: - Data

    private func selectedDays() -> Int {
        switch rangeControl.selectedSegmentIndex {
        case 0: return 7
        case 1: return 14
        case 2: return 30
        default: return 90
        }
    }

    private func reloadAll() {
        updateVisibleChart()

        let days = selectedDays()
        let now = Date()
        let calendar = Calendar.current

        let startOfToday = calendar.startOfDay(for: now)
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) else { return }

        let raw = Storage.shared.alarmHistory
        let windowStart = startDate.timeIntervalSince1970
        let windowEnd = now.timeIntervalSince1970

        let alarmsInWindow = raw
            .filter { $0.date >= windowStart && $0.date <= windowEnd }
            .sorted { $0.date < $1.date }

        let group = selectedAlarmGroup()

        var counts: [Int] = Array(repeating: 0, count: days)
        var nightCounts: [Int] = Array(repeating: 0, count: days)

        // Scatter: tre serier
        var lowEntries: [ChartDataEntry] = []
        var highEntries: [ChartDataEntry] = []
        var otherEntries: [ChartDataEntry] = []

        // Per alarm-kind
        var perKind: [AlarmKind: Int] = [:]
        AlarmKind.allCases.forEach { perKind[$0] = 0 }

        for alarm in alarmsInWindow {
            let alarmDate = Date(timeIntervalSince1970: alarm.date)
            let dayIndex = calendar.dateComponents([.day], from: startDate, to: calendar.startOfDay(for: alarmDate)).day ?? 0
            guard dayIndex >= 0 && dayIndex < days else { continue }

            let kind = AlarmKind.from(alarmLabel: alarm.alarmLabel)

            if let kind { perKind[kind, default: 0] += 1 }

            // Bar = filtrerad grupp
            let includeInGroup: Bool = {
                if let kind { return groupAllows(kind, group: group) }
                return group == .all
            }()

            if includeInGroup {
                counts[dayIndex] += 1
            }

            // Scatter time-of-day
            let comps = calendar.dateComponents([.hour, .minute], from: alarmDate)
            let hour = comps.hour ?? 0
            let timeOfDay = Double(hour) + Double(comps.minute ?? 0) / 60.0

            // Night count (22:00–06:00) uses the same group filter, but additionally filters by hour
            if includeInGroup {
                if hour >= 22 || hour < 6 {
                    nightCounts[dayIndex] += 1
                }
            }

            if let kind {
                if kind.isGlucose {
                    if group == .glucose || group == .all {
                        if kind.isLowGlucose {
                            lowEntries.append(ChartDataEntry(x: Double(dayIndex), y: timeOfDay))
                        } else if kind.isHighGlucose {
                            highEntries.append(ChartDataEntry(x: Double(dayIndex), y: timeOfDay))
                        } else {
                            // safety fallback
                            otherEntries.append(ChartDataEntry(x: Double(dayIndex), y: timeOfDay))
                        }
                    }
                } else {
                    if group == .other || group == .all {
                        otherEntries.append(ChartDataEntry(x: Double(dayIndex), y: timeOfDay))
                    }
                }
            } else {
                // okänd label: visa bara när group == .all
                if group == .all {
                    otherEntries.append(ChartDataEntry(x: Double(dayIndex), y: timeOfDay))
                }
            }
        }

        // Charts
        updateBarChart(counts: counts, startDate: startDate, days: days)
        updateNightLineChart(counts: nightCounts, startDate: startDate, days: days)
        updateScatterChart(lowEntries: lowEntries, highEntries: highEntries, otherEntries: otherEntries, startDate: startDate, days: days)

        // Stats ska matcha gruppen (annars blir totalsiffrorna förvirrande)
        let filteredForStats: [AlarmHistoryEntry] = alarmsInWindow.filter { alarm in
            let kind = AlarmKind.from(alarmLabel: alarm.alarmLabel)
            if let kind { return groupAllows(kind, group: group) }
            return group == .all
        }
        statRows = buildStats(days: days, startDate: startDate, now: now, alarms: filteredForStats, counts: counts)

        // Section 2: alltid lista alla 17 cases
        alarmCaseRows = AlarmKind.allCases.map { AlarmCaseRow(title: $0.title, count: perKind[$0, default: 0]) }

        tableView.reloadData()

        // Update intrinsic height so the surrounding scroll view can scroll the whole screen
        tableView.layoutIfNeeded()
        tableHeightConstraint?.constant = tableView.contentSize.height
    }

    private func updateBarChart(counts: [Int], startDate: Date, days: Int) {
        var entries: [BarChartDataEntry] = []
        entries.reserveCapacity(counts.count)

        for (i, c) in counts.enumerated() {
            entries.append(BarChartDataEntry(x: Double(i), y: Double(c)))
        }

        let set = BarChartDataSet(entries: entries)
        set.drawValuesEnabled = false
        set.setColor(.systemGray)
        set.barBorderColor = .label
        set.barBorderWidth = 0.5

        let data = BarChartData(dataSet: set)
        data.barWidth = 0.8
        barChartView.data = data

        barChartView.xAxis.valueFormatter = AlarmDateAxisFormatter(startDate: startDate)
        barChartView.xAxis.labelCount = min(days, 7)

        barChartView.notifyDataSetChanged()
        barChartView.setNeedsDisplay()
    }

    private func updateScatterChart(
        lowEntries: [ChartDataEntry],
        highEntries: [ChartDataEntry],
        otherEntries: [ChartDataEntry],
        startDate: Date,
        days: Int
    ) {
        let lowSet = ScatterChartDataSet(entries: lowEntries, label: "Låga larm")
        lowSet.drawValuesEnabled = false
        lowSet.setScatterShape(.circle)
        lowSet.setColor(.systemRed.withAlphaComponent(0.8))
        lowSet.scatterShapeSize = 5

        let highSet = ScatterChartDataSet(entries: highEntries, label: "Höga larm")
        highSet.drawValuesEnabled = false
        highSet.setScatterShape(.circle)
        highSet.setColor(.systemBlue.withAlphaComponent(0.8))
        highSet.scatterShapeSize = 5

        let otherSet = ScatterChartDataSet(entries: otherEntries, label: "Övriga larm")
        otherSet.drawValuesEnabled = false
        otherSet.setScatterShape(.circle)
        otherSet.setColor(.systemGray.withAlphaComponent(0.8))
        otherSet.scatterShapeSize = 5

        scatterChartView.data = ScatterChartData(dataSets: [lowSet, highSet, otherSet])

        // Legend
        scatterChartView.legend.enabled = true
        scatterChartView.legend.verticalAlignment = .top
        scatterChartView.legend.horizontalAlignment = .right
        scatterChartView.legend.orientation = .vertical
        scatterChartView.legend.drawInside = true

        scatterChartView.xAxis.valueFormatter = AlarmDateAxisFormatter(startDate: startDate)
        scatterChartView.xAxis.labelCount = min(days, 7)

        scatterChartView.notifyDataSetChanged()
        scatterChartView.setNeedsDisplay()
    }
    
    private func updateNightLineChart(counts: [Int], startDate: Date, days: Int) {
        var entries: [ChartDataEntry] = []
        entries.reserveCapacity(counts.count)

        var circleColors: [NSUIColor] = []
        circleColors.reserveCapacity(counts.count)

        var maxY: Double = 0

        for (i, c) in counts.enumerated() {
            let y = Double(c)
            if y > maxY { maxY = y }
            entries.append(ChartDataEntry(x: Double(i), y: y))

            // Color rules:
            // < 1 => green, 1..<3 => orange, >= 3 => red
            if c < 1 {
                circleColors.append(NSUIColor.systemGreen)
            } else if c < 3 {
                circleColors.append(NSUIColor.systemOrange)
            } else {
                circleColors.append(NSUIColor.systemRed)
            }
        }

        let set = LineChartDataSet(entries: entries, label: "")
        set.drawValuesEnabled = false
        set.drawCirclesEnabled = true
        set.circleRadius = 5
        set.circleHoleRadius = 0
        set.circleColors = circleColors

        set.lineWidth = 1
        set.setColor(.systemGray)
        set.drawFilledEnabled = false
        set.mode = .linear
        set.highlightEnabled = false

        nightLineChartView.data = LineChartData(dataSet: set)

        nightLineChartView.xAxis.valueFormatter = AlarmDateAxisFormatter(startDate: startDate)
        nightLineChartView.xAxis.labelCount = min(days, 7)

        // Dynamic y-axis like the bar chart
        nightLineChartView.leftAxis.axisMinimum = 0
        let paddedMax = max(3.0, ceil(maxY + 1.0))
        nightLineChartView.leftAxis.axisMaximum = paddedMax
        nightLineChartView.leftAxis.granularity = 1
        nightLineChartView.leftAxis.granularityEnabled = true

        nightLineChartView.notifyDataSetChanged()
        nightLineChartView.setNeedsDisplay()
    }

    private func buildStats(days: Int, startDate: Date, now: Date, alarms: [AlarmHistoryEntry], counts: [Int]) -> [StatRow] {
        let total = alarms.count
        let avgPerDay = days > 0 ? Double(total) / Double(days) : 0
        let maxSameDay = counts.max() ?? 0

        // Night alarms between 22:00–06:00
        let calendar = Calendar.current
        var nightTotal = 0
        for a in alarms {
            let d = Date(timeIntervalSince1970: a.date)
            let h = calendar.component(.hour, from: d)
            if h >= 22 || h < 6 { nightTotal += 1 }
        }
        let avgNightPerDay = days > 0 ? Double(nightTotal) / Double(days) : 0

        // Longest streak without alarms (hours) within selected window
        let windowStart = startDate.timeIntervalSince1970
        let windowEnd = now.timeIntervalSince1970

        var last = windowStart
        var longest: TimeInterval = 0

        for a in alarms {
            let gap = a.date - last
            if gap > longest { longest = gap }
            last = a.date
        }

        let tail = windowEnd - last
        if tail > longest { longest = tail }

        let longestHours = longest / 3600.0

        func fmt1(_ v: Double) -> String {
            if v.isNaN || v.isInfinite { return "0.0" }
            return String(format: "%.1f", v)
        }

        return [
            StatRow(title: "Triggade larm totalt", value: "\(total) st"),
            StatRow(title: "Medel larm per dag", value: "\(fmt1(avgPerDay)) st"),
            StatRow(title: "Högsta antal larm samma dag", value: "\(maxSameDay) st"),
            StatRow(title: "Medel larm nattid (22–06)", value: "\(fmt1(avgNightPerDay)) st"),
            StatRow(title: "Längsta streak utan larm", value: "\(fmt1(longestHours)) h")
        ]
    }
    
    private struct AlarmCaseRow {
        let title: String
        let count: Int
    }

    private var alarmCaseRows: [AlarmCaseRow] = []

    private enum AlarmGroup: Int {
        case glucose = 0
        case other = 1
        case all = 2
    }

    private enum AlarmKind: String, CaseIterable {
        // Glukoslarm
        case urgentLow, urgentLowSoon, low, high, urgentHigh, fastDrop, fastRise, alertTemporaryBG

        // Övriga larm
        case missedReading, notLooping, battery, sage, cage, pump, cob, iob, missedBolus//, recBolus, tempTargetStart, tempTargetEnd

        var title: String {
            switch self {
            case .urgentLow: return "🆘 Akut lågt!"
            case .urgentLowSoon: return "⚠️ Snart akut låg!"
            case .low: return "🔴 Lågt socker"
            case .high: return "🟣 Högt socker"
            case .urgentHigh: return "⚠️ Akut högt!"
            case .fastDrop: return "⏬ Sjunker snabbt"
            case .fastRise: return "⏫ Stiger snabbt"
            case .alertTemporaryBG: return "⚠️ Tillfällig varning"

            case .missedReading: return "⚠️ Inga värden"
            case .notLooping: return "❌ Loop ej aktiv!"
            case .battery: return "🪫 Låg batterinivå"
            case .sage: return "⏰ Påminnelse sensorbyte"
            case .cage: return "⏰ Påminnelse pumpbyte"
            case .pump: return "⚠️ Låg insulinnivå"
            case .cob: return "🥨 COB Varning"
            case .iob: return "💉 IOB Varning"
            case .missedBolus: return "⚠️ Missad måltidsbolus"
            //case .recBolus: return "👉 Rek. Bolus"
            //case .tempTargetStart: return "▶️ Temp Target Start"
            //case .tempTargetEnd: return "⏹️ Temp Target End"
            }
        }

        var isGlucose: Bool {
            switch self {
            case .urgentLow, .urgentLowSoon, .low, .high, .urgentHigh, .fastDrop, .fastRise, .alertTemporaryBG:
                return true
            default:
                return false
            }
        }

        var isLowGlucose: Bool {
            switch self {
            case .urgentLow, .low, .fastDrop, .urgentLowSoon, .alertTemporaryBG: return true
            default: return false
            }
        }

        var isHighGlucose: Bool {
            switch self {
            case .high, .urgentHigh, .fastRise: return true
            default: return false
            }
        }

        static func from(alarmLabel: String?) -> AlarmKind? {
            guard let alarmLabel, !alarmLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let trimmed = alarmLabel.trimmingCharacters(in: .whitespacesAndNewlines)

            // 1) raw case name, t.ex. "urgentLow"
            if let k = AlarmKind(rawValue: trimmed) { return k }

            // 2) case-insensitive raw match
            let lowered = trimmed.lowercased()
            if let k = AlarmKind.allCases.first(where: { $0.rawValue.lowercased() == lowered }) { return k }

            // 3) matcha title (emoji + svensk text)
            if let k = AlarmKind.allCases.first(where: { $0.title == trimmed }) { return k }

            // 4) loose contains (if label contains extra text)
            if let k = AlarmKind.allCases.first(where: { lowered.contains($0.rawValue.lowercased()) }) { return k }
            if let k = AlarmKind.allCases.first(where: { lowered.contains($0.title.lowercased()) }) { return k }

            return nil
        }
    }

    private func selectedAlarmGroup() -> AlarmGroup {
        AlarmGroup(rawValue: alarmFilterControl.selectedSegmentIndex) ?? .all
    }

    private func groupAllows(_ kind: AlarmKind, group: AlarmGroup) -> Bool {
        switch group {
        case .glucose: return kind.isGlucose
        case .other: return !kind.isGlucose
        case .all: return true
        }
    }
}

extension AlarmStatsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return statRows.count
        default: return alarmCaseRows.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return nil
        default: return "Antal larm per typ"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)

        switch indexPath.section {
        case 0:
            let row = statRows[indexPath.row]
            cell.textLabel?.text = row.title
            cell.detailTextLabel?.text = row.value
        default:
            let row = alarmCaseRows[indexPath.row]
            cell.textLabel?.text = row.title
            cell.detailTextLabel?.text = "\(row.count) ggr"
        }

        cell.selectionStyle = .none
        
        // Transparent cell so the themed gradient shows
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
        return cell
    }
}

private final class AlarmDateAxisFormatter: AxisValueFormatter {
    private let startDate: Date
    private let calendar = Calendar.current
    private let df: DateFormatter = {
        let d = DateFormatter()
        d.dateFormat = "d/M" // e.g. 5/2
        return d
    }()

    init(startDate: Date) {
        self.startDate = startDate
    }

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let i = Int(round(value))
        guard i >= 0 else { return "" }
        guard let d = calendar.date(byAdding: .day, value: i, to: startDate) else { return "" }
        return df.string(from: d)
    }
}
