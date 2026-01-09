//
//  GlucoseView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-11-22.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import UIKit
import Charts

/// Table-style glucose log, similar look/feel to TreatmentsTableView.
final class GlucoseView: ThemedViewController, UITableViewDataSource, UITableViewDelegate {

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
    
    // Throttle so we don’t fetch on every quick appear (e.g. during navigation)
    private var lastNSOnly24hRefreshAt: Date?
    private let nsOnly24hRefreshMinInterval: TimeInterval = 60 // seconds

    // UI
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let datePicker: UIDatePicker = {
        let dp = UIDatePicker()
        dp.datePickerMode = .date
        dp.preferredDatePickerStyle = .compact
        dp.translatesAutoresizingMaskIntoConstraints = false
        dp.locale = Locale(identifier: "sv_SE")
        return dp
    }()

    private let modeSegmentedControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Alla värden", "Uppladdningar Trio ⇢ NS"])
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
        title = "Glukoslogg"
        //view.backgroundColor = .systemBackground
        updateBackgroundForCurrentMode()

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
        //GlucoseNSOnlyCache.debugListSegments()
        //print("GlucoseNSOnlyCache dir:", GlucoseNSOnlyCache.dir.path)

        // Initial NS-only backfill (90 days) + initial load for today from NS cache
        Task {
            await self.ensureInitialBackfill()
            await MainActor.run {
                self.loadBG(for: self.selectedDate)
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        Task {
            // Always keep NS-only cache fresh for last 24h when opening the view
            await refreshNSOnlyCacheRecent(hours: 24)

            await MainActor.run {
                // Reload current day so labels/SAKNAS reasons are correct immediately
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
        /*
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
*/
        let filter = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            style: .plain,
            target: self,
            action: #selector(toggleMissingOnly)
        )
        filter.tintColor = .label
        
        navigationItem.leftBarButtonItems = [reload, filter]
        
        // Optional close button to mirror other modal logs
        let done = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(doneTapped)
        )
/*
        let filter = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            style: .plain,
            target: self,
            action: #selector(toggleMissingOnly)
        )
        filter.tintColor = .label
*/
        let info = UIBarButtonItem(
            image: UIImage(systemName: "chart.bar.xaxis.ascending"),
            style: .plain,
            target: self,
            action: #selector(showGlucoseStats)
        )
        info.tintColor = .label
        
        //navigationItem.rightBarButtonItems = [done, info, filter]

        navigationItem.rightBarButtonItems = [done, info]
    }

    @objc private func doneTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func showGlucoseStats() {
        let statsVC = GlucoseStatsViewController()
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

        //if let filterButton = navigationItem.rightBarButtonItems?.last {
        if let filterButton = navigationItem.leftBarButtonItems?.last {
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
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.isOpaque = false
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
    
    /// Refresh NS-only cache for the most recent window (default 24h).
    /// This makes sure Trio→NS gaps are up-to-date as soon as the view is opened.
    private func refreshNSOnlyCacheRecent(hours: Int = 24) async {
        let now = Date()

        // Throttle
        if let last = lastNSOnly24hRefreshAt, now.timeIntervalSince(last) < nsOnly24hRefreshMinInterval {
            return
        }
        lastNSOnly24hRefreshAt = now

        let start = now.addingTimeInterval(-TimeInterval(hours) * 3600)

        let sgvBatch = await NightscoutUtils.fetchSGVWindow(from: start, to: now)
        if !sgvBatch.isEmpty {
            GlucoseNSOnlyCache.mergeSGVBatch(sgvBatch)
            GlucoseNSOnlyCache.purgeOldFiles()
        }
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
    
    /// Expected number of 5-min glucose slots for a given calendar day.
    /// Handles DST transitions (23h/25h days) by using the actual local day length.
    private func expectedSlots(for day: Date, upTo now: Date? = nil) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return 288 }

        // If an upper bound is provided (e.g. "today"), clamp within the day.
        let upper = min(now ?? end, end)
        let seconds = max(0, upper.timeIntervalSince(start))

        // 5-min buckets
        return max(1, Int(floor(seconds / 300.0)))
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
            expectedCount = expectedSlots(for: selectedDate, upTo: now)
        } else {
            expectedCount = expectedSlots(for: selectedDate)
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

        // Ensure selection overlay renders over our gradient (avoid iOS 14+ backgroundConfiguration overriding)
        if #available(iOS 14.0, *) {
            cell.backgroundConfiguration = nil
        }

        // Match Treatments-style selection highlight (subtle overlay over the gradient)
        cell.selectionStyle = .default
        let selected = UIView()
        selected.backgroundColor = UIColor.label.withAlphaComponent(0.2)
        selected.layer.cornerRadius = 10
        selected.layer.masksToBounds = true
        cell.selectedBackgroundView = selected

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

// MARK: - Glucose Stats (All values vs Trio→NS)

final class GlucoseStatsViewController: ThemedTableViewController {

    // Match LowTreatmentsStatsViewController: insetGrouped gives the rounded light-gray cards
    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Full 90d dataset (oldest → newest)
    private var allDays: [Date] = []
    private var allCountsAllValues: [Int] = []
    private var allCountsNSOnly: [Int] = []

    // Current selection
    private var selectedDays: [Date] = []
    private var selectedCountsAllValues: [Int] = []
    private var selectedCountsNSOnly: [Int] = []

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

    private var selectedPeriod: PeriodOption = .d7

    private lazy var periodControl: UISegmentedControl = {
        let items = PeriodOption.allCases.map { $0.title }
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = PeriodOption.allCases.firstIndex(of: selectedPeriod) ?? 2
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
        v.maxVisibleCount = 1_000_000
        return v
    }()

    private let dfAxis: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "dd/MM"
        return df
    }()

    private let dfISO: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        updateBackgroundForCurrentMode()
        tableView.backgroundColor = .clear
        tableView.backgroundView = tableView.backgroundView
        tableView.isOpaque = false
        tableView.layer.backgroundColor = UIColor.clear.cgColor
        title = "Glukosstatistik"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissSelf)
        )

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "GlucoseStatsCell")

        setupChartHeader()
        loadDataAndApplyInitialPeriod()
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    // MARK: - Data loading

    private func loadDataAndApplyInitialPeriod() {
        Task {
            let cal = Calendar.current
            let now = Date()

            // Up to 90 days (align with cache retention if smaller)
            let daysBack = min(NightscoutCache.retentionDays, 90)

            guard let startDay = cal.date(byAdding: .day, value: -(daysBack - 1), to: cal.startOfDay(for: now)) else {
                await MainActor.run {
                    self.applyPeriod(self.selectedPeriod)
                }
                return
            }

            // Build all days list (oldest → newest)
            var days: [Date] = []
            days.reserveCapacity(daysBack)
            for offset in 0..<daysBack {
                if let d = cal.date(byAdding: .day, value: offset, to: startDay) {
                    days.append(cal.startOfDay(for: d))
                }
            }

            // Load datasets
            let (allSGV, _) = await NightscoutCache.loadWindow(from: startDay, to: now)
            let nsOnlySGV = await GlucoseNSOnlyCache.loadWindow(from: startDay, to: now)

            // Count unique readings per day using bucket dedupe
            let countsAllValuesByDay = self.countsByDayFromSGVJSON(allSGV, bucketSeconds: 240.0)
            let countsNSOnlyByDay = self.countsByDayFromSGVJSON(nsOnlySGV, bucketSeconds: 300.0)

            var countsAll: [Int] = []
            var countsNS: [Int] = []
            countsAll.reserveCapacity(days.count)
            countsNS.reserveCapacity(days.count)

            for day in days {
                countsAll.append(countsAllValuesByDay[day] ?? 0)
                countsNS.append(countsNSOnlyByDay[day] ?? 0)
            }

            await MainActor.run {
                self.allDays = days
                self.allCountsAllValues = countsAll
                self.allCountsNSOnly = countsNS

                // Apply initial period
                self.applyPeriod(self.selectedPeriod)
            }
        }
    }

    /// Counts unique readings per day by bucketing timestamps.
    private func countsByDayFromSGVJSON(_ sgvs: [SGVJSON], bucketSeconds: TimeInterval) -> [Date: Int] {
        let cal = Calendar.current
        var bucketsByDay: [Date: Set<Int>] = [:]

        for e in sgvs {
            let date = Date(timeIntervalSince1970: e.date)
            let dayStart = cal.startOfDay(for: date)
            let bucket = Int(floor(date.timeIntervalSince1970 / bucketSeconds))
            bucketsByDay[dayStart, default: []].insert(bucket)
        }

        var counts: [Date: Int] = [:]
        counts.reserveCapacity(bucketsByDay.count)
        for (day, set) in bucketsByDay {
            counts[day] = set.count
        }
        return counts
    }

    // MARK: - Period selection

    private func applyPeriod(_ period: PeriodOption) {
        selectedPeriod = period
        let total = allDays.count
        guard total > 0 else {
            selectedDays = []
            selectedCountsAllValues = []
            selectedCountsNSOnly = []
            chartView.data = nil
            tableView.reloadData()
            return
        }

        let n = min(period.days, total)
        let startIndex = max(0, total - n)

        selectedDays = Array(allDays[startIndex..<total])
        selectedCountsAllValues = Array(allCountsAllValues[startIndex..<total])
        selectedCountsNSOnly = Array(allCountsNSOnly[startIndex..<total])

        loadChartData()
        tableView.reloadData()
    }

    @objc private func periodChanged(_ sender: UISegmentedControl) {
        let index = sender.selectedSegmentIndex
        guard index >= 0 && index < PeriodOption.allCases.count else { return }
        applyPeriod(PeriodOption.allCases[index])
    }

    // MARK: - Chart header

    private func setupChartHeader() {
        let container = UIView()
        container.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 330)
        container.backgroundColor = .clear

        container.addSubview(periodControl)
        container.addSubview(chartView)

        periodControl.translatesAutoresizingMaskIntoConstraints = false
        chartView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            periodControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            periodControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            periodControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            chartView.topAnchor.constraint(equalTo: periodControl.bottomAnchor, constant: 12),
            chartView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            chartView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            chartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])

        tableView.tableHeaderView = container
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let header = tableView.tableHeaderView {
            let targetSize = CGSize(width: tableView.bounds.width, height: 330)
            if header.frame.size != targetSize {
                header.frame.size = targetSize
                tableView.tableHeaderView = header
            }
        }
    }

    private func loadChartData() {
        guard selectedDays.count == selectedCountsAllValues.count,
              selectedDays.count == selectedCountsNSOnly.count,
              !selectedDays.isEmpty
        else {
            chartView.data = nil
            chartView.setNeedsDisplay()
            return
        }

        let n = selectedDays.count
        let expectedPerDay = expectedCountsForSelectedDays()

        var entriesAll: [BarChartDataEntry] = []
        var entriesNS: [BarChartDataEntry] = []
        entriesAll.reserveCapacity(n)
        entriesNS.reserveCapacity(n)

        for i in 0..<n {
            let expected = Double(expectedPerDay[i])
            let pctAll = min(100.0, max(0.0, Double(selectedCountsAllValues[i]) / expected * 100.0))
            let pctNS  = min(100.0, max(0.0, Double(selectedCountsNSOnly[i]) / expected * 100.0))
            entriesAll.append(BarChartDataEntry(x: Double(i), y: pctAll))
            entriesNS.append(BarChartDataEntry(x: Double(i), y: pctNS))
        }

        let dsAll = BarChartDataSet(entries: entriesAll, label: "Alla värden")
        dsAll.setColor(UIColor(
            red: 76.0/255.0,
            green: 179.0/255.0,
            blue: 72.0/255.0,
            alpha: 1.0
        ))
        
        dsAll.drawValuesEnabled = false
        dsAll.barBorderColor = .black
        dsAll.barBorderWidth = 0.5

        let dsNS = BarChartDataSet(entries: entriesNS, label: "Uppladdningar Trio ⇢ NS")
        dsNS.setColor(UIColor.systemPurple.withAlphaComponent(0.7))
        dsNS.drawValuesEnabled = false
        dsNS.barBorderColor = .black
        dsNS.barBorderWidth = 0.5

        let data = BarChartData(dataSets: [dsAll, dsNS])

        // Grouped bars (two per day)
        let groupSpace = 0.20
        let barSpace = 0.05
        let barWidth = (1.0 - groupSpace) / 2.0 - barSpace
        data.barWidth = barWidth

        // Configure X axis for grouping
        let xAxis = chartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.granularityEnabled = true
        xAxis.granularity = 1
        xAxis.centerAxisLabelsEnabled = true

        let labels = selectedDays.map { dfAxis.string(from: $0) }
        xAxis.valueFormatter = IndexAxisValueFormatter(values: labels)
        xAxis.setLabelCount(min(6, labels.count), force: false)

        // Y axis: cropped to 70–100 % for better day-to-day resolution
        let yAxis = chartView.leftAxis
        yAxis.axisMinimum = 70
        yAxis.axisMaximum = 100
        yAxis.granularityEnabled = true
        yAxis.granularity = 5
        yAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
            String(format: "%.0f%%", value)
        }

        chartView.rightAxis.enabled = false

        chartView.data = data

        // Make groups start at x = 0
        chartView.xAxis.axisMinimum = 0
        chartView.xAxis.axisMaximum = Double(n)
        data.groupBars(fromX: 0, groupSpace: groupSpace, barSpace: barSpace)

        // Light grid for readability (same vibe as BGCheck)
        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.5)
        xAxis.gridColor = gridLineColor
        xAxis.gridLineWidth = 0.5
        xAxis.gridLineDashLengths = [2, 2]

        yAxis.gridColor = gridLineColor
        yAxis.gridLineWidth = 0.5
        yAxis.gridLineDashLengths = [2, 2]

        // --- Legend configuration ---
        chartView.legend.enabled = true
        let legend = chartView.legend
        legend.horizontalAlignment = .center
        legend.verticalAlignment = .bottom
        legend.orientation = .horizontal
        legend.drawInside = false
        legend.form = .square
        legend.formSize = 10
        legend.xEntrySpace = 12
        legend.yOffset = 8
        // Lite extra luft mellan plot-ytan och legend (yOffset påverkar inte alltid layouten)
        chartView.extraBottomOffset = 4

        chartView.notifyDataSetChanged()
        chartView.setNeedsDisplay()
    }

    // MARK: - Expected counts helper

    private func expectedCount(for day: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return 288 }

        // For today, only count expected slots up to now (clamped within the day).
        let upper: Date
        if cal.isDateInToday(day) {
            upper = min(Date(), end)
        } else {
            upper = end
        }

        let seconds = max(0, upper.timeIntervalSince(start))
        return max(1, Int(floor(seconds / 300.0)))
    }

    private func expectedCountsForSelectedDays() -> [Int] {
        selectedDays.map { expectedCount(for: $0) }
    }

    // MARK: - Stats table

    private enum Row: Int, CaseIterable {
        case avgAllPct
        case avgMissedAllPerDay
        case avgTrioPct
        case avgMissedTrioPerDay
        case avgMinutesWithoutAll
        case bestAllDay
        case worstAllDay
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    private func percentString(_ value: Double) -> String {
        String(format: "%.0f %%", value)
    }

    private func countString(_ value: Double) -> String {
        // keep one decimal if needed
        if abs(value.rounded() - value) < 0.001 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func avg(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "GlucoseStatsCell")
        cell.selectionStyle = .none
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.backgroundView = nil
        if #available(iOS 14.0, *) {
            var bg = UIBackgroundConfiguration.clear()
            bg.backgroundColor = .systemGray.withAlphaComponent(0.1)
            cell.backgroundConfiguration = bg
        }
        cell.textLabel?.backgroundColor = .clear
        cell.detailTextLabel?.backgroundColor = .clear

        let row = Row(rawValue: indexPath.row)!

        let expectedPerDay = expectedCountsForSelectedDays()

        let totalExpected = Double(expectedPerDay.reduce(0, +))
        let totalAll = Double(selectedCountsAllValues.reduce(0, +))
        let totalNS  = Double(selectedCountsNSOnly.reduce(0, +))

        let avgAllPct = totalExpected > 0 ? (totalAll / totalExpected * 100.0) : 0
        let avgNSPct  = totalExpected > 0 ? (totalNS / totalExpected * 100.0) : 0

        let missedAllPerDay = zip(selectedCountsAllValues, expectedPerDay)
            .map { Double(max(0, $1 - $0)) }

        let missedNSPerDay = zip(selectedCountsNSOnly, expectedPerDay)
            .map { Double(max(0, $1 - $0)) }

        let avgMissAll = avg(missedAllPerDay)
        let avgMissNS  = avg(missedNSPerDay)

        let avgMinutesNoAll = avgMissAll * 5.0

        // Best/worst day for "All values"
        var bestPct: Double = 0
        var bestDate: Date?
        var worstPct: Double = 101
        var worstDate: Date?

        for (i, day) in selectedDays.enumerated() {
            let expected = Double(expectedPerDay[i])
            guard expected > 0 else { continue }

            let pct = Double(selectedCountsNSOnly[i]) / expected * 100.0
            if pct > bestPct {
                bestPct = pct
                bestDate = day
            }
            if pct < worstPct {
                worstPct = pct
                worstDate = day
            }
        }

        switch row {
        case .avgAllPct:
            cell.textLabel?.text = "Medel BG-värden (Alla)"
            cell.detailTextLabel?.text = percentString(avgAllPct)

        case .avgMissedAllPerDay:
            cell.textLabel?.text = "Medel missade BG-värden/dag"
            cell.detailTextLabel?.text = "\(countString(avgMissAll)) st"
            
        case .avgTrioPct:
            cell.textLabel?.text = "Medel BG-uppladdningar (Trio)"
            cell.detailTextLabel?.text = percentString(avgNSPct)

        case .avgMissedTrioPerDay:
            cell.textLabel?.text = "Medel missade uppladdningar/dag"
            cell.detailTextLabel?.text = "\(countString(avgMissNS)) st"

        case .avgMinutesWithoutAll:
            cell.textLabel?.text = "Medel tid/dag utan BG-värden"
            cell.detailTextLabel?.text = "\(countString(avgMinutesNoAll)) min"

        case .bestAllDay:
            cell.textLabel?.text = "Bästa dag Trio->NS"
            if let d = bestDate {
                cell.detailTextLabel?.text = "\(percentString(bestPct)) • \(dfISO.string(from: d))"
            } else {
                cell.detailTextLabel?.text = "–"
            }

        case .worstAllDay:
            cell.textLabel?.text = "Sämsta dag Trio->NS"
            if let d = worstDate {
                cell.detailTextLabel?.text = "\(percentString(worstPct)) • \(dfISO.string(from: d))"
            } else {
                cell.detailTextLabel?.text = "–"
            }
        }

        return cell
    }
}
