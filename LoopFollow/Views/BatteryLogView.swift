//
//  BatteryLogView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2026-01-08.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import Foundation
import UIKit
import Charts

// MARK: - Battery Log

struct BatteryEntry {
    let date: Date
    let percent: Double
    let isCharging: Bool
}

/// Simple day-filtered battery log table.
final class BatteryLogViewController: ThemedViewController, UITableViewDataSource, UITableViewDelegate {

    private var entries: [BatteryEntry] = []
    private var selectedDate: Date = Date()

    private let tableView = UITableView(frame: .zero, style: .plain)

    private let datePicker: UIDatePicker = {
        let dp = UIDatePicker()
        dp.datePickerMode = .date
        dp.preferredDatePickerStyle = .compact
        dp.translatesAutoresizingMaskIntoConstraints = false
        dp.locale = Locale(identifier: "sv_SE")
        return dp
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Trio batterilogg"
        updateBackgroundForCurrentMode()

        setupNavigationBar()
        setupTableView()
        setupHeader()
        setupConstraints()

        // Date picker bounds follow cache retention
        let cal = Calendar.current
        if let oldest = cal.date(byAdding: .day, value: -BatteryCache.retentionDays + 1, to: Date()) {
            datePicker.minimumDate = oldest
        }
        datePicker.maximumDate = Date()
        datePicker.date = selectedDate
        datePicker.addTarget(self, action: #selector(dateChanged(_:)), for: .valueChanged)

        loadDay(selectedDate)
    }

    private func setupNavigationBar() {
        let done = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(doneTapped)
        )

        let stats = UIBarButtonItem(
            image: UIImage(systemName: "chart.bar.xaxis.ascending"),
            style: .plain,
            target: self,
            action: #selector(showStats)
        )
        stats.tintColor = .label

        navigationItem.rightBarButtonItems = [done, stats]
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func showStats() {
        let statsVC = BatteryLogStatsViewController()
        let nav = UINavigationController(rootViewController: statsVC)

        nav.modalPresentationStyle = .formSheet
        nav.view.backgroundColor = .clear
        nav.view.isOpaque = false
        nav.view.layer.backgroundColor = UIColor.clear.cgColor

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance

        nav.overrideUserInterfaceStyle = self.traitCollection.userInterfaceStyle
        present(nav, animated: true)
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        tableView.register(Value1TableViewCell.self, forCellReuseIdentifier: "BatteryCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.isOpaque = false
    }

    private func setupHeader() {
        // Simple header: date picker only (day filter)
        view.addSubview(datePicker)
        datePicker.setContentHuggingPriority(.required, for: .horizontal)
        datePicker.setContentCompressionResistancePriority(.required, for: .horizontal)
        datePicker.heightAnchor.constraint(equalToConstant: 30).isActive = true
        datePicker.widthAnchor.constraint(lessThanOrEqualToConstant: 105).isActive = true
    }

    private func setupConstraints() {
        let safe = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            datePicker.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            datePicker.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 8),

            tableView.topAnchor.constraint(equalTo: datePicker.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func dateChanged(_ sender: UIDatePicker) {
        selectedDate = sender.date
        loadDay(selectedDate)
    }

    private func loadDay(_ date: Date) {
        Task {
            let samples = await BatteryCache.loadDay(date)
            let mapped: [BatteryEntry] = samples.map {
                BatteryEntry(date: Date(timeIntervalSince1970: $0.date), percent: $0.percent, isCharging: $0.isCharging)
            }

            await MainActor.run {
                // Newest first
                self.entries = mapped.sorted { $0.date > $1.date }
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(entries.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "BatteryCell", for: indexPath) as? Value1TableViewCell else {
            return UITableViewCell(style: .value1, reuseIdentifier: "BatteryCell")
        }

        if entries.isEmpty {
            cell.textLabel?.text = "Inga batteridata"
            cell.detailTextLabel?.text = ""
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.selectionStyle = .none
            return cell
        }

        let e = entries[indexPath.row]
        let timeStr = timeFormatter.string(from: e.date)
        let charging = e.isCharging ? "⚡" : ""

        cell.textLabel?.text = String(format: "%.0f%% %@", e.percent, charging)
        cell.detailTextLabel?.text = timeStr
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
}

/// Battery stats view with Day / Week visualization.
final class BatteryLogStatsViewController: ThemedViewController, ChartViewDelegate {

    private enum Mode: Int {
        case day = 0
        case week = 1
    }

    private var mode: Mode = .day
    private var selectedDate: Date = Date()

    private let headerStack = UIStackView()

    private let dayLegendLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.numberOfLines = 0
        l.textAlignment = .center
        l.font = UIFont.preferredFont(forTextStyle: .caption1)
        l.textColor = .secondaryLabel
        l.isHidden = false
        return l
    }()

    private let datePicker: UIDatePicker = {
        let dp = UIDatePicker()
        dp.datePickerMode = .date
        dp.preferredDatePickerStyle = .compact
        dp.translatesAutoresizingMaskIntoConstraints = false
        dp.locale = Locale(identifier: "sv_SE")
        return dp
    }()

    private let modeSegment: UISegmentedControl = {
        let s = UISegmentedControl(items: ["Dag", "Vecka"])
        s.selectedSegmentIndex = 0
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let dayChartView: BarChartView = {
        let v = BarChartView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.legend.enabled = false
        v.chartDescription.enabled = false
        v.doubleTapToZoomEnabled = false
        v.pinchZoomEnabled = false
        v.scaleXEnabled = false
        v.scaleYEnabled = false
        v.highlightPerTapEnabled = true
        v.highlightPerDragEnabled = false
        return v
    }()

    private let weekChartView: CandleStickChartView = {
        let v = CandleStickChartView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.legend.enabled = false
        v.chartDescription.enabled = false
        v.doubleTapToZoomEnabled = false
        v.pinchZoomEnabled = false
        v.scaleXEnabled = false
        v.scaleYEnabled = false
        v.highlightPerTapEnabled = true
        v.highlightPerDragEnabled = false
        return v
    }()

    // Formatters
    private let dayXAxisFormatter = DayBatteryXAxisFormatter()
    private let weekXAxisFormatter = WeekBatteryXAxisFormatter()
    private let yAxisFormatter = BatteryYAxisValueFormatter()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Batteristatistik"
        updateBackgroundForCurrentMode()

        setupNavigationBar()
        setupHeader()
        setupCharts()
        setupConstraints()

        // Date picker bounds follow cache retention
        let cal = Calendar.current
        if let oldest = cal.date(byAdding: .day, value: -BatteryCache.retentionDays + 1, to: Date()) {
            datePicker.minimumDate = oldest
        }
        datePicker.maximumDate = Date()
        datePicker.date = selectedDate

        modeSegment.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        datePicker.addTarget(self, action: #selector(dateChanged(_:)), for: .valueChanged)

        applyMode(.day, keepingDate: selectedDate)
    }

    // MARK: - UI setup

    private func setupNavigationBar() {
        let done = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissSelf)
        )

        let prev = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(previousTapped)
        )

        let next = UIBarButtonItem(
            image: UIImage(systemName: "chevron.right"),
            style: .plain,
            target: self,
            action: #selector(nextTapped)
        )

        navigationItem.rightBarButtonItem = done
        navigationItem.leftBarButtonItems = [prev, next]
    }

    private func setupHeader() {
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.distribution = .fill
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerStack)
        headerStack.addArrangedSubview(datePicker)
        headerStack.addArrangedSubview(UIView())
        headerStack.addArrangedSubview(modeSegment)

        // Keep compact sizing similar to other screens
        datePicker.setContentHuggingPriority(.required, for: .horizontal)
        datePicker.setContentCompressionResistancePriority(.required, for: .horizontal)
        modeSegment.setContentHuggingPriority(.required, for: .horizontal)
        modeSegment.setContentCompressionResistancePriority(.required, for: .horizontal)

        datePicker.heightAnchor.constraint(equalToConstant: 30).isActive = true
        datePicker.widthAnchor.constraint(lessThanOrEqualToConstant: 130).isActive = true
    }

    private func setupCharts() {
        view.addSubview(dayChartView)
        view.addSubview(weekChartView)
        view.addSubview(dayLegendLabel)
        updateDayLegendText()

        dayChartView.delegate = self
        weekChartView.delegate = self

        configureYAxis(for: dayChartView.leftAxis, rightAxis: dayChartView.rightAxis)
        configureYAxis(for: weekChartView.leftAxis, rightAxis: weekChartView.rightAxis)

        configureDayXAxis()
        configureWeekXAxis()

        // Initial visibility
        dayChartView.isHidden = false
        weekChartView.isHidden = true

        // Background / grid aesthetics
        dayChartView.backgroundColor = .clear
        weekChartView.backgroundColor = .clear

        // Ensure content isn't clipped at edges
        weekChartView.setExtraOffsets(left: 8, top: 0, right: 8, bottom: 0)
    }

    private func setupConstraints() {
        let safe = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            headerStack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 8),
            headerStack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -8),

            dayChartView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 10),
            dayChartView.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 8),
            dayChartView.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -8),
            dayChartView.heightAnchor.constraint(equalToConstant: 300),
            dayLegendLabel.topAnchor.constraint(equalTo: dayChartView.bottomAnchor, constant: 8),
            dayLegendLabel.leadingAnchor.constraint(equalTo: dayChartView.leadingAnchor, constant: 15),
            dayLegendLabel.trailingAnchor.constraint(equalTo: dayChartView.trailingAnchor),
            dayLegendLabel.bottomAnchor.constraint(lessThanOrEqualTo: safe.bottomAnchor, constant: -8),

            weekChartView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 10),
            weekChartView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),//, constant: 8),
            weekChartView.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -8),
            weekChartView.heightAnchor.constraint(equalToConstant: 300),
            weekChartView.bottomAnchor.constraint(lessThanOrEqualTo: safe.bottomAnchor, constant: -8)
        ])
    }

    // MARK: - Axis configuration

    private func configureYAxis(for leftAxis: YAxis, rightAxis: YAxis) {
        rightAxis.enabled = false

        leftAxis.axisMinimum = 0
        leftAxis.axisMaximum = 100

        // Grid every 10%
        leftAxis.granularityEnabled = true
        leftAxis.granularity = 10

        // Force ticks across the full range (0..100) so 50% reliably appears
        leftAxis.setLabelCount(11, force: true)
        leftAxis.valueFormatter = yAxisFormatter
        leftAxis.drawLabelsEnabled = true

        leftAxis.drawGridLinesEnabled = true
        leftAxis.gridLineDashLengths = [2, 2]
        leftAxis.gridColor = UIColor.label.withAlphaComponent(0.2)

        leftAxis.drawAxisLineEnabled = true
        leftAxis.axisLineColor = UIColor.label.withAlphaComponent(1.0)
        leftAxis.axisLineWidth = 0.5
        leftAxis.labelTextColor = .secondaryLabel
    }

    private func configureDayXAxis() {
        let x = dayChartView.xAxis
        x.labelPosition = .bottom
        x.drawGridLinesEnabled = false
        x.drawAxisLineEnabled = true
        x.axisLineColor = UIColor.label.withAlphaComponent(1.0)
        x.axisLineWidth = 0.5
        x.labelTextColor = .secondaryLabel
        x.granularity = 1
        x.axisMinimum = 0
        x.axisMaximum = 96
        x.setLabelCount(5, force: true)
        x.valueFormatter = dayXAxisFormatter

        dayChartView.leftAxis.spaceTop = 5
        dayChartView.leftAxis.spaceBottom = 0
    }

    private func configureWeekXAxis() {
        let x = weekChartView.xAxis
        x.labelPosition = .bottom
        x.drawGridLinesEnabled = false
        x.drawAxisLineEnabled = true
        x.axisLineColor = UIColor.label.withAlphaComponent(1.0)
        x.axisLineWidth = 0.5
        x.labelTextColor = .secondaryLabel
        x.granularity = 1
        // Add half-step padding so day 0 and day 6 candles are not clipped
        x.axisMinimum = -0.5
        x.axisMaximum = 6.5
        x.setLabelCount(7, force: true)
        x.valueFormatter = weekXAxisFormatter
/*
        // Extra spacing at chart edges (defensive)
        x.spaceMin = 0.5
        x.spaceMax = 0.5
*/
        weekChartView.leftAxis.spaceTop = 5
        weekChartView.leftAxis.spaceBottom = 0
    }

    // MARK: - Actions

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        let newMode: Mode = sender.selectedSegmentIndex == 0 ? .day : .week
        applyMode(newMode, keepingDate: selectedDate)
    }

    @objc private func dateChanged(_ sender: UIDatePicker) {
        selectedDate = sender.date
        if mode == .week {
            // Snap to start-of-week so week navigation behaves consistently
            selectedDate = startOfWeek(for: selectedDate)
            datePicker.date = selectedDate
        }
        reload()
    }

    @objc private func previousTapped() {
        let cal = Calendar.current
        switch mode {
        case .day:
            selectedDate = cal.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = cal.date(byAdding: .day, value: -7, to: selectedDate) ?? selectedDate
            selectedDate = startOfWeek(for: selectedDate)
        }
        datePicker.date = selectedDate
        reload()
    }

    @objc private func nextTapped() {
        let cal = Calendar.current
        let today = Date()
        switch mode {
        case .day:
            selectedDate = cal.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = cal.date(byAdding: .day, value: 7, to: selectedDate) ?? selectedDate
            selectedDate = startOfWeek(for: selectedDate)
        }

        // Prevent navigating into the future
        if selectedDate > today {
            selectedDate = today
            if mode == .week { selectedDate = startOfWeek(for: selectedDate) }
        }

        datePicker.date = selectedDate
        reload()
    }

    // MARK: - Mode

    private func applyMode(_ newMode: Mode, keepingDate date: Date) {
        mode = newMode
        modeSegment.selectedSegmentIndex = newMode.rawValue

        switch newMode {
        case .day:
            dayChartView.isHidden = false
            weekChartView.isHidden = true
            dayLegendLabel.isHidden = false
            selectedDate = date
            datePicker.date = selectedDate

        case .week:
            dayChartView.isHidden = true
            weekChartView.isHidden = false
            dayLegendLabel.isHidden = true
            selectedDate = startOfWeek(for: date)
            datePicker.date = selectedDate
        }

        // Caller decides when to reload (avoids duplicate reloads during tap navigation)
        reload()
    }

    // MARK: - Data loading + chart building

    private func reload() {
        switch mode {
        case .day:
            Task { await buildDayChart(for: selectedDate) }
        case .week:
            Task { await buildWeekChart(startingAt: startOfWeek(for: selectedDate)) }
        }
    }

    private func buildDayChart(for date: Date) async {
        let samples = await BatteryCache.loadDay(date)

        // Sort ascending by time
        let sorted = samples.sorted { $0.date < $1.date }

        // Pick the FIRST sample per 15-minute bucket (local time)
        // Bucket index: 0..95 (each is 15 minutes)
        var firstByQuarter: [Int: BatterySampleJSON] = [:]
        let cal = Calendar.current
        for s in sorted {
            let d = Date(timeIntervalSince1970: s.date)
            let hour = cal.component(.hour, from: d)
            let minute = cal.component(.minute, from: d)
            let quarter = hour * 4 + (minute / 15)
            if quarter >= 0 && quarter < 96, firstByQuarter[quarter] == nil {
                firstByQuarter[quarter] = s
            }
        }

        var entries: [BarChartDataEntry] = []
        var colors: [UIColor] = []

        for q in 0..<96 {
            if let s = firstByQuarter[q] {
                entries.append(BarChartDataEntry(x: Double(q), y: s.percent))
                colors.append(colorForBattery(percent: s.percent, isCharging: s.isCharging))
            } else {
                // No data for this 15-min bucket -> invisible bar (gap)
                entries.append(BarChartDataEntry(x: Double(q), y: 0))
                colors.append(UIColor.clear)
            }
        }

        let set = BarChartDataSet(entries: entries, label: "")
        set.colors = colors
        set.drawValuesEnabled = false
        set.drawValuesEnabled = false
        set.highlightEnabled = true

        let data = BarChartData(dataSet: set)
        data.barWidth = 0.9

        await MainActor.run {
            self.dayChartView.data = data
            self.dayChartView.notifyDataSetChanged()
        }
    }

    private func buildWeekChart(startingAt weekStart: Date) async {
        let cal = Calendar.current
        let start = cal.startOfDay(for: weekStart)
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start

        // Load all samples in the week window (inclusive).
        let endOfLastDay = cal.date(byAdding: .day, value: 1, to: end)!.addingTimeInterval(-1)
        let samples = await BatteryCache.loadWindow(from: start, to: endOfLastDay)

        // Build min/max per day
        var perDay: [[BatterySampleJSON]] = Array(repeating: [], count: 7)
        for s in samples {
            let d = Date(timeIntervalSince1970: s.date)
            let idx = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: d)).day ?? 0
            if idx >= 0 && idx < 7 {
                perDay[idx].append(s)
            }
        }

        var candleEntries: [CandleChartDataEntry] = []

        for i in 0..<7 {
            let daySamples = perDay[i].sorted { $0.date < $1.date }
            let dayDate = cal.date(byAdding: .day, value: i, to: start) ?? start

            if daySamples.isEmpty {
                // Empty day -> invisible candle at 0
                candleEntries.append(CandleChartDataEntry(x: Double(i), shadowH: 0, shadowL: 0, open: 0, close: 0))
                continue
            }

            let percents = daySamples.map { $0.percent }
            let hi = percents.max() ?? 0
            let lo = percents.min() ?? 0

            // Use open/close to create a body; keep it consistent (open=hi, close=lo).
            candleEntries.append(CandleChartDataEntry(x: Double(i), shadowH: hi, shadowL: lo, open: hi, close: lo))

            // Label for x-axis
            weekXAxisFormatter.setLabel(forIndex: i, date: dayDate)
        }

        let set = CandleChartDataSet(entries: candleEntries, label: "")
        set.drawValuesEnabled = false
        set.highlightEnabled = true
        set.setDrawHighlightIndicators(false)   // så du slipper crosshair-linjer
        set.shadowWidth = 1
        // Single color for all week candles (focus is on day-to-day range differences)
        let c = UIColor.systemGreen
        set.shadowColor = c
        set.increasingColor = c
        set.decreasingColor = c
        set.neutralColor = c
        set.shadowColorSameAsCandle = true
        set.formLineWidth = 0
        set.barSpace = 0.2

        let data = CandleChartData(dataSet: set)

        await MainActor.run {
            self.weekChartView.data = data
            self.weekChartView.notifyDataSetChanged()
        }
    }

    // MARK: - Helpers

    private func updateDayLegendText() {
        let a = NSMutableAttributedString(string: "Batteristatus:  ")

        func add(_ title: String, color: UIColor) {
            let sq = NSAttributedString(
                string: "■ ",
                attributes: [.foregroundColor: color]
            )
            let txt = NSAttributedString(
                string: title,
                attributes: [.foregroundColor: UIColor.secondaryLabel]
            )
            a.append(sq)
            a.append(txt)
        }

        add("Laddar  ", color: .systemBlue)
        add("Bra  ", color: .systemGreen)
        add("Låg  ", color: .systemOrange)
        add("Akut låg", color: .systemRed)

        dayLegendLabel.attributedText = a
    }

    private func colorForBattery(percent: Double, isCharging: Bool) -> UIColor {
        if isCharging { return .systemBlue }
        if percent >= 50 { return .systemGreen }
        if percent >= 20 { return .systemOrange }
        return .systemRed
    }

    private func startOfWeek(for date: Date) -> Date {
        let cal = Calendar.current
        // Use user's locale/calendar settings
        if let interval = cal.dateInterval(of: .weekOfYear, for: date) {
            return cal.startOfDay(for: interval.start)
        }
        return cal.startOfDay(for: date)
    }
    
    // MARK: - ChartViewDelegate (tap-to-navigate)

    func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
        if chartView === weekChartView {
            // Week -> Day: x is 0..6 for the day index in the selected week
            let idx = Int(round(entry.x))
            guard idx >= 0 && idx < 7 else { return }

            let cal = Calendar.current
            let weekStart = startOfWeek(for: selectedDate)
            guard let dayDate = cal.date(byAdding: .day, value: idx, to: weekStart) else { return }

            // Switch to day mode and show that date
            applyMode(.day, keepingDate: dayDate)
            selectedDate = cal.startOfDay(for: dayDate)
            datePicker.date = selectedDate
            reload()

            // Clear highlight to avoid accidental re-selection
            weekChartView.highlightValues(nil)

        } else if chartView === dayChartView {
            // Day -> Week: any bar tap opens the week containing the current selected day (Monday start)
            let cal = Calendar.current
            let weekStart = startOfWeek(for: selectedDate)

            applyMode(.week, keepingDate: weekStart)
            selectedDate = cal.startOfDay(for: weekStart)
            datePicker.date = selectedDate
            reload()

            dayChartView.highlightValues(nil)
        }
    }
    
    func chartValueNothingSelected(_ chartView: ChartViewBase) {
        // No-op
    }
}

// MARK: - Axis formatters

private final class BatteryYAxisValueFormatter: AxisValueFormatter {
    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let v = Int(round(value))
        if v == 0 || v == 50 || v == 100 {
            return "\(v) %"
        }
        return ""
    }
}

private final class DayBatteryXAxisFormatter: AxisValueFormatter {
    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let i = Int(round(value))
        switch i {
        case 0: return "00"
        case 24: return "06"
        case 48: return "12"
        case 72: return "18"
        case 96: return "24"
        default: return ""
        }
    }
}

private final class WeekBatteryXAxisFormatter: AxisValueFormatter {

    private var labels: [Int: String] = [:]
    private let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "dd/MM"
        return f
    }()

    func setLabel(forIndex idx: Int, date: Date) {
        labels[idx] = df.string(from: date)
    }

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let i = Int(round(value))
        return labels[i] ?? ""
    }
}
