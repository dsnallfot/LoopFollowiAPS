//
//  GlucoseView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-11-22.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import UIKit

/// Table-style glucose log, similar look/feel to TreatmentsTableView.
final class GlucoseView: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Glucose data (same source as MealAnalysisView)
    private var bgEntries: [BGEntry] = []

    // Selected day for table
    private var selectedDate: Date = Date()

    // UI
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let datePicker: UIDatePicker = {
        let dp = UIDatePicker()
        dp.datePickerMode = .date
        dp.preferredDatePickerStyle = .compact
        dp.translatesAutoresizingMaskIntoConstraints = false
        return dp
    }()

    private var activityIndicator: UIActivityIndicatorView?

    // Toggle to show only missing rows
    private var showOnlyMissingGlucose: Bool = false

    /// Row model for the table
    private enum GlucoseRow {
        case glucose(BGEntry)
        case missing(Date)

        var date: Date {
            switch self {
            case .glucose(let e): return e.date
            case .missing(let d): return d
            }
        }

        var isMissing: Bool {
            if case .missing = self { return true }
            return false
        }
    }

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    
    private let statsLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .secondaryLabel
        l.textAlignment = .right
        l.numberOfLines = 1
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }()

    // Build per-day rows, inserting missing 5‑min slots when gaps exceed ~6 minutes.
    private var dayRowsIncludingMissing: [GlucoseRow] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }

        let dayEntriesAsc = bgEntries
            .filter { $0.date >= start && $0.date < end }
            .sorted { $0.date < $1.date }

        guard !dayEntriesAsc.isEmpty else { return [] }

        var rows: [GlucoseRow] = []
        rows.reserveCapacity(dayEntriesAsc.count)

        for idx in 0..<dayEntriesAsc.count {
            let current = dayEntriesAsc[idx]
            rows.append(.glucose(current))

            // Insert missing rows between current and next
            if idx < dayEntriesAsc.count - 1 {
                let next = dayEntriesAsc[idx + 1]
                let gap = next.date.timeIntervalSince(current.date)

                // Threshold: if more than 6 min, we consider at least one missing 5‑min slot
                if gap > 360 {
                    let missingCount = Int(floor((gap - 360) / 300)) + 1
                    if missingCount > 0 {
                        for i in 1...missingCount {
                            let missingDate = current.date.addingTimeInterval(Double(i) * 300)
                            rows.append(.missing(missingDate))
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

    private var filteredRows: [GlucoseRow] {
        let rows = dayRowsIncludingMissing
        if showOnlyMissingGlucose {
            return rows.filter { $0.isMissing }
        }
        return rows
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Glukoslogg"
        view.backgroundColor = .systemBackground

        setupNavigationBar()
        setupTableView()
        setupHeader()
        setupConstraints()

        // Date picker bounds roughly follow cache retention
        let cal = Calendar.current
        if let oldest = cal.date(byAdding: .day,
                                 value: -NightscoutCache.retentionDays,
                                 to: Date()) {
            datePicker.minimumDate = oldest
        }
        datePicker.maximumDate = Date()
        datePicker.date = selectedDate
        datePicker.addTarget(self, action: #selector(dateChanged(_:)), for: .valueChanged)

        // Initial load for today
        loadBG(for: selectedDate)
    }

    // MARK: - Navigation bar
    private func setupNavigationBar() {
        // Day-stepper chevrons (top-left)
        let back = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(prevDayTapped)
        )
        let forward = UIBarButtonItem(
            image: UIImage(systemName: "chevron.right"),
            style: .plain,
            target: self,
            action: #selector(nextDayTapped)
        )
        navigationItem.leftBarButtonItems = [back, forward]

        // Optional close button to mirror other modal logs
        let done = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(doneTapped)
        )

        let filter = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            style: .plain,
            target: self,
            action: #selector(toggleMissingOnly)
        )
        filter.tintColor = .label

        navigationItem.rightBarButtonItems = [done, filter]
    }

    @objc private func doneTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func toggleMissingOnly() {
        showOnlyMissingGlucose.toggle()

        if let filterButton = navigationItem.rightBarButtonItems?.last {
            let name = showOnlyMissingGlucose
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle"
            filterButton.image = UIImage(systemName: name)
            filterButton.tintColor = showOnlyMissingGlucose ? .systemBlue : .label
        }

        tableView.reloadData()
        updateStatsLabel()
    }

    @objc private func prevDayTapped() { stepDay(by: -1) }
    @objc private func nextDayTapped() { stepDay(by: 1) }

    private func stepDay(by delta: Int) {
        let cal = Calendar.current
        guard let newDate = cal.date(byAdding: .day, value: delta, to: selectedDate) else { return }

        // Clamp to picker range (no future days, no earlier than cache window)
        if let minDate = datePicker.minimumDate, newDate < cal.startOfDay(for: minDate) { return }
        if newDate > Date() { return }

        selectedDate = newDate
        datePicker.setDate(newDate, animated: true)
        loadBG(for: newDate)
        updateStatsLabel()
    }

    // MARK: - Header
    private func setupHeader() {
        // We’ll use a simple horizontal stack for date picker (like TreatmentsTableView)
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerStack = UIStackView(arrangedSubviews: [datePicker, spacer, statsLabel])
        headerStack.axis = .horizontal
        headerStack.spacing = 6
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.tag = 999 // so we can find it in constraints
        view.addSubview(headerStack)

        datePicker.setContentHuggingPriority(.required, for: .horizontal)
        datePicker.setContentCompressionResistancePriority(.required, for: .horizontal)
        datePicker.heightAnchor.constraint(equalToConstant: 30).isActive = true
        datePicker.widthAnchor.constraint(lessThanOrEqualToConstant: 105).isActive = true

        statsLabel.text = "CGM –" // placeholder until data loads
    }

    // MARK: - Table
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        tableView.register(Value1TableViewCell.self, forCellReuseIdentifier: "GlucoseCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
    }

    private func setupConstraints() {
        let safe = view.safeAreaLayoutGuide
        guard let headerStack = view.subviews.first(where: { $0.tag == 999 }) else { return }

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            headerStack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 8),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -8),

            tableView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Loading

    /// Load BG for a calendar day. Uses live 24h fetch for today, otherwise uses NightscoutCache.
    private func loadBG(for date: Date) {
        let cal = Calendar.current
        let now = Date()

        showRefreshIndicator()

        if cal.isDate(date, inSameDayAs: now) {
            // Live fetch (same as MealAnalysisView.fetchBG24h)
            BGProvider.fetch { [weak self] sgv in
                guard let self = self else { return }
                let newBG: [BGEntry] = sgv.map {
                    BGEntry(date: Date(timeIntervalSince1970: $0.date),
                            mmol: Double($0.sgv) / 18.0182)
                }
                DispatchQueue.main.async {
                    // Replace today-window entries, keep older cached ones
                    let startToday = cal.startOfDay(for: now)
                    self.bgEntries.removeAll { $0.date >= startToday }
                    self.bgEntries.append(contentsOf: newBG)
                    self.bgEntries.sort { $0.date < $1.date }
                    self.tableView.reloadData()
                    self.updateStatsLabel()
                    self.hideRefreshIndicator()
                }
            }
            return
        }

        // Cached day loader
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!

        Task {
            let (sgvJSON, _) = await NightscoutCache.loadWindow(from: start, to: end)
            let cachedBG: [BGEntry] = sgvJSON.map {
                BGEntry(date: Date(timeIntervalSince1970: $0.date),
                        mmol: Double($0.sgv) / 18.0182)
            }

            DispatchQueue.main.async {
                // Remove any existing entries inside that day and replace them
                self.bgEntries.removeAll { $0.date >= start && $0.date < end }
                self.bgEntries.append(contentsOf: cachedBG)
                self.bgEntries.sort { $0.date < $1.date }
                self.tableView.reloadData()
                self.updateStatsLabel()
                self.hideRefreshIndicator()
            }
        }
    }

    private func showRefreshIndicator() {
        if activityIndicator == nil {
            let ind = UIActivityIndicatorView(style: .medium)
            ind.startAnimating()
            activityIndicator = ind
            navigationItem.titleView = ind
        }
    }

    private func hideRefreshIndicator() {
        navigationItem.titleView = nil
        activityIndicator = nil
    }
    
    private func updateStatsLabel() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else {
            statsLabel.text = " CGM avläsningar: –"
            return
        }

        let now = Date()
        let isToday = cal.isDate(selectedDate, inSameDayAs: now)

        let actualCount = bgEntries.filter { $0.date >= start && $0.date < end }.count

        let expectedCount: Int
        if isToday {
            let secondsSinceStart = now.timeIntervalSince(start)
            expectedCount = max(1, Int(floor(secondsSinceStart / 300)))
        } else {
            expectedCount = 288
        }

        let pct = expectedCount > 0 ? Int(round(Double(actualCount) / Double(expectedCount) * 100.0)) : 0
        statsLabel.text = " CGM avläsningar:  \(actualCount)/\(expectedCount)  \(pct)%"
    }

    @objc private func dateChanged(_ sender: UIDatePicker) {
        selectedDate = sender.date
        loadBG(for: selectedDate)
        updateStatsLabel()
    }

    // MARK: - UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredRows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "GlucoseCell", for: indexPath) as? Value1TableViewCell else {
            return UITableViewCell(style: .value1, reuseIdentifier: "GlucoseCell")
        }

        let row = filteredRows[indexPath.row]

        switch row {
        case .glucose(let entry):
            cell.textLabel?.text = String(format: "%.1f mmol/L", entry.mmol)
            cell.textLabel?.font = .systemFont(ofSize: 17)
            cell.detailTextLabel?.text = timeFormatter.string(from: entry.date)
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear

        case .missing(let date):
            cell.textLabel?.text = "[Saknas]"
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            cell.detailTextLabel?.text = timeFormatter.string(from: date)

            // Red‑tinted background to stand out
            let tint = UIColor.systemRed.withAlphaComponent(0.12)
            cell.backgroundColor = tint
            cell.contentView.backgroundColor = tint
        }

        cell.accessoryType = .none
        cell.selectionStyle = .none
        return cell
    }

    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
}
