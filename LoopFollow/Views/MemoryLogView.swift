//
//  MemoryLogView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2026-09-11.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import Foundation
import UIKit
import Charts

// MARK: - Memory Log

struct MemoryEntry {
    let date: Date
    let mib: Double
}

/// Simple day-filtered memory log table.
final class MemoryLogViewController: ThemedViewController, UITableViewDataSource, UITableViewDelegate {

    private var entries: [MemoryEntry] = []
    private var selectedDate: Date = Date()

    // Toggle to show only missing rows
    private var showOnlyMissingMemory: Bool = false

    /// Row model for the table (memory + missing slots)
    private enum MemoryRow {
        case memory(MemoryEntry)
        case missing(Date)

        var date: Date {
            switch self {
            case .memory(let e): return e.date
            case .missing(let d): return d
            }
        }

        var isMissing: Bool {
            if case .missing = self { return true }
            return false
        }
    }

    private let tableView = UITableView(frame: .zero, style: .plain)

    private let datePicker: UIDatePicker = {
        let dp = UIDatePicker()
        dp.datePickerMode = .date
        dp.preferredDatePickerStyle = .compact
        dp.translatesAutoresizingMaskIntoConstraints = false
        dp.locale = Locale(identifier: "sv_SE")
        return dp
    }()

