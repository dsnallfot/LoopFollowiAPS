//
//  GlucoseView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-11-22.

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
        case sensorErrors   // Dexcom sensor error Notes (90d list)
    }

    /// Why a 5‑min slot is missing.
    private enum MissingReason {
        case sensor       // Sensor never produced a reading (missing in both datasets)
        case trioUpload   // Trio/NS upload missing, but sensor (Dexcom) has the value
    }

    private var dataMode: GlucoseDataMode = .nsOnly
    
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
        let sc = UISegmentedControl(items: ["Dexcomvärden", "Trio ⇢ NS", "Sensorfel"])
        sc.selectedSegmentIndex = 1
        sc.translatesAutoresizingMaskIntoConstraints = false
        return sc
    }()

    private var activityIndicator: UIActivityIndicatorView?

    // Toggle to show only missing rows
    private var showOnlyMissingGlucose: Bool = false

    // Sensor error rows (90 days)
    private var sensorErrorRows: [GlucoseRow] = []
    private let sensorErrorLookbackDays: Int = 90
    private let sensorErrorCacheRowsKey = "GlucoseViewSensorErrorCacheRows"
    private let sensorErrorCacheLastRefreshKey = "GlucoseViewSensorErrorCacheLastRefresh"

    private struct SensorErrorCacheItem: Codable {
        var id: String?
        var noteTimestamp: TimeInterval
        var durationMinutes: Int
        var notes: String?
        var enteredBy: String?
    }

    /// Row model for the table
    private enum GlucoseRow {
        case glucose(BGEntry)
        case missing(Date, MissingReason)
        case sensorError(date: Date, durationMinutes: Int, note: Treatment)

        var date: Date {
            switch self {
            case .glucose(let e): return e.date
            case .missing(let d, _): return d
            case .sensorError(let d, _, _): return d
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
        if dataMode == .sensorErrors { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }

        let baseEntries: [BGEntry]
        switch dataMode {
        case .allValues:
            baseEntries = allValuesDayEntries
        case .nsOnly:
            baseEntries = nsOnlyDayEntries
        case .sensorErrors:
            return []
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

    /// Determines which rows are shown when the filter button (line.3.horizontal.decrease.circle) is enabled.
    /// Includes:
    /// - all missing rows
    /// - glucose rows that are "special" (🦄, 🆘, ⚠️)
    private func shouldIncludeWhenFiltered(_ row: GlucoseRow) -> Bool {
        switch row {
        case .missing:
            // Always keep missing rows
            return true

        case .glucose(let entry):
            // 🦄 Unicorn = exactly 5.5 mmol/L (≈ 100 mg/dL)
            if abs(entry.mmol - 5.5) < 0.02 { return true }
            // 🆘 Very low marker ~2.2 mmol/L
            if abs(entry.mmol - 2.2) < 0.04 { return true }
            // ⚠️ Very high marker ~22.2 mmol/L
            if abs(entry.mmol - 22.2) < 0.04 { return true }
            return false

        case .sensorError:
            // Sensorfel-läget har egen vy och hanteras separat
            return false
        }
    }

    private var filteredRows: [GlucoseRow] {
        if dataMode == .sensorErrors {
            return sensorErrorRows
        }

        let rows = dayRowsIncludingMissing
        if showOnlyMissingGlucose {
            // Visa alla saknade rader + "intressanta" värden (🦄, 🆘, ⚠️)
            let hits = rows.filter { shouldIncludeWhenFiltered($0) }

            if hits.isEmpty {
                // Insert a synthetic placeholder missing row at noon
                let cal = Calendar.current
                let start = cal.startOfDay(for: selectedDate)
                let placeholderDate = cal.date(byAdding: .hour, value: 12, to: start) ?? start
                return [.missing(placeholderDate, .sensor)]
            }
            return hits
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
        title = "Glukos"
        //view.backgroundColor = .systemBackground
        updateBackgroundForCurrentMode()

        // Default to Trio → Nightscout uploads when opening this modal
        dataMode = .nsOnly
        modeSegmentedControl.selectedSegmentIndex = 1

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
        // När GlucoseView är root i sin navigation stack (egen UINavigationController)
        // så är vi i modalt läge. När vi är pushade från SettingsVC är vi inte root.
        let isModalRoot = navigationController?.viewControllers.first === self

        let reload = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshButtonTapped)
        )
        self.reloadButton = reload

        if isModalRoot {
            // Modalt: bara reload + filter på vänster sida
            navigationItem.leftBarButtonItems = [reload]
        } else {
            // Pushat från Settings: behåll back-knappen och supplementera med reload + filter
            navigationItem.leftItemsSupplementBackButton = true
            navigationItem.leftBarButtonItems = [reload]
        }

        // Optional close button to mirror other modal logs
        let done = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(doneTapped)
        )

        let info = UIBarButtonItem(
            image: UIImage(systemName: "chart.bar.xaxis.ascending"),
            style: .plain,
            target: self,
            action: #selector(showGlucoseStats)
        )
        info.tintColor = .label
        
        let filter = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            style: .plain,
            target: self,
            action: #selector(toggleMissingOnly)
        )
        filter.tintColor = .label

        if isModalRoot {
            // Modalt: visa både Klar och statistik
            navigationItem.rightBarButtonItems = [done, info, filter]
        } else {
            // Pushat: ingen Klar-knapp, bara statistik
            navigationItem.rightBarButtonItems = [info, filter]
        }
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
        statsLabel.heightAnchor.constraint(equalToConstant: 30).isActive = true

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
                case .sensorErrors:
                    // Sensorfel-läget använder egen datakälla (sensorErrorRows)
                    self.bgEntries = []
                }

                self.tableView.reloadData()
                self.updateStatsLabel()
                self.hideRefreshIndicator()
            }
        }
    }

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            dataMode = .allValues
        case 1:
            dataMode = .nsOnly
        default:
            dataMode = .sensorErrors
        }

        // UI tweaks for Sensorfel mode
        let isSensorErrors = (dataMode == .sensorErrors)
        datePicker.isHidden = isSensorErrors

        if let filterButton = navigationItem.leftBarButtonItems?.last {
            if isSensorErrors {
                // När vi går in i Sensorfel-läget: nollställ filtret och inaktivera knappen.
                showOnlyMissingGlucose = false
                filterButton.isEnabled = false
                filterButton.image = UIImage(systemName: "line.3.horizontal.decrease.circle")
                filterButton.tintColor = .secondaryLabel
            } else {
                // I de två andra lägena (Dexcomvärden / Trio ⇢ NS):
                // behåll showOnlyMissingGlucose-state och återspegla den i ikonen.
                filterButton.isEnabled = true
                let name = showOnlyMissingGlucose
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
                filterButton.image = UIImage(systemName: name)
                filterButton.tintColor = showOnlyMissingGlucose ? .systemBlue : .label
            }
        }

        if isSensorErrors {

            // Visa cached lista direkt (instant)
            let cached = loadSensorErrorRowsFromCache()
            if !cached.isEmpty {
                sensorErrorRows = cached.sorted { $0.date > $1.date }
                tableView.reloadData()
                updateStatsLabel()
            }

            showRefreshIndicator()
            Task {
                await self.loadSensorErrors90Days()
            }

        } else {
            loadBG(for: selectedDate)
            updateStatsLabel()
        }
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
        if dataMode == .sensorErrors {
            statsLabel.text = "Sensorfel: \(sensorErrorRows.count) st"
            return
        }
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
    
    /// Visar sensorstatus / Dexcom-noteringar som förklaring till saknade värden.
    /// Letar efter en Nightscout-treatment av typen "Note".
    /// För sensor-miss: senaste Dexcom-Note efter senaste lyckade BG gäller tills nästa BG kommer in.
    /// För Trio-upload-miss: snäv lookup kring saknad timestamp (± toleranceSeconds).
    private func showSensorStatusAlert(forMissingDate missingDate: Date,
                                       reason: MissingReason,
                                       onDismiss: @escaping () -> Void) {
        Task {
            // A Dexcom sensor "Note" can describe an outage spanning multiple missing 5‑min slots.
            // Therefore, for sensor-missing rows we treat the latest Dexcom Note *after the last successful BG*
            // as valid until the next BG arrives.
            let note: Treatment?
            if reason == .sensor {
                let bounds = self.sensorOutageBounds(around: missingDate)
                note = await self.fetchLatestDexcomNote(after: bounds.start, before: bounds.end)
            } else {
                // For Trio-upload misses, keep the narrow lookup around the missing timestamp.
                note = await self.fetchDexcomNoteTreatment(around: missingDate, toleranceSeconds: 60)
            }

            await MainActor.run {
                let timeFormatter = DateFormatter()
                timeFormatter.locale = Locale(identifier: "sv_SE")
                timeFormatter.dateFormat = "dd MMM HH:mm:ss"

                let titleTime: String
                let message: String

                if let note = note,
                   let fullNote = note.rawData["notes"] as? String {

                    // created_at/timestamp från noten används i rubriken
                    titleTime = timeFormatter.string(from: note.timestamp)

                    var msg = fullNote
                    if let enteredBy = note.rawData["enteredBy"] as? String, !enteredBy.isEmpty {
                        msg += "\nInlagt av: \(enteredBy)"
                    }
                    message = msg

                } else {
                    // Ingen Dexcom-notering hittades i spannet — fallback-texter.
                    titleTime = timeFormatter.string(from: missingDate)

                    switch reason {
                    case .sensor:
                        message =
                        """
                        Ingen Dexcom-notering hittades i anslutning till det saknade glukosvärdet.

                        Detta beror oftast på tappad bluetoothsignal mellan sensorn och den mottagande telefonen, eller att värdet inte kunde laddas upp till varesig Dexcom Share eller Nightscout (t.ex. server-/nätverksproblem).
                        """
                    case .trioUpload:
                        message =
                        """
                        Ingen Dexcom-notering hittades i anslutning till det saknade glukosvärdet.

                        Detta beror på att Trio → Nightscout-uppladdningen misslyckadades (t.ex. bluetooth-/nätverksproblem eller andra problem med Trio-appen).
                        """
                    }
                }

                let alert = UIAlertController(
                    title: "\(titleTime)\n\nSensorstatus",
                    message: message,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    onDismiss()
                })
                self.present(alert, animated: true, completion: nil)
            }
        }
    }
    /// Returns the [start,end] bounds for a sensor outage around a missing timestamp.
    /// - start: timestamp of the last successful BG before `date` (if any)
    /// - end: timestamp of the first successful BG after `date` (if any), otherwise end-of-day/today.
    private func sensorOutageBounds(around date: Date) -> (start: Date?, end: Date) {
        let cal = Calendar.current

        // Combine both datasets so we can find the nearest successful BG regardless of current mode.
        let combined = (allValuesDayEntries + nsOnlyDayEntries)
            .sorted { $0.date < $1.date }

        // Last successful BG before the missing timestamp
        let prev = combined.last(where: { $0.date < date })?.date

        // First successful BG after the missing timestamp
        let next = combined.first(where: { $0.date > date })?.date

        // If the outage has already recovered, clamp to the first BG after the gap.
        if let next = next {
            return (start: prev, end: next)
        }

        // Otherwise, the outage is ongoing (or we're looking at the tail end of the day).
        // Clamp to end-of-day for historic days, or "now" for today.
        let dayStart = cal.startOfDay(for: selectedDate)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: dayStart) ?? Date.distantFuture

        if cal.isDate(selectedDate, inSameDayAs: Date()) {
            return (start: prev, end: min(Date(), endOfDay))
        } else {
            return (start: prev, end: endOfDay)
        }
    }

    /// Fetches the latest Dexcom-related Nightscout "Note" treatment after the last successful BG,
    /// and treats it as valid until a new BG arrives (end bound).
    private func fetchLatestDexcomNote(after start: Date?, before end: Date) async -> Treatment? {
        // If we have no previous BG, still look back a bit to catch a note at the start of an outage.
        let fallbackLookback: TimeInterval = 6 * 3600
        let windowStart = start ?? end.addingTimeInterval(-fallbackLookback)
        let windowEnd = end

        let (_, treatsJSON) = await NightscoutCache.loadWindow(from: windowStart, to: windowEnd)

        let treatments: [Treatment] = treatsJSON.compactMap { tjson in
            Treatment(dictionary: [
                "_id":       tjson._id as AnyObject,
                "eventType": tjson.eventType as AnyObject,
                "enteredBy": tjson.enteredBy as AnyObject,
                "created_at": ISO8601DateFormatter().string(from: tjson.created_at) as AnyObject,
                "rate":      tjson.rate as AnyObject,
                "absolute":  tjson.absolute as AnyObject,
                "insulin":   tjson.insulin as AnyObject,
                "carbs":     tjson.carbs as AnyObject,
                "amount":    tjson.amount as AnyObject,
                "foodType":  tjson.foodType as AnyObject,
                "notes":     tjson.notes as AnyObject,
                "glucose":   tjson.glucose as AnyObject,
                "units":     tjson.units as AnyObject,
                "duration":  tjson.tempBasalDuration as AnyObject
            ])
        }

        let candidates = treatments.filter {
            $0.eventType == "Note" &&
            (($0.rawData["notes"] as? String)?
                .localizedCaseInsensitiveContains("Dexcom") ?? false) &&
            // Must be after last successful BG (if known)
            (start == nil || $0.timestamp >= start!) &&
            // And must be before recovery (or end bound)
            $0.timestamp <= end
        }

        guard !candidates.isEmpty else { return nil }

        // Latest note wins (persists across multiple missing 5-min slots)
        return candidates.max(by: { $0.timestamp < $1.timestamp })
    }

    /// Hämtar en "Note"-treatment inom ett tidsfönster runt en timestamp och filtrerar på Dexcom.
    /// - Returns: Den närmast matchande noteringen (i tid) om någon hittas.
    private func fetchDexcomNoteTreatment(around date: Date, toleranceSeconds: TimeInterval) async -> Treatment? {
        let start = date.addingTimeInterval(-toleranceSeconds)
        let end = date.addingTimeInterval(toleranceSeconds)

        // Hämta treatments från cachefönster. (Vi behöver bara treatments.)
        let (_, treatsJSON) = await NightscoutCache.loadWindow(from: start, to: end)

        // Mappa cache-objekten till Treatment för enkel filtrering.
        let treatments: [Treatment] = treatsJSON.compactMap { tjson in
            Treatment(dictionary: [
                "_id":       tjson._id as AnyObject,
                "eventType": tjson.eventType as AnyObject,
                "enteredBy": tjson.enteredBy as AnyObject,
                "created_at": ISO8601DateFormatter().string(from: tjson.created_at) as AnyObject,
                "rate":      tjson.rate as AnyObject,
                "absolute":  tjson.absolute as AnyObject,
                "insulin":   tjson.insulin as AnyObject,
                "carbs":     tjson.carbs as AnyObject,
                "amount":    tjson.amount as AnyObject,
                "foodType":  tjson.foodType as AnyObject,
                "notes":     tjson.notes as AnyObject,
                "glucose":   tjson.glucose as AnyObject,
                "units":     tjson.units as AnyObject,
                "duration":  tjson.tempBasalDuration as AnyObject
            ])
        }

        let candidates = treatments.filter {
            $0.eventType == "Note" &&
            (($0.rawData["notes"] as? String)?
                .localizedCaseInsensitiveContains("Dexcom") ?? false)
        }

        guard !candidates.isEmpty else { return nil }

        // Välj den notering som är närmast den saknade tidsstämpeln.
        // (Denna används för snäva tidsfönster, t.ex. när Trio-uppladdning saknas.)
        return candidates.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        })
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
        formatted = formatted.replacingOccurrences(of: "BG: 5.5", with: "Glukos: 5.5 🦄")
        formatted = formatted.replacingOccurrences(of: "BG:", with: "Glukos:")
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
            let valueString = String(format: "%.1f mmol/L", entry.mmol)

            // 🦄 Unicorn = exactly 5.5 mmol/L (≈ 100 mg/dL)
            if abs(entry.mmol - 5.5) < 0.02 {
                cell.textLabel?.text = valueString + " 🦄"
            } else if abs(entry.mmol - 2.2) < 0.04 {
                cell.textLabel?.text = valueString + " 🆘"
            } else if abs(entry.mmol - 22.2) < 0.04 {
                cell.textLabel?.text = valueString + " ⚠️"
            } else {
                cell.textLabel?.text = valueString
            }

            cell.textLabel?.font = .systemFont(ofSize: 17)
            cell.detailTextLabel?.text = timeFormatter.string(from: entry.date)
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear

        case .missing(let date, let reason):
            // Detect placeholder: no actual missing rows and showOnlyMissingGlucose = true
            let isPlaceholder = showOnlyMissingGlucose && dayRowsIncludingMissing.filter { $0.isMissing }.isEmpty
            if isPlaceholder {
                cell.textLabel?.text = "Inga saknade värden denna dag ✅"
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

        case .sensorError(let date, let durationMinutes, _):
            cell.textLabel?.text = "Sensorfel • \(durationMinutes) min"
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .semibold)

            let df = DateFormatter()
            df.locale = Locale(identifier: "sv_SE")
            df.dateFormat = "yyyy-MM-dd, HH:mm"
            cell.detailTextLabel?.text = df.string(from: date)

            let tint = UIColor.systemRed.withAlphaComponent(0.15)
            cell.backgroundColor = tint
            cell.contentView.backgroundColor = tint
        }

        cell.accessoryType = .none
        return cell
    }

    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
    
    private func showExactDexcomNoteAlert(note: Treatment, durationMinutes: Int?, onDismiss: @escaping () -> Void) {
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "dd MMM HH:mm:ss"

        let titleTime = df.string(from: note.timestamp)
        let fullNote = (note.rawData["notes"] as? String) ?? "(Ingen text)"

        var msg = fullNote
        if let durationMinutes = durationMinutes {
            msg += "\n\nVaraktighet: \(durationMinutes) min"
        }
        if let enteredBy = note.rawData["enteredBy"] as? String, !enteredBy.isEmpty {
            msg += "\nInlagt av: \(enteredBy)"
        }

        let alert = UIAlertController(
            title: "\(titleTime)\n\nSensorfel",
            message: msg,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            onDismiss()
        })
        present(alert, animated: true)
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

        case .missing(let date, let reason):
            // Do not show alert for placeholder row ("Inga saknade värden denna dag")
            let isPlaceholder = showOnlyMissingGlucose && dayRowsIncludingMissing.filter { $0.isMissing }.isEmpty
            if isPlaceholder {
                tableView.deselectRow(at: indexPath, animated: true)
                return
            }
            showSensorStatusAlert(forMissingDate: date, reason: reason) {
                DispatchQueue.main.async {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            }

        case .sensorError(_, let durationMinutes, let note):
            showExactDexcomNoteAlert(note: note, durationMinutes: durationMinutes) {
                DispatchQueue.main.async {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            }
        }
    }
    
    private func loadSensorErrorRowsFromCache() -> [GlucoseRow] {
        // Read shared cache from Storage
        let items = Storage.shared.dexcomSensorErrorOutagesCache
        return glucoseRowsFromOutageItems(items)
    }

    private func glucoseRowsFromOutageItems(_ items: [DexcomSensorErrorOutageCacheItem]) -> [GlucoseRow] {
        // Convert shared cache items to GlucoseRow.sensorError for the table.
        return items
            .sorted { $0.noteTimestamp > $1.noteTimestamp }
            .compactMap { item in
                let noteDate = Date(timeIntervalSince1970: item.noteTimestamp)
                let start = Date(timeIntervalSince1970: item.startTimestamp)
                let end = Date(timeIntervalSince1970: item.endTimestamp)
                let minutes = max(0, Int(round(end.timeIntervalSince(start) / 60.0)))

                // Create minimal Treatment so existing alert logic can reuse note.rawData["notes"/"enteredBy"].
                var raw: [String: AnyObject] = [
                    "eventType": "Note" as AnyObject,
                    "created_at": ISO8601DateFormatter().string(from: noteDate) as AnyObject
                ]
                if let notes = item.notesText {
                    raw["notes"] = notes as AnyObject
                }
                if let enteredBy = item.enteredBy {
                    raw["enteredBy"] = enteredBy as AnyObject
                }

                guard let t = Treatment(dictionary: raw) else { return nil }

                return .sensorError(
                    date: noteDate,
                    durationMinutes: minutes,
                    note: t
                )
            }
    }

    // (saveSensorErrorRowsToCache and sensorErrorLastRefreshDate removed; no longer used)

    /// Loads a 90-day list of Dexcom sensor error Notes and computes duration based on nearest BGs.
    private func loadSensorErrors90Days() async {
        let cal = Calendar.current
        let now = Date()

        let hardFloor = cal.date(byAdding: .day, value: -sensorErrorLookbackDays, to: now) ?? now.addingTimeInterval(-90 * 86400)
        let overlap: TimeInterval = 6 * 3600

        // Use shared Storage cache for incremental refresh.
        let cachedItems = Storage.shared.dexcomSensorErrorOutagesCache
        let start: Date

        if cachedItems.count >= 3, let last = Storage.shared.dexcomSensorErrorOutagesRefreshedAt {
            start = max(hardFloor, last.addingTimeInterval(-overlap))
        } else {
            start = hardFloor
        }
        // Load a single wide window from the merged cache (includes Dexcom + NS values) + treatments.
        let (sgvJSON, treatsJSON) = await NightscoutCache.loadWindow(from: start, to: now)

        // Convert BG points (we only need timestamps)
        let bgTimes: [Date] = sgvJSON
            .map { Date(timeIntervalSince1970: $0.date) }
            .sorted()

        // Filter Dexcom Notes first to reduce mapping work
        let dexcomTreatJSON = treatsJSON.filter { tjson in
            tjson.eventType == "Note" && (tjson.notes?.localizedCaseInsensitiveContains("Dexcom") ?? false)
        }

        let dexcomNotes: [Treatment] = dexcomTreatJSON.compactMap { tjson in
            Treatment(dictionary: [
                "_id":       tjson._id as AnyObject,
                "eventType": tjson.eventType as AnyObject,
                "enteredBy": tjson.enteredBy as AnyObject,
                "created_at": ISO8601DateFormatter().string(from: tjson.created_at) as AnyObject,
                "rate":      tjson.rate as AnyObject,
                "absolute":  tjson.absolute as AnyObject,
                "insulin":   tjson.insulin as AnyObject,
                "carbs":     tjson.carbs as AnyObject,
                "amount":    tjson.amount as AnyObject,
                "foodType":  tjson.foodType as AnyObject,
                "notes":     tjson.notes as AnyObject,
                "glucose":   tjson.glucose as AnyObject,
                "units":     tjson.units as AnyObject,
                "duration":  tjson.tempBasalDuration as AnyObject
            ])
        }
        .sorted { $0.timestamp < $1.timestamp }

        // Build outage intervals (cache items) and dedupe multiple notes inside the same [prevBG,nextBG] span
        var outageItems: [DexcomSensorErrorOutageCacheItem] = []
        outageItems.reserveCapacity(dexcomNotes.count)

        var lastSpanKey: String?

        for note in dexcomNotes {
            let prev = nearestBG(before: note.timestamp, in: bgTimes)
            let next = nearestBG(after: note.timestamp, in: bgTimes)

            // Span key: same prev/next => same outage, only keep first
            let prevKey = prev?.timeIntervalSince1970 ?? -1
            let nextKey = next?.timeIntervalSince1970 ?? -1
            let spanKey = "\(prevKey)-\(nextKey)"

            if spanKey == lastSpanKey {
                continue
            }
            lastSpanKey = spanKey

            let startTime = prev ?? note.timestamp
            let endTime = next ?? now

            let notesText = note.rawData["notes"] as? String
            let enteredBy = note.rawData["enteredBy"] as? String

            outageItems.append(
                DexcomSensorErrorOutageCacheItem(
                    noteTimestamp: note.timestamp.timeIntervalSince1970,
                    startTimestamp: startTime.timeIntervalSince1970,
                    endTimestamp: endTime.timeIntervalSince1970,
                    notesText: notesText,
                    enteredBy: enteredBy
                )
            )
        }

        // Newest first (from the fetched window)
        let newestItems = outageItems.sorted { $0.noteTimestamp > $1.noteTimestamp }

        await MainActor.run {
            // Merge by noteTimestamp (latest computed wins), keep only within retention.
            var mergedByNote: [TimeInterval: DexcomSensorErrorOutageCacheItem] = [:]

            // Start with existing cache, drop anything older than hardFloor
            let floorTS = hardFloor.timeIntervalSince1970
            for item in cachedItems where item.noteTimestamp >= floorTS {
                mergedByNote[item.noteTimestamp] = item
            }

            // Overwrite/insert latest computed items
            for item in newestItems {
                mergedByNote[item.noteTimestamp] = item
            }

            let merged = mergedByNote.values.sorted { $0.noteTimestamp > $1.noteTimestamp }

            // Persist shared cache
            Storage.shared.dexcomSensorErrorOutagesCache = merged
            Storage.shared.dexcomSensorErrorOutagesRefreshedAt = now

            // Drive UI rows from shared cache
            self.sensorErrorRows = self.glucoseRowsFromOutageItems(merged)
            self.tableView.reloadData()

            // Stats label: count
            self.statsLabel.text = "Antal sensorfel: \(merged.count) st (90d)   "
            self.hideRefreshIndicator()
        }
    }

    private func nearestBG(before date: Date, in bgTimes: [Date]) -> Date? {
        guard !bgTimes.isEmpty else { return nil }
        // bgTimes is sorted asc
        var lo = 0
        var hi = bgTimes.count - 1
        var result: Date?
        while lo <= hi {
            let mid = (lo + hi) / 2
            let d = bgTimes[mid]
            if d < date {
                result = d
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return result
    }

    private func nearestBG(after date: Date, in bgTimes: [Date]) -> Date? {
        guard !bgTimes.isEmpty else { return nil }
        // bgTimes is sorted asc
        var lo = 0
        var hi = bgTimes.count - 1
        var result: Date?
        while lo <= hi {
            let mid = (lo + hi) / 2
            let d = bgTimes[mid]
            if d > date {
                result = d
                hi = mid - 1
            } else {
                lo = mid + 1
            }
        }
        return result
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
    private var unicornsByDay: [Date: Int] = [:]
    
    // Raw SGV data for full window (used for extreme-value stats)
    private var allSGVJSON: [SGVJSON] = []


    // Current selection
    private var selectedDays: [Date] = []
    private var selectedCountsAllValues: [Int] = []
    private var selectedCountsNSOnly: [Int] = []

    // Sensor error outages (computed for the full window, then filtered by selected period)
    private struct SensorErrorOutage {
        let noteDate: Date
        let durationMinutes: Int
    }
    private var allSensorErrorOutages: [SensorErrorOutage] = []
    private var selectedSensorErrorOutages: [SensorErrorOutage] = []

    private enum ChartMode: Int {
        case glucoseValues = 0
        case sensorErrors = 1
    }
    private var selectedChartMode: ChartMode = .glucoseValues

    private lazy var chartModeControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Glukosvärden", "Sensorfel"])
        sc.selectedSegmentIndex = selectedChartMode.rawValue
        sc.addTarget(self, action: #selector(chartModeChanged(_:)), for: .valueChanged)
        return sc
    }()

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

    // Scatterplot: Sensorfel per datum (x) och tid på dygnet (y)
    private let sensorErrorChartView: ScatterChartView = {
        let v = ScatterChartView()
        v.chartDescription.enabled = false
        v.legend.enabled = false
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
        v.rightAxis.enabled = false
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

            // Load datasets (and treatments for Sensorfel)
            let (allSGV, allTreatments) = await NightscoutCache.loadWindow(from: startDay, to: now)
            let nsOnlySGV = await GlucoseNSOnlyCache.loadWindow(from: startDay, to: now)
            self.allSGVJSON = allSGV

            // Build Sensorfel outages for the full window
            let outages = self.buildSensorErrorOutages(allSGV: allSGV, allTreatments: allTreatments, now: now)

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

            // Unicorn counts per day
            let unicornsByDay = self.unicornCountsByDayFromSGVJSON(allSGV)

            await MainActor.run {
                self.allDays = days
                self.allCountsAllValues = countsAll
                self.allCountsNSOnly = countsNS
                self.allSensorErrorOutages = outages
                self.unicornsByDay = unicornsByDay

                // Apply initial period
                self.applyPeriod(self.selectedPeriod)
            }
        }
    }
    /// Counts "unicorn" readings (≈ 5.5 mmol/L) per day, deduped to match GlucoseView.
    private func unicornCountsByDayFromSGVJSON(_ sgvs: [SGVJSON]) -> [Date: Int] {
        let cal = Calendar.current

        // Per dag: set av tidsbuckets (4-min, samma som allValuesDayEntries)
        var bucketsByDay: [Date: Set<Int>] = [:]

        for e in sgvs {
            // SGVJSON.sgv är mg/dL → konvertera till mmol/L
            let mmol = Double(e.sgv) / 18.0182

            // Samma tolerans som i GlucoseView (🦄-etiketten)
            guard abs(mmol - 5.5) < 0.02 else { continue }

            let date = Date(timeIntervalSince1970: e.date)
            let dayStart = cal.startOfDay(for: date)

            // Dedupera på 4-minutersbuckets ungefär som dedupeToBuckets(..., bucketSeconds: 240)
            let bucket = Int(floor(date.timeIntervalSince1970 / 240.0))

            var set = bucketsByDay[dayStart] ?? []
            set.insert(bucket)
            bucketsByDay[dayStart] = set
        }

        var counts: [Date: Int] = [:]
        counts.reserveCapacity(bucketsByDay.count)
        for (day, set) in bucketsByDay {
            counts[day] = set.count
        }
        return counts
    }
    // MARK: - Unicorn badge

    /// Updates the 🦄 badge in the top-left corner based on the current period's total unicorn count.
    private func updateUnicornBadge(for count: Int) {
        if count > 0 {
            let title = "🦄 \(count)"
            let item = UIBarButtonItem(title: title, style: .plain, target: nil, action: nil)
            item.isEnabled = false
            navigationItem.leftBarButtonItem = item
        } else {
            navigationItem.leftBarButtonItem = nil
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

    // MARK: - Sensorfel helpers

    /// Build sensor error outages (deduped by the [prevBG,nextBG] span) from the full window.
    private func buildSensorErrorOutages(allSGV: [SGVJSON], allTreatments: [TreatmentJSON], now: Date) -> [SensorErrorOutage] {
        // BG timestamps (sorted)
        let bgTimes: [Date] = allSGV
            .map { Date(timeIntervalSince1970: $0.date) }
            .sorted()

        // Filter Dexcom Notes first
        let dexcomTreatJSON = allTreatments.filter { tjson in
            tjson.eventType == "Note" && (tjson.notes?.localizedCaseInsensitiveContains("Dexcom") ?? false)
        }

        let dexcomNotes: [Treatment] = dexcomTreatJSON.compactMap { tjson in
            Treatment(dictionary: [
                "_id":       tjson._id as AnyObject,
                "eventType": tjson.eventType as AnyObject,
                "enteredBy": tjson.enteredBy as AnyObject,
                "created_at": ISO8601DateFormatter().string(from: tjson.created_at) as AnyObject,
                "rate":      tjson.rate as AnyObject,
                "absolute":  tjson.absolute as AnyObject,
                "insulin":   tjson.insulin as AnyObject,
                "carbs":     tjson.carbs as AnyObject,
                "amount":    tjson.amount as AnyObject,
                "foodType":  tjson.foodType as AnyObject,
                "notes":     tjson.notes as AnyObject,
                "glucose":   tjson.glucose as AnyObject,
                "units":     tjson.units as AnyObject,
                "duration":  tjson.tempBasalDuration as AnyObject
            ])
        }
        .sorted { $0.timestamp < $1.timestamp }

        var outages: [SensorErrorOutage] = []
        outages.reserveCapacity(dexcomNotes.count)

        var lastSpanKey: String?

        for note in dexcomNotes {
            let prev = nearestBG(before: note.timestamp, in: bgTimes)
            let next = nearestBG(after: note.timestamp, in: bgTimes)

            let prevKey = prev?.timeIntervalSince1970 ?? -1
            let nextKey = next?.timeIntervalSince1970 ?? -1
            let spanKey = "\(prevKey)-\(nextKey)"

            if spanKey == lastSpanKey {
                continue
            }
            lastSpanKey = spanKey

            let startTime = prev ?? note.timestamp
            let endTime = next ?? now
            let minutes = max(0, Int(round(endTime.timeIntervalSince(startTime) / 60.0)))

            outages.append(SensorErrorOutage(noteDate: note.timestamp, durationMinutes: minutes))
        }

        return outages.sorted { $0.noteDate > $1.noteDate }
    }

    private func updateSensorErrorChart() {
        guard !selectedSensorErrorOutages.isEmpty else {
            sensorErrorChartView.data = nil
            sensorErrorChartView.setNeedsDisplay()
            return
        }

        let cal = Calendar.current

        // Index per dag för x-position (matchar BGCheck time-scatter)
        let periodDays = selectedDays
        var indexByDay: [Date: Int] = [:]
        indexByDay.reserveCapacity(periodDays.count)
        for (idx, d) in periodDays.enumerated() {
            indexByDay[cal.startOfDay(for: d)] = idx
        }

        // X-axis labels = datum (kompakt format) för varje index
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "dd/MM"
        let labels = periodDays.map { df.string(from: $0) }

        // Hjälpfunktion: timestamp -> timmar på dygnet (0–24)
        func hourOfDay(for date: Date) -> Double {
            let comps = cal.dateComponents([.hour, .minute, .second], from: date)
            let h = Double(comps.hour ?? 0)
            let m = Double(comps.minute ?? 0)
            let s = Double(comps.second ?? 0)
            return h + (m / 60.0) + (s / 3600.0)
        }

        // Points: flera sensorfel kan landa på samma dagIndex (samma x)
        var entries: [ChartDataEntry] = []
        entries.reserveCapacity(selectedSensorErrorOutages.count)

        for o in selectedSensorErrorOutages {
            let dayStart = cal.startOfDay(for: o.noteDate)
            guard let dayIndex = indexByDay[dayStart] else { continue }
            entries.append(ChartDataEntry(x: Double(dayIndex), y: hourOfDay(for: o.noteDate)))
        }

        // Viktigt: sortera entries för att undvika Charts-bug där punkter kan försvinna vid zoom/scroll
        entries.sort {
            if $0.x == $1.x { return $0.y < $1.y }
            return $0.x < $1.x
        }

        let ds = ScatterChartDataSet(entries: entries, label: "Sensorfel")
        ds.drawValuesEnabled = false
        ds.setScatterShape(.circle)
        ds.scatterShapeSize = 7
        ds.setColor(.black)
        ds.scatterShapeHoleRadius = 3
        ds.scatterShapeHoleColor = .systemRed

        let data = ScatterChartData(dataSet: ds)
        sensorErrorChartView.data = data

        // X-axis (match BGCheck time-scatter)
        let xAxis = sensorErrorChartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.granularity = 1
        xAxis.granularityEnabled = true
        xAxis.valueFormatter = IndexAxisValueFormatter(values: labels)
        xAxis.setLabelCount(min(6, labels.count), force: false)

        // Ensure stable visible range during zoom
        xAxis.axisMinimum = -0.5
        xAxis.axisMaximum = Double(max(0, labels.count - 1)) + 0.5
        
        // Y-axel = timmar 0–24 (dashad grid) + solida huvudlinjer 00/06/12/18/24
        let yAxis = sensorErrorChartView.leftAxis
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

        sensorErrorChartView.rightAxis.enabled = false

        // Light grid
        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.5)
        xAxis.gridColor = gridLineColor
        xAxis.gridLineWidth = 0.5
        xAxis.gridLineDashLengths = [2, 2]

        yAxis.gridColor = gridLineColor
        yAxis.gridLineWidth = 0.5
        yAxis.gridLineDashLengths = [2, 2]
        
        sensorErrorChartView.drawGridBackgroundEnabled = true
        sensorErrorChartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)

        sensorErrorChartView.notifyDataSetChanged()
        sensorErrorChartView.setNeedsDisplay()
    }

    private func nearestBG(before date: Date, in bgTimes: [Date]) -> Date? {
        guard !bgTimes.isEmpty else { return nil }
        var lo = 0
        var hi = bgTimes.count - 1
        var result: Date?
        while lo <= hi {
            let mid = (lo + hi) / 2
            let d = bgTimes[mid]
            if d < date {
                result = d
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return result
    }

    private func nearestBG(after date: Date, in bgTimes: [Date]) -> Date? {
        guard !bgTimes.isEmpty else { return nil }
        var lo = 0
        var hi = bgTimes.count - 1
        var result: Date?
        while lo <= hi {
            let mid = (lo + hi) / 2
            let d = bgTimes[mid]
            if d > date {
                result = d
                hi = mid - 1
            } else {
                lo = mid + 1
            }
        }
        return result
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

        // Filter sensor errors to the selected period
        let cal = Calendar.current
        let periodStart = cal.startOfDay(for: selectedDays.first ?? Date())
        let periodEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: selectedDays.last ?? Date())) ?? Date()
        self.selectedSensorErrorOutages = allSensorErrorOutages.filter { $0.noteDate >= periodStart && $0.noteDate < periodEnd }

        // Unicorn count for the selected period (sum of per-day unicorns over selectedDays)
        let unicornCount = selectedDays.reduce(0) { $0 + (unicornsByDay[$1] ?? 0) }
        updateUnicornBadge(for: unicornCount)

        if selectedChartMode == .sensorErrors {
            updateSensorErrorChart()
        }

        loadChartData()
        chartView.isHidden = (selectedChartMode == .sensorErrors)
        sensorErrorChartView.isHidden = (selectedChartMode != .sensorErrors)
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
        container.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 350)
        container.backgroundColor = .clear

        container.addSubview(periodControl)
        container.addSubview(chartModeControl)
        container.addSubview(chartView)
        container.addSubview(sensorErrorChartView)

        periodControl.translatesAutoresizingMaskIntoConstraints = false
        chartModeControl.translatesAutoresizingMaskIntoConstraints = false
        chartView.translatesAutoresizingMaskIntoConstraints = false
        sensorErrorChartView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            periodControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            periodControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            periodControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            chartModeControl.topAnchor.constraint(equalTo: periodControl.bottomAnchor, constant: 8),
            chartModeControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            chartModeControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            chartView.topAnchor.constraint(equalTo: chartModeControl.bottomAnchor, constant: 12),
            chartView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            chartView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            chartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: 20),

            sensorErrorChartView.topAnchor.constraint(equalTo: chartModeControl.bottomAnchor, constant: 12),
            sensorErrorChartView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            sensorErrorChartView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            sensorErrorChartView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        // Initial visibility
        chartView.isHidden = (selectedChartMode == .sensorErrors)
        sensorErrorChartView.isHidden = (selectedChartMode != .sensorErrors)

        tableView.tableHeaderView = container
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let header = tableView.tableHeaderView {
            let targetSize = CGSize(width: tableView.bounds.width, height: 370)
            if header.frame.size != targetSize {
                header.frame.size = targetSize
                tableView.tableHeaderView = header
            }
        }
    }
    @objc private func chartModeChanged(_ sender: UISegmentedControl) {
        let idx = sender.selectedSegmentIndex
        selectedChartMode = ChartMode(rawValue: idx) ?? .glucoseValues

        chartView.isHidden = (selectedChartMode == .sensorErrors)
        sensorErrorChartView.isHidden = (selectedChartMode != .sensorErrors)

        if selectedChartMode == .sensorErrors {
            updateSensorErrorChart()
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

        let dsAll = BarChartDataSet(entries: entriesAll, label: "Alla Dexcomvärden")
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
        
        chartView.drawGridBackgroundEnabled = true
        chartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)

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
        legend.form = .circle
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
    
    /// Counts extreme glucose values within the selected period.
    /// Low  <= 2.2 mmol/L (40 mg/dL)
    /// High >= 22.2 mmol/L (400 mg/dL)
    private func countExtremeValuesForSelectedPeriod() -> (low: Int, high: Int) {
        guard !selectedDays.isEmpty else { return (0, 0) }

        let cal = Calendar.current
        let periodStart = cal.startOfDay(for: selectedDays.first!)
        let periodEnd = cal.date(
            byAdding: .day,
            value: 1,
            to: cal.startOfDay(for: selectedDays.last!)
        ) ?? Date()

        var low = 0
        var high = 0

        for e in allSGVJSON {
            let d = Date(timeIntervalSince1970: e.date)
            guard d >= periodStart && d < periodEnd else { continue }

            // SGVJSON.sgv is mg/dL
            if e.sgv <= 40 {
                low += 1
            } else if e.sgv >= 400 {
                high += 1
            }
        }
        return (low, high)
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

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            // Dexcom inkl backfill
            return 6
        case 1:
            // Trio uppladdningar realtid
            return 5
        default:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Dexcom glukosvärden (inkl backfill)"
        case 1:
            return "Trio uppladdningar (realtid)"
        default:
            return nil
        }
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
        let avgMinutesNoAll = avgMissNS * 5.0
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

        switch indexPath.section {
        case 0:
            // Dexcom inkl backfill
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Medel glukosvärden"
                cell.detailTextLabel?.text = percentString(avgAllPct)

            case 1:
                cell.textLabel?.text = "Medel saknade värden/dag"
                cell.detailTextLabel?.text = "\(countString(avgMissAll)) st"

            case 2:
                cell.textLabel?.text = "Antal sensorfel"
                cell.detailTextLabel?.text = "\(selectedSensorErrorOutages.count) st"

            case 3:
                cell.textLabel?.text = "Tid med sensorfel"
                let totalMin = selectedSensorErrorOutages.reduce(0) { $0 + $1.durationMinutes }
                let h = totalMin / 60
                let m = totalMin % 60
                if h > 0 {
                    cell.detailTextLabel?.text = "\(h) h \(m) min"
                } else {
                    cell.detailTextLabel?.text = "\(m) min"
                }
                
            case 4:
                cell.textLabel?.text = "Värden under LÅG tröskel (2.2)"
                let extremes = countExtremeValuesForSelectedPeriod()
                cell.detailTextLabel?.text = "\(extremes.low) st"

            case 5:
                cell.textLabel?.text = "Värden över HÖG tröskel (22.2)"
                let extremes = countExtremeValuesForSelectedPeriod()
                cell.detailTextLabel?.text = "\(extremes.high) st"

            default:
                break
            }

        case 1:
            // Trio uppladdningar realtid
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Medel lyckade/dag"
                cell.detailTextLabel?.text = percentString(avgNSPct)

            case 1:
                cell.textLabel?.text = "Medel missar/dag"
                cell.detailTextLabel?.text = "\(countString(avgMissNS)) st"

            case 2:
                cell.textLabel?.text = "Medel tid/dag utan värden"
                cell.detailTextLabel?.text = "\(countString(avgMinutesNoAll)) min"

            case 3:
                cell.textLabel?.text = "Bästa dag"
                if let d = bestDate {
                    cell.detailTextLabel?.text = "\(percentString(bestPct)) • \(dfISO.string(from: d))"
                } else {
                    cell.detailTextLabel?.text = "–"
                }

            case 4:
                cell.textLabel?.text = "Sämsta dag"
                if let d = worstDate {
                    cell.detailTextLabel?.text = "\(percentString(worstPct)) • \(dfISO.string(from: d))"
                } else {
                    cell.detailTextLabel?.text = "–"
                }

            default:
                break
            }

        default:
            break
        }

        return cell
    }
    
    override func tableView(_ tableView: UITableView,
                            willDisplayHeaderView view: UIView,
                            forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            header.textLabel?.textColor = .secondaryLabel
        }
    }
}
