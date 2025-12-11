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
    /// Aktiva värden för valt läge (driver tabell + stats).
    private var bgEntries: [BGEntry] = []
    /// NS-only Trio → Nightscout-värden för vald dag.
    private var nsOnlyDayEntries: [BGEntry] = []
    /// Dexcom+Nightscout-mergade värden för vald dag.
    private var allValuesDayEntries: [BGEntry] = []

    /// Which data source to show in the table.
    private enum GlucoseDataMode {
        case allValues      // Dexcom + Nightscout merged (ordinary BG cache)
        case nsOnly         // Only Trio → Nightscout uploads (NS-only cache)
    }

    /// Why a 5‑min slot is missing.
    private enum MissingReason {
        case sensor       // Sensor never produced a reading (missing in both datasets)
        case trioUpload   // Trio/NS upload missing, but sensor (Dexcom) has the value
    }

    private var dataMode: GlucoseDataMode = .allValues
    
    // How many days back the manual backfill refresh should fetch (used by reload button)
    private let backfillDays = 14
    // Initial Nightscout backfill window for NS-only cache used in GlucoseView
    private let initialBackfillDays = 90
    // UserDefaults flag so we only run the large initial backfill once
    private let initialBackfillFlagKey = "GlucoseViewInitialNSBackfillDone"

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

    private let modeSegmentedControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Alla värden", "Endast Trio ⇢ NS"])
        sc.selectedSegmentIndex = 0
        sc.translatesAutoresizingMaskIntoConstraints = false
        return sc
    }()

    private var activityIndicator: UIActivityIndicatorView?

    // Toggle to show only missing rows
    private var showOnlyMissingGlucose: Bool = false

    /// Row model for the table
    private enum GlucoseRow {
        case glucose(BGEntry)
        case missing(Date, MissingReason)

        var date: Date {
            switch self {
            case .glucose(let e): return e.date
            case .missing(let d, _): return d
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
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }()

    // Build per-day rows, inserting missing 5‑min slots when gaps exceed ~6 minutes.
    private var dayRowsIncludingMissing: [GlucoseRow] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }

        let baseEntries: [BGEntry]
        switch dataMode {
        case .allValues:
            baseEntries = allValuesDayEntries
        case .nsOnly:
            baseEntries = nsOnlyDayEntries
        }

        let dayEntriesAsc = baseEntries
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
                            let reason = missingReason(for: missingDate)
                            rows.append(.missing(missingDate, reason))
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
                                let reason = missingReason(for: missingDate)
                                rows.append(.missing(missingDate, reason))
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
                                let reason = missingReason(for: missingDate)
                                rows.append(.missing(missingDate, reason))
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
            let missing = rows.filter { $0.isMissing }
            if missing.isEmpty {
                // Insert a synthetic placeholder missing row at noon
                let cal = Calendar.current
                let start = cal.startOfDay(for: selectedDate)
                let placeholderDate = cal.date(byAdding: .hour, value: 12, to: start) ?? start
                return [.missing(placeholderDate, .sensor)]
            }
            return missing
        }
        return rows
    }

    /// Bestäm varför ett 5‑minuters-slot saknas.
    ///
    /// - Om varken NS-only eller Alla värden har en avläsning i samma 5-minutersbucket
    ///   → behandla som sensor-miss.
    /// - Om Alla värden har en avläsning men NS-only inte har det
    ///   → behandla som Trio-upload-miss.
    private func missingReason(for date: Date) -> MissingReason {
        let bucket = Int(floor(date.timeIntervalSince1970 / 300.0))

        func hasEntry(in entries: [BGEntry]) -> Bool {
            entries.contains { entry in
                let b = Int(floor(entry.date.timeIntervalSince1970 / 300.0))
                return b == bucket
            }
        }

        let hasAllValues = hasEntry(in: allValuesDayEntries)
        let hasNSOnly    = hasEntry(in: nsOnlyDayEntries)

        if !hasAllValues && !hasNSOnly {
            return .sensor
        }
        if hasAllValues && !hasNSOnly {
            return .trioUpload
        }
        // Fallback
        return .sensor
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "BG logg"
        view.backgroundColor = .systemBackground

        setupNavigationBar()
        setupTableView()
        setupHeader()
        setupConstraints()

        // Date picker bounds roughly follow NS-only glucose cache retention
        let cal = Calendar.current
        if let oldest = cal.date(byAdding: .day,
                                 value: -GlucoseNSOnlyCache.retentionDays + 1,
                                 to: Date()) {
            datePicker.minimumDate = oldest
        }
        datePicker.maximumDate = Date()
        datePicker.date = selectedDate
        datePicker.addTarget(self, action: #selector(dateChanged(_:)), for: .valueChanged)

        // Debug: list cached NS-only glucose day files whenever entering GlucoseView
        GlucoseNSOnlyCache.debugListSegments()
        print("GlucoseNSOnlyCache dir:", GlucoseNSOnlyCache.dir.path)

        // Initial NS-only backfill (90 days) + initial load for today from NS cache
        Task {
            await self.ensureInitialBackfill()
            await MainActor.run {
                self.loadBG(for: self.selectedDate)
            }
        }
    }

    // MARK: - Navigation bar
    private var reloadButton: UIBarButtonItem?
    private var reloadIndicator: UIActivityIndicatorView?
    private func setupNavigationBar() {
        let reload = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshButtonTapped)
        )
        self.reloadButton = reload
        
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
        navigationItem.leftBarButtonItems = [reload, back, forward]

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
    
    @objc private func refreshButtonTapped() {
        showRefreshIndicator()
        Task {
            await backfillLastDays(backfillDays)
            DispatchQueue.main.async {
                self.loadBG(for: self.selectedDate)
            }
        }
    }
    
    /// Fetches X days back from Nightscout and writes SGVs into the NS-only glucose cache.
    /// Overwrites existing cached days only if needed.
    private func backfillLastDays(_ days: Int) async {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(byAdding: .day, value: -days, to: now)!

        print("🔄 Backfilling \(days) days (NS-only glucose): \(start) → \(now)")

        let sgvBatch = await NightscoutUtils.fetchSGVWindow(from: start, to: now)
        if !sgvBatch.isEmpty {
            GlucoseNSOnlyCache.mergeSGVBatch(sgvBatch)
            GlucoseNSOnlyCache.purgeOldFiles()
        }

        print("✅ NS-only glucose backfill completed.")
    }

    /// Ensure that we have performed the large initial NS-only backfill once (90 days).
    private func ensureInitialBackfill() async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: initialBackfillFlagKey) {
            return
        }

        await backfillLastDays(initialBackfillDays)
        defaults.set(true, forKey: initialBackfillFlagKey)
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
        // Top horizontal row: date picker + spacer + stats label
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let topRow = UIStackView(arrangedSubviews: [datePicker, spacer, statsLabel])
        topRow.axis = .horizontal
        topRow.spacing = 6
        topRow.alignment = .center

        // Full header: top row + segmented control stacked vertically
        let headerStack = UIStackView(arrangedSubviews: [topRow, modeSegmentedControl])
        headerStack.axis = .vertical
        headerStack.spacing = 6
        headerStack.alignment = .fill
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.tag = 999 // so we can find it in constraints
        view.addSubview(headerStack)

        datePicker.setContentHuggingPriority(.required, for: .horizontal)
        datePicker.setContentCompressionResistancePriority(.required, for: .horizontal)
        datePicker.heightAnchor.constraint(equalToConstant: 30).isActive = true
        datePicker.widthAnchor.constraint(lessThanOrEqualToConstant: 105).isActive = true

        statsLabel.text = "CGM –" // placeholder until data loads

        modeSegmentedControl.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
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
            headerStack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -8),

            tableView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Loading

    /// Normalizes and merges BG entries by timestamp, removes duplicates, and sorts. No gap-fill.
    private func normalizedMergedBG(existing: [BGEntry], new: [BGEntry]) -> [BGEntry] {
        let cal = Calendar.current
        var merged: [TimeInterval: BGEntry] = [:]

        for e in existing {
            merged[e.date.timeIntervalSince1970] = e
        }
        for e in new {
            merged[e.date.timeIntervalSince1970] = e
        }

        // No gap‑fill in GlucoseView — only merge & sort
        let sorted = merged.values.sorted { $0.date < $1.date }
        return sorted
    }

    /// Deduplicate BG entries within time buckets of the given size (in seconds).
    /// If multiple readings fall into the same bucket, keep the newest one.
    private func dedupeToBuckets(_ entries: [BGEntry], bucketSeconds: TimeInterval) -> [BGEntry] {
        var byBucket: [Int: BGEntry] = [:]

        for entry in entries {
            let ts = entry.date.timeIntervalSince1970
            // Bucket window index since 1970‑01‑01
            let bucket = Int(floor(ts / bucketSeconds))

            if let existing = byBucket[bucket] {
                // Keep the newer reading within the same bucket
                if entry.date > existing.date {
                    byBucket[bucket] = entry
                }
            } else {
                byBucket[bucket] = entry
            }
        }

        return byBucket.values.sorted { $0.date < $1.date }
    }

    /// Load BG for a calendar day using both datasets, then drive the UI from the selected mode.
    /// - NS-only: Uses GlucoseNSOnlyCache (Trio → Nightscout uploads only).
    ///   For today, we first refresh the NS-only cache from Nightscout for [startOfDay, now].
    /// - All-values: Uses NightscoutCache (Dexcom+Nightscout merged BG history).
    private func loadBG(for date: Date) {
        let cal = Calendar.current
        let now = Date()

        showRefreshIndicator()

        let start = cal.startOfDay(for: date)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: start) else {
            hideRefreshIndicator()
            return
        }

        Task {
            // Expand the cache window with a ±12h buffer around the day
            let bufferedStart = cal.date(byAdding: .hour, value: -12, to: start) ?? start
            let bufferedEnd   = cal.date(byAdding: .hour, value: 12, to: endOfDay) ?? endOfDay

            // --- NS-only dataset ---
            if cal.isDate(date, inSameDayAs: now) {
                let sgvBatch = await NightscoutUtils.fetchSGVWindow(from: start, to: now)
                if !sgvBatch.isEmpty {
                    GlucoseNSOnlyCache.mergeSGVBatch(sgvBatch)
                }
            }

            let nsOnlySGV = await GlucoseNSOnlyCache.loadWindow(from: bufferedStart, to: bufferedEnd)
            let nsOnlyRaw: [BGEntry] = nsOnlySGV
                .map {
                    BGEntry(
                        date: Date(timeIntervalSince1970: $0.date),
                        mmol: Double($0.sgv) / 18.0182
                    )
                }
                .filter { $0.date >= start && $0.date < endOfDay }
            let nsOnlyDay = self.dedupeToBuckets(nsOnlyRaw, bucketSeconds: 300.0)

            // --- All-values dataset (Dex+NS merged cache) ---
            let (allSGV, _) = await NightscoutCache.loadWindow(from: bufferedStart, to: bufferedEnd)
            let allRaw: [BGEntry] = allSGV
                .map {
                    BGEntry(
                        date: Date(timeIntervalSince1970: $0.date),
                        mmol: Double($0.sgv) / 18.0182
                    )
                }
                .filter { $0.date >= start && $0.date < endOfDay }
            let allDay = self.dedupeToBuckets(allRaw, bucketSeconds: 240.0)

            await MainActor.run {
                // Cache both datasets for the selected day so that gap analysis
                // can cross-reference them when deciding missing reasons.
                self.nsOnlyDayEntries = nsOnlyDay
                self.allValuesDayEntries = allDay

                // Aktiva värden till tabellen utifrån valt läge.
                switch self.dataMode {
                case .nsOnly:
                    self.bgEntries = nsOnlyDay
                case .allValues:
                    self.bgEntries = allDay
                }

                self.tableView.reloadData()
                self.updateStatsLabel()
                self.hideRefreshIndicator()
            }
        }
    }

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        dataMode = sender.selectedSegmentIndex == 0 ? .allValues : .nsOnly
        loadBG(for: selectedDate)
        updateStatsLabel()
    }

    private func showRefreshIndicator() {
        guard reloadIndicator == nil, let reloadButton = reloadButton else { return }

        let ind = UIActivityIndicatorView(style: .medium)
        ind.startAnimating()
        reloadIndicator = ind

        let indicatorItem = UIBarButtonItem(customView: ind)

        if var items = navigationItem.leftBarButtonItems {
            if let idx = items.firstIndex(of: reloadButton) {
                items[idx] = indicatorItem
                navigationItem.leftBarButtonItems = items
            }
        }
    }

    private func hideRefreshIndicator() {
        guard let reloadButton = reloadButton else { return }

        if let ind = reloadIndicator {
            ind.stopAnimating()
            reloadIndicator = nil
        }

        if var items = navigationItem.leftBarButtonItems {
            // Replace indicator with reload button
            if let idx = items.firstIndex(where: { ($0.customView as? UIActivityIndicatorView) != nil }) {
                items[idx] = reloadButton
                navigationItem.leftBarButtonItems = items
            }
        }
    }
    
    private func updateStatsLabel() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else {
            statsLabel.text = "CGM-värden: –"
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
        // Hantera lägen där inga värden missats ännu, och de sekunder mellan att ett cgm-värde kommit in och 5 min indelningen av dygnets timmar ger en diff (ex cgm värden kommer minut:sekund 02:30, 07:30, 12:30 osv. expectedCOunt utgår från 05:00, 10:00, 15:00. Det gör at cgm % blir högre än 100% mellan minut:sekund 02:30-05:00, 07:30-10:00, 12:30-15:00 osv utan denna expectedCOuntAdjusted-fix
        var expectedCountAdjusted: Int
        if actualCount > expectedCount {
            expectedCountAdjusted = actualCount
        } else {
            expectedCountAdjusted = expectedCount
        }

        // If there is at least one missing reading for the day, make sure we never show 100% coverage
        // during the current 5‑min window while expectedCount has not yet “caught up”.
        let missingCount = dayRowsIncludingMissing.filter { $0.isMissing }.count
        if missingCount > 0 && expectedCountAdjusted == expectedCount {
            expectedCountAdjusted += 1
        }

        let pct = expectedCountAdjusted > 0 ? Int(round(Double(actualCount) / Double(expectedCountAdjusted) * 100.0)) : 0
        var emoji = " 🔴"
        if pct > 95 {
            emoji = " 🟢"
        } else if pct > 90 {
            emoji = " 🟡"
        }
        statsLabel.text = "CGM-värden:  \(actualCount)/\(expectedCount)  \(pct)%" + emoji
    }

    @objc private func dateChanged(_ sender: UIDatePicker) {
        selectedDate = sender.date
        loadBG(for: selectedDate)
        updateStatsLabel()
    }

    // MARK: - Trio Decision Popup for BG Points

    /// Hämtar Trio-beslutsreason för en BG-timestamp och visar som alert.
    private func showTrioDecisionAlert(for timestamp: TimeInterval, onDismiss: @escaping () -> Void) {
        let bgDate = Date(timeIntervalSince1970: timestamp)
        let adjustedTimestamp = bgDate.addingTimeInterval(180)

        NightscoutUtils.fetchDeviceStatusReasonBeforeTimestamp(timestamp: adjustedTimestamp) { [weak self] result in
            guard let self = self else { return }

            let handler = { (_: UIAlertAction) in
                onDismiss()
            }

            switch result {
            case .success(let reason):
                let formattedReason = self.formatGraphReason(reason)
                let alert = UIAlertController(
                    title: "Trio behandlingsbeslut",
                    message: formattedReason,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: handler))
                self.present(alert, animated: true, completion: nil)

            case .failure(let error):
                let alert = UIAlertController(
                    title: "Fel",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: handler))
                self.present(alert, animated: true, completion: nil)
            }
        }
    }

    /// Formatterar reason-strängen ungefär som i MainView/Graphs för BG-popupen.
    private func formatGraphReason(_ reason: String) -> String {
        var formatted = reason

        // 1. Hantera AF och SMB Ratio innan övriga ersättningar.
        let patternAFSMB = "AF:\\s([0-9]\\.[0-9]{1,2})(?:,\\sSMB Ratio:\\s([0-9]\\.[0-9]{1,2}))?;"
        if let regexAFSMB = try? NSRegularExpression(pattern: patternAFSMB, options: []) {
            let range = NSRange(location: 0, length: formatted.utf16.count)
            let matches = regexAFSMB.matches(in: formatted, options: [], range: range)
            for match in matches.reversed() {
                let fullRange = match.range(at: 0)
                let afValue = (formatted as NSString).substring(with: match.range(at: 1))
                var replacement = "AF: \(afValue)\n"
                if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                    let smbValue = (formatted as NSString).substring(with: match.range(at: 2))
                    if !smbValue.isEmpty {
                        replacement += "• SMB Ratio: \(smbValue)\n"
                    }
                }
                replacement += "\n👉  OREF SLUTSATS:\n•"
                formatted = (formatted as NSString).replacingCharacters(in: fullRange, with: replacement)
            }
        }

        // 2. Byt alla kommatecken mot radbrytning + punktlista.
        formatted = formatted.replacingOccurrences(of: ",", with: "\n•")

        // 3. Mer specifika ersättningar.
        formatted = formatted.replacingOccurrences(of: "SMB INAKTIVERADE!", with: "SMB Inaktiverade 🚫")
        formatted = formatted.replacingOccurrences(of: "Mikrobolus:", with: "🔹 Mikrobolus:")
        formatted = formatted.replacingOccurrences(of: ". ;", with: "\n• ")
        formatted = formatted.replacingOccurrences(of: "E. ", with: "E\n")
        formatted = formatted.replacingOccurrences(of: "U. ", with: "E\n")
        formatted = formatted.replacingOccurrences(of: "E/h. ", with: "E/h\n")
        formatted = formatted.replacingOccurrences(of: "temp.", with: "temp.\n")
        formatted = formatted.replacingOccurrences(of: ". ", with: "")
        formatted = formatted.replacingOccurrences(of: "; ", with: "\n• ")

        // 4. Ersätt "TDD: <number> U" med kompakt variant.
        if let regexTDD = try? NSRegularExpression(pattern: "TDD:\\s(\\d+(?:\\.\\d{1,2})?)\\sU", options: []) {
            let range = NSRange(location: 0, length: formatted.utf16.count)
            formatted = regexTDD.stringByReplacingMatches(
                in: formatted,
                options: [],
                range: range,
                withTemplate: "TDD: $1E"
            )
        }

        // 5. HTML-encodeade < och >.
        formatted = formatted.replacingOccurrences(of: "&lt;", with: "<")
        formatted = formatted.replacingOccurrences(of: "&gt;", with: ">")

        return formatted
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

        case .missing(let date, let reason):
            // Detect placeholder: no actual missing rows and showOnlyMissingGlucose = true
            let isPlaceholder = showOnlyMissingGlucose && dayRowsIncludingMissing.filter { $0.isMissing }.isEmpty
            if isPlaceholder {
                cell.textLabel?.text = "Inga saknade värden denna dag 👍"
                cell.detailTextLabel?.text = ""
                cell.textLabel?.font = .systemFont(ofSize: 17)
                let tint = UIColor.systemGreen.withAlphaComponent(0.12)
                cell.backgroundColor = tint
                cell.contentView.backgroundColor = tint
            } else {
                switch reason {
                case .sensor:
                    cell.textLabel?.text = "[Sensoravläsning saknas]"
                    cell.backgroundColor = UIColor.systemRed.withAlphaComponent(0.15)
                    cell.contentView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.15)
                case .trioUpload:
                    cell.textLabel?.text = "[Trio uppladdning saknas]"
                    cell.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
                    cell.contentView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
                }
                cell.textLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
                cell.detailTextLabel?.text = timeFormatter.string(from: date)

            }
        }

        cell.accessoryType = .none
        cell.selectionStyle = .default
        return cell
    }

    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = filteredRows[indexPath.row]
        switch row {
        case .glucose(let entry):
            let timestamp = entry.date.timeIntervalSince1970
            showTrioDecisionAlert(for: timestamp) {
                DispatchQueue.main.async {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            }
        case .missing(_, _):
            DispatchQueue.main.async {
                tableView.deselectRow(at: indexPath, animated: true)
            }
        }
    }
}