    private let statsLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        l.textAlignment = .right
        l.text = "Minnesvärden: –"
        return l
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // Build per-day rows, inserting missing 5‑min slots when gaps exceed ~6 minutes.
    private var dayRowsIncludingMissing: [MemoryRow] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }

        let dayEntriesAsc = entries
            .filter { $0.date >= start && $0.date < end }
            .sorted { $0.date < $1.date }

        guard !dayEntriesAsc.isEmpty else { return [] }

        var rows: [MemoryRow] = []
        rows.reserveCapacity(dayEntriesAsc.count)

        for idx in 0..<dayEntriesAsc.count {
            let current = dayEntriesAsc[idx]
            rows.append(.memory(current))

            if idx < dayEntriesAsc.count - 1 {
                let next = dayEntriesAsc[idx + 1]
                let gap = next.date.timeIntervalSince(current.date)

                // Threshold: if more than 6 min, we consider at least one missing 5‑min slot
                if gap > 360 {
                    let missingCount = Int(floor((gap - 360) / 300)) + 1
                    if missingCount > 0 {
                        for i in 1...missingCount {
                            let missingDate = current.date.addingTimeInterval(Double(i) * 300)
                            if missingDate < next.date {
                                rows.append(.missing(missingDate))
                            }
                        }
                    }
                }
            }
        }

        // Tail-gap: insert missing slots after last actual value.
        let now = Date()
        if let lastActual = dayEntriesAsc.last {
            if cal.isDate(selectedDate, inSameDayAs: now) {
                // Today → fill to "now"
                let gapToNow = now.timeIntervalSince(lastActual.date)
                if gapToNow > 360 {
                    let missingCount = Int(floor((gapToNow - 360) / 300)) + 1
                    if missingCount > 0 {
                        for i in 1...missingCount {
                            let missingDate = lastActual.date.addingTimeInterval(Double(i) * 300)
                            if missingDate <= now {
                                rows.append(.missing(missingDate))
                            }
                        }
                    }
                }
            } else {
                // Historic day → fill to end-of-day (24:00)
                let gapToEnd = end.timeIntervalSince(lastActual.date)
                if gapToEnd > 360 {
                    let missingCount = Int(floor((gapToEnd - 360) / 300)) + 1
                    if missingCount > 0 {
                        for i in 1...missingCount {
                            let missingDate = lastActual.date.addingTimeInterval(Double(i) * 300)
                            if missingDate < end {
                                rows.append(.missing(missingDate))
                            }
                        }
                    }
                }
            }
        }

        // Table wants newest first
        return rows.sorted { $0.date > $1.date }
    }

    private var filteredRows: [MemoryRow] {
        let rows = dayRowsIncludingMissing
        if showOnlyMissingMemory {
            let missing = rows.filter { $0.isMissing }
            if missing.isEmpty {
                // Insert a synthetic placeholder missing row at noon
                let cal = Calendar.current
                let start = cal.startOfDay(for: selectedDate)
                let placeholderDate = cal.date(byAdding: .hour, value: 12, to: start) ?? start
                return [.missing(placeholderDate)]
            }
            return missing
        }
        return rows
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Trio minneslogg"
        updateBackgroundForCurrentMode()

        setupNavigationBar()
        setupTableView()
        setupHeader()
        setupConstraints()

        // Date picker bounds follow cache retention
        let cal = Calendar.current
        if let oldest = cal.date(byAdding: .day, value: -MemoryCache.retentionDays + 1, to: Date()) {
            datePicker.minimumDate = oldest
        }
        datePicker.maximumDate = Date()
        datePicker.date = selectedDate
        datePicker.addTarget(self, action: #selector(dateChanged(_:)), for: .valueChanged)

        loadDay(selectedDate)
    }

    private func setupNavigationBar() {
        let isModalRoot = navigationController?.viewControllers.first === self

        let filter = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            style: .plain,
            target: self,
            action: #selector(toggleMissingOnly)
        )
        filter.tintColor = .label

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

        if isModalRoot {
            //navigationItem.leftBarButtonItems = [filter]
            navigationItem.rightBarButtonItems = [done, stats, filter]
        } else {
            navigationItem.leftItemsSupplementBackButton = true
            //navigationItem.leftBarButtonItems = [filter]
            navigationItem.rightBarButtonItems = [stats, filter]
        }
    }
    @objc private func toggleMissingOnly() {
        showOnlyMissingMemory.toggle()

        if let filterButton = navigationItem.rightBarButtonItems?.last {
            let name = showOnlyMissingMemory
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle"
            filterButton.image = UIImage(systemName: name)
            filterButton.tintColor = showOnlyMissingMemory ? .systemBlue : .label
        }

        tableView.reloadData()
        updateStatsLabel()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func showStats() {
        let statsVC = MemoryLogStatsViewController()
        statsVC.selectedDate = selectedDate
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
        tableView.register(Value1TableViewCell.self, forCellReuseIdentifier: "MemoryCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.isOpaque = false
    }

    private func setupHeader() {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [datePicker, spacer, statsLabel])
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        row.tag = 999

        view.addSubview(row)

        datePicker.setContentHuggingPriority(.required, for: .horizontal)
        datePicker.setContentCompressionResistancePriority(.required, for: .horizontal)
        datePicker.heightAnchor.constraint(equalToConstant: 30).isActive = true
        datePicker.widthAnchor.constraint(lessThanOrEqualToConstant: 105).isActive = true
    }

    private func setupConstraints() {
        let safe = view.safeAreaLayoutGuide

        guard let headerRow = view.subviews.first(where: { $0.tag == 999 }) else { return }

        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            headerRow.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 8),
            headerRow.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -8),

            tableView.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func dateChanged(_ sender: UIDatePicker) {
        selectedDate = sender.date
        loadDay(selectedDate)
        updateStatsLabel()
    }

    private func loadDay(_ date: Date) {
        Task {
            let samples = await MemoryCache.loadDay(date)
            let mapped: [MemoryEntry] = samples.map {
                MemoryEntry(date: Date(timeIntervalSince1970: $0.date), mib: $0.mib)
            }

            await MainActor.run {
                guard Calendar.current.isDate(self.selectedDate, inSameDayAs: date) else { return }
                // Newest first
                self.entries = mapped.sorted { $0.date > $1.date }
                self.tableView.reloadData()
                self.updateStatsLabel()
            }
        }
    }

    private func expectedMemorySlots(for day: Date, upTo now: Date? = nil) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return 288 }

        let upper = min(now ?? end, end)
        let seconds = max(0, upper.timeIntervalSince(start))
        return max(1, Int(floor(seconds / 300.0)))
    }

    private func updateStatsLabel() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else {
            statsLabel.text = "Minnesvärden: –"
            return
        }

        let now = Date()
        let isToday = cal.isDate(selectedDate, inSameDayAs: now)

        let actualCount = entries.filter { $0.date >= start && $0.date < end }.count

        let expectedCount: Int = isToday
            ? expectedMemorySlots(for: selectedDate, upTo: now)
            : expectedMemorySlots(for: selectedDate)

        var expectedCountAdjusted = max(actualCount, expectedCount)

        // Om vi har saknade slots – undvik 100 % för tidigt
        let missingCount = dayRowsIncludingMissing.filter { $0.isMissing }.count
        if missingCount > 0 && expectedCountAdjusted == expectedCount {
            expectedCountAdjusted += 1
        }

        let pct = expectedCountAdjusted > 0
            ? Int(round(Double(actualCount) / Double(expectedCountAdjusted) * 100.0))
            : 0

        let emoji: String
        if pct > 95 {
            emoji = " 🟢"
        } else if pct > 90 {
            emoji = " 🟡"
        } else {
            emoji = " 🔴"
        }

        statsLabel.text =
            "Minnesvärden:  \(actualCount)/\(expectedCount)  \(pct)%" + emoji
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // When no memory data exists at all, keep a single placeholder row.
        if entries.isEmpty {
            return 1
        }
        return max(filteredRows.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "MemoryCell", for: indexPath) as? Value1TableViewCell else {
            return UITableViewCell(style: .value1, reuseIdentifier: "MemoryCell")
        }

        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.selectionStyle = .none
        cell.textLabel?.font = .systemFont(ofSize: 17)

        // No raw data at all
        if entries.isEmpty {
            cell.textLabel?.text = "Inga minnesdata"
            cell.detailTextLabel?.text = ""
            return cell
        }

        let rows = filteredRows
        if rows.isEmpty {
            cell.textLabel?.text = "Inga minnesdata"
            cell.detailTextLabel?.text = ""
            return cell
        }

        let row = rows[indexPath.row]

        switch row {
        case .memory(let e):
            let timeStr = timeFormatter.string(from: e.date)
            cell.textLabel?.text = String(format: "%.0f MiB", e.mib)
            cell.detailTextLabel?.text = timeStr
            cell.detailTextLabel?.font = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .regular)
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear

        case .missing(let date):
            // Detect placeholder: no actual missing rows and showOnlyMissingMemory = true
            let isPlaceholder = showOnlyMissingMemory && dayRowsIncludingMissing.filter { $0.isMissing }.isEmpty
            if isPlaceholder {
                cell.textLabel?.text = "Inga saknade värden denna dag ✅"
                cell.detailTextLabel?.text = ""
                cell.textLabel?.font = .systemFont(ofSize: 17)
                let tint = UIColor.systemGreen.withAlphaComponent(0.12)
                cell.backgroundColor = tint
                cell.contentView.backgroundColor = tint
            } else {
                cell.textLabel?.text = "[Minnesvärde saknas]"
                cell.detailTextLabel?.text = timeFormatter.string(from: date)
                let tint = UIColor.systemRed.withAlphaComponent(0.15)
                cell.backgroundColor = tint
                cell.contentView.backgroundColor = tint
                cell.textLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            }
        }

        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
}

/// Memory stats view with Day / Week visualization.
final class MemoryLogStatsViewController: ThemedViewController, ChartViewDelegate {

    private enum Mode: Int {
        case day = 0
        case week = 1
    }

    private var mode: Mode = .day
    var selectedDate: Date = Date()

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
    private let dayXAxisFormatter = DayMemoryXAxisFormatter()
    private let weekXAxisFormatter = WeekMemoryXAxisFormatter()
    private let yAxisFormatter = MemoryYAxisValueFormatter()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Minnestatistik"
        updateBackgroundForCurrentMode()

        setupNavigationBar()
        setupHeader()
        setupCharts()
        setupConstraints()

        // Date picker bounds follow cache retention
        let cal = Calendar.current
        if let oldest = cal.date(byAdding: .day, value: -MemoryCache.retentionDays + 1, to: Date()) {
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

        navigationItem.rightBarButtonItems = [done, next, prev]
        //navigationItem.leftBarButtonItems = [prev, next]
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
        updateLegendText(for: .day)

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
        //dayChartView.backgroundColor = .clear
        //weekChartView.backgroundColor = .clear

        dayChartView.drawGridBackgroundEnabled = true
        dayChartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)
        weekChartView.drawGridBackgroundEnabled = true
        weekChartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)

        // Ensure content isn't clipped at edges, and give extra room for edge labels
        weekChartView.setExtraOffsets(left: 14, top: 0, right: 14, bottom: 0)
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
        leftAxis.axisMaximum = 1 // Empty/all-zero data fallback; updated for each dataset.
        leftAxis.granularityEnabled = false
        leftAxis.setLabelCount(6, force: true)
        leftAxis.valueFormatter = yAxisFormatter
        leftAxis.drawLabelsEnabled = true

        leftAxis.drawGridLinesEnabled = true
        leftAxis.gridLineDashLengths = [2, 2]
        leftAxis.gridColor = UIColor.label.withAlphaComponent(0.5)

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
        x.setLabelCount(9, force: true)
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
        // We want ticks at integer day indices (0...6). When using padded min/max (-0.5..6.5),
        // do NOT force label count; forced labels are evenly distributed across the padded range
        // (step = 7/6) and would produce non-integer values that get rounded by the formatter.
        x.granularityEnabled = true
        x.granularity = 1

        // Add half-step padding so day 0 and day 6 candles are not clipped
        x.axisMinimum = -0.5
        x.axisMaximum = 6.5

        // Hint desired count, but do not force.
        x.setLabelCount(7, force: false)
        x.valueFormatter = weekXAxisFormatter

        // Keep first/last labels visible (prevents clipping/vanishing at edges)
        x.avoidFirstLastClippingEnabled = false

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
            updateLegendText(for: .day)
            selectedDate = date
            datePicker.date = selectedDate

        case .week:
            dayChartView.isHidden = true
            weekChartView.isHidden = false
            dayLegendLabel.isHidden = false   // 👈 fortfarande synlig
            updateLegendText(for: .week)
            selectedDate = startOfWeek(for: date)
            datePicker.date = selectedDate
        }

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
        let samples = await MemoryCache.loadDay(date)

        // One bar per saved reading, positioned by local time on the same 00–24 axis.
        let cal = Calendar.current
        let entries = samples.sorted { $0.date < $1.date }.map { sample in
            let components = cal.dateComponents([.hour, .minute, .second], from: Date(timeIntervalSince1970: sample.date))
            let seconds = Double((components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0))
            let x = min(95.85, max(0.15, seconds / 900))
            return BarChartDataEntry(x: x, y: sample.mib)
        }

        let set = BarChartDataSet(entries: entries, label: "Minnesanvändning (MiB)")
        set.colors = [.white]
        set.drawValuesEnabled = false
        set.highlightEnabled = true

        let data = BarChartData(dataSet: set)
        data.barWidth = 0.3

        await MainActor.run {
            guard self.mode == .day, Calendar.current.isDate(self.selectedDate, inSameDayAs: date) else { return }
            let maximumMiB = samples.map { $0.mib }.max() ?? 0
            self.dayChartView.leftAxis.axisMaximum = maximumMiB > 0 ? maximumMiB : 1
            self.dayChartView.data = data
            self.dayChartView.notifyDataSetChanged()
        }
    }

    private func buildWeekChart(startingAt weekStart: Date) async {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        let start = cal.startOfDay(for: weekStart)
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start

        // Load all samples in the week window (inclusive).
        let endOfLastDay = cal.date(byAdding: .day, value: 1, to: end)!.addingTimeInterval(-1)
        let samples = await MemoryCache.loadWindow(from: start, to: endOfLastDay)

        // Build min/max per day
        var perDay: [[MemorySampleJSON]] = Array(repeating: [], count: 7)
        for s in samples {
            let d = Date(timeIntervalSince1970: s.date)
            let idx = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: d)).day ?? 0
            if idx >= 0 && idx < 7 {
                perDay[idx].append(s)
            }
        }

        var candleEntries: [CandleChartDataEntry] = []
        guard mode == .week, startOfWeek(for: selectedDate) == start else { return }
        weekXAxisFormatter.reset()

        for i in 0..<7 {
            let daySamples = perDay[i].sorted { $0.date < $1.date }
            let dayDate = cal.date(byAdding: .day, value: i, to: start) ?? start

            // ✅ Always set x-axis label (even if the day has no samples)
            weekXAxisFormatter.setLabel(forIndex: i, date: dayDate)

            guard !daySamples.isEmpty else { continue }

            let mibs = daySamples.map { $0.mib }
            let hi = mibs.max() ?? 0
            let lo = mibs.min() ?? 0

            candleEntries.append(CandleChartDataEntry(x: Double(i), shadowH: hi, shadowL: lo, open: hi, close: lo))

        }

        let set = CandleChartDataSet(entries: candleEntries, label: "")
        set.drawValuesEnabled = false
        set.highlightEnabled = true
        set.setDrawHighlightIndicators(false)   // så du slipper crosshair-linjer
        set.shadowWidth = 1

        set.colors = [.white]
        set.decreasingColor = .white
        set.increasingColor = .white
        set.neutralColor = .white
        set.decreasingFilled = true
        set.increasingFilled = true
        set.shadowColorSameAsCandle = true
        set.formLineWidth = 0
        set.barSpace = 0.2

        let data = CandleChartData(dataSet: set)

        await MainActor.run {
            guard self.mode == .week, self.startOfWeek(for: self.selectedDate) == start else { return }
            let maximumMiB = samples.map { $0.mib }.max() ?? 0
            self.weekChartView.leftAxis.axisMaximum = maximumMiB > 0 ? maximumMiB : 1
            self.weekChartView.data = data
            self.weekChartView.notifyDataSetChanged()
        }
    }

    // MARK: - Helpers

    private func updateLegendText(for mode: Mode) {
        let text = mode == .day
            ? "Minnesanvändning per mätning (MiB)"
            : "Max/min minnesanvändning per dag (MiB)"
        let legend = NSMutableAttributedString(string: "■ ", attributes: [.foregroundColor: UIColor.white])
        legend.append(NSAttributedString(string: text, attributes: [.foregroundColor: UIColor.secondaryLabel]))
        dayLegendLabel.attributedText = legend
    }

    private func startOfWeek(for date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
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

private final class MemoryYAxisValueFormatter: AxisValueFormatter {
    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let format = (axis?.axisMaximum ?? 0) < 5 ? "%.1f MiB" : "%.0f MiB"
        return String(format: format, value)
    }
}

private final class DayMemoryXAxisFormatter: AxisValueFormatter {
    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let i = Int(round(value))
        switch i {
        case 0: return "00"
        case 12: return "03"
        case 24: return "06"
        case 36: return "09"
        case 48: return "12"
        case 60: return "15"
        case 72: return "18"
        case 84: return "21"
        case 96: return "24"
        default: return ""
        }
    }
}

private final class WeekMemoryXAxisFormatter: AxisValueFormatter {

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

    func reset() {
        labels.removeAll()
    }
}
