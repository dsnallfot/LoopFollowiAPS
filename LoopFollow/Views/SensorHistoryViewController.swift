//
//  SensorHistoryViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-03-09.

//
import UIKit
import Charts

struct SessionBuckets {
    // Counts
    var lt1d: Int = 0        // < 1 day
    var d1to5: Int = 0       // 1 - 5 days
    var d5to9_5: Int = 0     // 5 - 9.5 days
    var gt9_5: Int = 0       // > 9.5 days (>= 228h)

    // Total hours per bucket (for averages)
    var hrs_lt1d: Int = 0
    var hrs_d1to5: Int = 0
    var hrs_d5to9_5: Int = 0
    var hrs_gt9_5: Int = 0

    // Overall totals
    var total: Int { lt1d + d1to5 + d5to9_5 + gt9_5 }
    var hrs_total: Int { hrs_lt1d + hrs_d1to5 + hrs_d5to9_5 + hrs_gt9_5 }
}

class SensorHistoryViewController: ThemedViewController, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate {
    
    private var sensorHistory: [SensorStartHistoryEntry] = []
    private var filteredHistory: [SensorStartHistoryEntry] = []
    private var isFiltering: Bool { !(searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    private let searchBar: UISearchBar = {
        let sb = UISearchBar()
        sb.placeholder = "Sök i sensorloggen"
        sb.autocapitalizationType = .none
        sb.autocorrectionType = .no
        sb.searchBarStyle = .minimal
        return sb
    }()

    private let openedAt = Date() // snapshot when modal opened
    
    // Dexcom sensorfel outages (persisted cache, refreshed incrementally)
    private var dexcomOutagesCache: [DexcomSensorErrorOutageCacheItem] = []
    private var isRefreshingDexcomOutagesCache: Bool = false

    private let topSearchContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .clear
        return v
    }()

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)//.insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private func currentHistory() -> [SensorStartHistoryEntry] {
        return isFiltering ? filteredHistory : sensorHistory
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Sensorlogg"
        updateBackgroundForCurrentMode()
        setupNavigationBar()
        searchBar.delegate = self
        installPinnedSearchBar()
        view.addSubview(tableView)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topSearchContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SensorHistoryCell")
        // Themed background: let gradient show through
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.isOpaque = false
        loadSensorHistory()
        loadDexcomOutagesCacheAndRefreshIfNeeded()
    }

    private func installPinnedSearchBar() {
        // Add a non-scrolling container under the nav bar
        view.addSubview(topSearchContainer)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            topSearchContainer.topAnchor.constraint(equalTo: guide.topAnchor),
            topSearchContainer.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            topSearchContainer.trailingAnchor.constraint(equalTo: guide.trailingAnchor)
        ])

        let sb = searchBar
        sb.translatesAutoresizingMaskIntoConstraints = false
        topSearchContainer.addSubview(sb)
        NSLayoutConstraint.activate([
            sb.leadingAnchor.constraint(equalTo: topSearchContainer.leadingAnchor, constant: 12),
            sb.trailingAnchor.constraint(equalTo: topSearchContainer.trailingAnchor, constant: -12),
            sb.topAnchor.constraint(equalTo: topSearchContainer.topAnchor, constant: 6),
            sb.bottomAnchor.constraint(equalTo: topSearchContainer.bottomAnchor, constant: -2)
        ])
    }

    
    // MARK: - Navigation Bar Setup
    
    private func setupNavigationBar() {
        // --- Left side: custom stack with controlled spacing and 2pt inset from the bubble edge ---
        let addBtn = UIButton(type: .system)
        addBtn.setImage(UIImage(systemName: "plus"), for: .normal)
        addBtn.tintColor = .label
        addBtn.addTarget(self, action: #selector(addManualSensorNote), for: .touchUpInside)

        let shareBtn = UIButton(type: .system)
        shareBtn.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareBtn.tintColor = .label
        shareBtn.addTarget(self, action: #selector(exportSensorHistory), for: .touchUpInside)

        let importBtn = UIButton(type: .system)
        importBtn.setImage(UIImage(systemName: "square.and.arrow.down"), for: .normal)
        importBtn.tintColor = .label
        importBtn.addTarget(self, action: #selector(importSensorHistory), for: .touchUpInside)

        // Tighten spacing between icons but keep 2pt leading margin from the nav bar's liquid glass edge
        let leftStack = UIStackView(arrangedSubviews: [addBtn, shareBtn, importBtn])
        leftStack.axis = .horizontal
        leftStack.alignment = .center
        leftStack.spacing = 9 // tighten icon-to-icon spacing
        leftStack.isLayoutMarginsRelativeArrangement = true
        leftStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 0) // 2pt from edge

        // Ensure tappable area is comfortable
        [addBtn, shareBtn, importBtn].forEach { btn in
            btn.contentEdgeInsets = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        }

        let leftItem = UIBarButtonItem(customView: leftStack)
        navigationItem.leftBarButtonItems = [leftItem]

        // --- Right side: info + done ---
        let infoButton = UIBarButtonItem(
            image: UIImage(systemName: "chart.bar.xaxis.ascending"),
            style: .plain,
            target: self,
            action: #selector(showSessionStats)
        )

        let doneButton = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(doneButtonTapped)
        )

        navigationItem.rightBarButtonItems = [doneButton, infoButton]
    }


    
    @objc private func doneButtonTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func showSessionStats() {
        let buckets = computeSessionBuckets()
        let statsVC = SensorSessionStatsViewController(buckets: buckets, history: sensorHistory)
        let nav = UINavigationController(rootViewController: statsVC)

        // Ensure the modal container doesn't paint an opaque gray background.
        nav.modalPresentationStyle = .formSheet
        nav.view.backgroundColor = .clear
        nav.view.isOpaque = false
        nav.view.layer.backgroundColor = UIColor.clear.cgColor

        // Transparent navigation bar so the gradient shows behind it too.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance

        // Match current interface style
        nav.overrideUserInterfaceStyle = self.traitCollection.userInterfaceStyle

        present(nav, animated: true)
    }

    private func loadSensorHistory() {
        sensorHistory = Storage.shared.sensorStartNotes
        sensorHistory.sort { $0.date > $1.date }
        applyFilterAndReload()
    }

    private func applyFilterAndReload() {
        let query = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if query.isEmpty {
            filteredHistory = []
        } else {
            filteredHistory = sensorHistory.filter { entry in
                let note = entry.note.replacingOccurrences(of: "+0000", with: "").lowercased()
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd HH:mm"
                let dateStr = df.string(from: Date(timeIntervalSince1970: entry.date)).lowercased()
                return note.contains(query) || dateStr.contains(query)
            }
        }
        tableView.reloadData()
    }
    
    private func computeSessionBuckets() -> SessionBuckets {
        guard sensorHistory.count > 1 else { return SessionBuckets() }
        var buckets = SessionBuckets()
        // Exclude index 0 (ongoing). For each i >= 1, endDate is the newer entry at i-1
        for i in 1..<sensorHistory.count {
            let start = Date(timeIntervalSince1970: sensorHistory[i].date)
            let end = Date(timeIntervalSince1970: sensorHistory[i - 1].date)
            var interval = end.timeIntervalSince(start)
            if interval < 0 { interval = 0 }
            let hours = Int(interval / 3600)
            switch hours {
            case ..<24:
                buckets.lt1d += 1
                buckets.hrs_lt1d += hours
            case 24..<120:
                buckets.d1to5 += 1
                buckets.hrs_d1to5 += hours
            case 120..<228:
                buckets.d5to9_5 += 1
                buckets.hrs_d5to9_5 += hours
            default: // >= 228h
                buckets.gt9_5 += 1
                buckets.hrs_gt9_5 += hours
            }
        }
        return buckets
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return currentHistory().count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SensorHistoryCell", for: indexPath)
        let entry = currentHistory()[indexPath.row]
        let cleanedNote = entry.note
            .replacingOccurrences(of: "+0000", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let formattedDate = dateFormatter.string(from: Date(timeIntervalSince1970: entry.date))

        // Use a slightly smaller dynamic font than default body
        let baseBody = UIFont.preferredFont(forTextStyle: .body)
        let smallBody = UIFontMetrics(forTextStyle: .body).scaledFont(for: baseBody.withSize(baseBody.pointSize - 1))
        cell.textLabel?.font = smallBody
        cell.textLabel?.adjustsFontForContentSizeCategory = true

        // Build: "<date> <session-info>" (first line), then "<note>" (second line)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: smallBody,
            .foregroundColor: cell.textLabel?.textColor ?? UIColor.label
        ]
        let append = sessionAppendInfo(forEntry: entry)
        let sessionAttrs: [NSAttributedString.Key: Any] = [
            .font: smallBody,
            .foregroundColor: append.color
        ]

        let composed = NSMutableAttributedString()
        composed.append(NSAttributedString(string: formattedDate, attributes: baseAttrs))
        composed.append(NSAttributedString(string: " ", attributes: baseAttrs))
        composed.append(NSAttributedString(string: append.text, attributes: sessionAttrs))
        composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))
        composed.append(NSAttributedString(string: cleanedNote, attributes: baseAttrs))

        cell.textLabel?.attributedText = composed
        cell.textLabel?.numberOfLines = 0

        // Transparent cell so the themed gradient shows through
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.backgroundView = nil

        // IMPORTANT: Disable iOS 14+ backgroundConfiguration completely,
        // otherwise UITableView injects a default gray background and kills the gradient.
        if #available(iOS 14.0, *) {
            cell.backgroundConfiguration = nil
        }

        cell.textLabel?.backgroundColor = .clear
        cell.detailTextLabel?.backgroundColor = .clear

        // Match Treatments-style selection highlight (subtle overlay over the gradient)
        cell.selectionStyle = .default
        let selected = UIView()
        selected.backgroundColor = UIColor.label.withAlphaComponent(0.2)
        selected.layer.cornerRadius = 10
        selected.layer.masksToBounds = true
        cell.selectedBackgroundView = selected
        // Ensure reused cells always start with a fully visible selection overlay
        cell.selectedBackgroundView?.alpha = 1

        return cell
    }

    private func sessionAppendInfo(forEntry entry: SensorStartHistoryEntry) -> (text: String, color: UIColor) {
        // Compute using the full (unfiltered) timeline so values remain correct while filtering
        guard let index = sensorHistory.firstIndex(where: { $0.date == entry.date && $0.note == entry.note }) else {
            return ("", .label)
        }
        let current = sensorHistory[index]
        let currentStart = Date(timeIntervalSince1970: current.date)
        let endDate: Date
        let isOngoing = (index == 0)
        if isOngoing {
            endDate = openedAt
        } else {
            // "Next" activation in time is the row above (newer) since list is sorted desc
            let newer = sensorHistory[index - 1]
            endDate = Date(timeIntervalSince1970: newer.date)
        }
        var interval = endDate.timeIntervalSince(currentStart)
        if interval < 0 { interval = 0 } // guard against ordering glitches
        let totalHours = Int(interval / 3600)
        let days = totalHours / 24
        let hours = totalHours % 24

        // Color selection: ongoing sessions are blue; past sessions use thresholds
        let color: UIColor
        if isOngoing {
            color = .systemBlue
        } else {
            switch totalHours {
            case 228...: color = .systemGreen           // >= 9.5 dagar
            case 120..<228: color = .systemOrange       // 5-10 dagar
            default: color = .systemRed                 // < 5 dagar
            }
        }

        let prefix = isOngoing ? " (Pågående: " : " (Session: "
        var snippet = "\(prefix)\(days)d \(hours)h)"

        // Mark very short past sessions
        if !isOngoing && totalHours < 24 { snippet += " ⛔️" }

        // Append warning if this sensor session has identified Dexcom sensorfel
        let startTs = currentStart.timeIntervalSince1970
        let endTs = endDate.timeIntervalSince1970
        if dexcomOutagesCache.contains(where: { $0.noteTimestamp >= startTs && $0.noteTimestamp < endTs }) {
            snippet += " ⚠️"
        }

        return (snippet, color)
    }
    
    // MARK: - Dexcom sensorfel cache + reklamations-alert

    private func loadDexcomOutagesCacheAndRefreshIfNeeded() {
        // Load persisted cache immediately so taps work without waiting
        self.dexcomOutagesCache = Storage.shared.dexcomSensorErrorOutagesCache

        // Kick an incremental refresh in the background
        refreshDexcomOutagesCacheIfNeeded()
    }

    private func refreshDexcomOutagesCacheIfNeeded() {
        guard !isRefreshingDexcomOutagesCache else { return }
        isRefreshingDexcomOutagesCache = true

        Task {
            defer { self.isRefreshingDexcomOutagesCache = false }

            let cal = Calendar.current
            let now = Date()

            // Keep up to 90 days (same as GlucoseView sensorfel retention)
            let hardFloor = cal.date(byAdding: .day, value: -(90 - 1), to: cal.startOfDay(for: now)) ?? cal.startOfDay(for: now)

            // Incremental refresh from last refreshed, with overlap so prev/next BG span resolves.
            let overlap: TimeInterval = 12 * 3600
            let last = Storage.shared.dexcomSensorErrorOutagesRefreshedAt
            let start = max(hardFloor, (last ?? hardFloor).addingTimeInterval(-overlap))

            // Load SGV + treatments window (same as GlucoseStatsViewController)
            let (allSGV, allTreatments) = await NightscoutCache.loadWindow(from: start, to: now)

            // Build outages from this window
            let newItems = self.buildDexcomOutageItems(allSGV: allSGV, allTreatments: allTreatments, now: now)

            await MainActor.run {
                // Merge by noteTimestamp (latest computed wins)
                var mergedByNote: [TimeInterval: DexcomSensorErrorOutageCacheItem] = [:]

                // Existing persisted cache, but drop anything older than hardFloor
                for item in Storage.shared.dexcomSensorErrorOutagesCache {
                    if item.noteTimestamp >= hardFloor.timeIntervalSince1970 {
                        mergedByNote[item.noteTimestamp] = item
                    }
                }

                // Overwrite/insert from new window
                for item in newItems {
                    mergedByNote[item.noteTimestamp] = item
                }

                let merged = mergedByNote.values.sorted { $0.noteTimestamp > $1.noteTimestamp }

                self.dexcomOutagesCache = merged
                Storage.shared.dexcomSensorErrorOutagesCache = merged
                Storage.shared.dexcomSensorErrorOutagesRefreshedAt = now
            }
        }
    }

    private func buildDexcomOutageItems(allSGV: [SGVJSON], allTreatments: [TreatmentJSON], now: Date) -> [DexcomSensorErrorOutageCacheItem] {
        // BG timestamps sorted asc
        let bgTimes: [Date] = allSGV
            .map { Date(timeIntervalSince1970: $0.date) }
            .sorted()

        // Filter Dexcom Notes
        let dexcomTreatJSON = allTreatments.filter { tjson in
            tjson.eventType == "Note" && (tjson.notes?.localizedCaseInsensitiveContains("Dexcom") ?? false)
        }

        // Convert to Treatment (same mapping style as GlucoseView)
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

        var items: [DexcomSensorErrorOutageCacheItem] = []
        items.reserveCapacity(dexcomNotes.count)

        var lastSpanKey: String?

        for note in dexcomNotes {
            let prev = nearestBG(before: note.timestamp, in: bgTimes)
            let next = nearestBG(after: note.timestamp, in: bgTimes)

            let prevKey = prev?.timeIntervalSince1970 ?? -1
            let nextKey = next?.timeIntervalSince1970 ?? -1
            let spanKey = "\(prevKey)-\(nextKey)"

            // Same prev/next span => same outage => keep only first
            if spanKey == lastSpanKey { continue }
            lastSpanKey = spanKey

            let startTime = (prev ?? note.timestamp)
            let endTime = (next ?? now)

            items.append(
                DexcomSensorErrorOutageCacheItem(
                    noteTimestamp: note.timestamp.timeIntervalSince1970,
                    startTimestamp: startTime.timeIntervalSince1970,
                    endTimestamp: endTime.timeIntervalSince1970
                )
            )
        }

        // Newest first
        return items.sorted { $0.noteTimestamp > $1.noteTimestamp }
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

    private func formatTotalDuration(minutes totalMin: Int?) -> String {
        guard let totalMin = totalMin else { return "--" }
        let h = totalMin / 60
        let m = totalMin % 60
        if h > 0 { return "\(h) h \(m) min" }
        return "\(m) min"
    }

    private func parsedSensorName(fromNote note: String) -> String? {
        let cleaned = note
            .replacingOccurrences(of: "+0000", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(6))
    }

    private func perCalendarDayErrorMinutes(
        outages: [DexcomSensorErrorOutageCacheItem],
        sessionStart: Date,
        sessionEnd: Date,
        maxDays: Int = 10
    ) -> [Int] {
        guard sessionEnd >= sessionStart else { return [] }

        let cal = Calendar.current
        let startOfFirstDay = cal.startOfDay(for: sessionStart)
        let startOfLastDay = cal.startOfDay(for: sessionEnd)

        // Total number of calendar days the session spans (including partial first/last days)
        let daySpan = (cal.dateComponents([.day], from: startOfFirstDay, to: startOfLastDay).day ?? 0) + 1

        // We will always compute all days in the span, but collapse anything beyond `maxDays`
        // into the last visible bucket so we never drop minutes.
        let daysToShow = max(0, min(maxDays, daySpan))
        guard daysToShow > 0 else { return [] }

        var result = Array(repeating: 0, count: daysToShow)

        // Pre-clamp each outage to the session window to avoid edge cases.
        let clampedOutages: [(start: Date, end: Date)] = outages.compactMap { item in
            let s = Date(timeIntervalSince1970: item.startTimestamp)
            let e = Date(timeIntervalSince1970: item.endTimestamp)
            let start = max(s, sessionStart)
            let end = min(e, sessionEnd)
            return end > start ? (start: start, end: end) : nil
        }

        guard !clampedOutages.isEmpty else { return result }

        // Iterate over all calendar days in the span. If the session extends beyond `maxDays`
        // of visible rows, aggregate later days into the last bucket (e.g. "Dag 10" holds day 10+).
        for dayIndex in 0..<daySpan {
            guard let dayStart = cal.date(byAdding: .day, value: dayIndex, to: startOfFirstDay) else { continue }
            guard let nextDayStart = cal.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let windowStart = max(dayStart, sessionStart)
            let windowEnd = min(nextDayStart, sessionEnd)
            if windowEnd <= windowStart { continue }

            var seconds: TimeInterval = 0
            for o in clampedOutages {
                let overlapStart = max(o.start, windowStart)
                let overlapEnd = min(o.end, windowEnd)
                if overlapEnd > overlapStart {
                    seconds += overlapEnd.timeIntervalSince(overlapStart)
                }
            }

            // Decide which visible bucket this day contributes to.
            let bucketIndex = min(dayIndex, daysToShow - 1)
            result[bucketIndex] += max(0, Int(round(seconds / 60.0)))
        }

        return result
    }

    private func showSensorErrorAlert(
        indexPath: IndexPath,
        sensorName: String?,
        countText: String,
        durationText: String,
        averageText: String?,
        perDayErrorMinutes: [Int]?
    ) {
        var message = "\nAntal sensorfel:     \(countText)\nTotal tid med fel:   \(durationText)"
        if let averageText = averageText {
            message += "\nMedel tid per fel:   \(averageText)"
        }

        if let perDay = perDayErrorMinutes, !perDay.isEmpty {
            message += "\n\nSensorfel (tid per kalenderdag)"
            for (idx, minutes) in perDay.enumerated() {
                let dayNumber = idx + 1
                message += "\nDag \(dayNumber):   \(minutes) min"
            }
        }

        let suffix: String
        if let sensorName = sensorName, !sensorName.isEmpty {
            suffix = " (\(sensorName))"
        } else {
            suffix = ""
        }

        let alert = UIAlertController(title: "⚠️ Sensorfel\(suffix)", message: message, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
            guard let self = self else { return }

            // Fade out the selection overlay smoothly, then deselect WITHOUT animation
            // (animated deselect can re-apply the selection state briefly -> "blink")
            if let cell = self.tableView.cellForRow(at: indexPath) {
                let overlay = cell.selectedBackgroundView
                UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: {
                    overlay?.alpha = 0
                }, completion: { _ in
                    // Deselect after fade, without triggering an additional UIKit selection animation.
                    self.tableView.deselectRow(at: indexPath, animated: false)
                })
            } else {
                self.tableView.deselectRow(at: indexPath, animated: false)
            }
        }))

        present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Ensure refresh is in flight so next tap is even more up-to-date
        refreshDexcomOutagesCacheIfNeeded()

        let entry = currentHistory()[indexPath.row]

        // Use master list (sorted desc) to define the session window
        guard let masterIndex = sensorHistory.firstIndex(where: { $0.date == entry.date && $0.note == entry.note }) else {
            showSensorErrorAlert(
                indexPath: indexPath,
                sensorName: parsedSensorName(fromNote: entry.note),
                countText: "--",
                durationText: "--",
                averageText: nil,
                perDayErrorMinutes: nil
            )
            return
        }

        let sessionStart = Date(timeIntervalSince1970: sensorHistory[masterIndex].date)
        let sessionEnd: Date
        if masterIndex == 0 {
            // Ongoing session
            sessionEnd = Date()
        } else {
            // Next newer sensor activation is the row above
            sessionEnd = Date(timeIntervalSince1970: sensorHistory[masterIndex - 1].date)
        }

        let startTs = sessionStart.timeIntervalSince1970
        let endTs = sessionEnd.timeIntervalSince1970

        // Outages whose NOTE happened within this session window
        let relevant = dexcomOutagesCache.filter { $0.noteTimestamp >= startTs && $0.noteTimestamp < endTs }

        guard !relevant.isEmpty else {
            showSensorErrorAlert(
                indexPath: indexPath,
                sensorName: parsedSensorName(fromNote: entry.note),
                countText: "--",
                durationText: "--",
                averageText: nil,
                perDayErrorMinutes: nil
            )
            return
        }

        let count = relevant.count
        let totalMinutes = relevant.reduce(0) { acc, item in
            acc + max(0, Int(round((item.endTimestamp - item.startTimestamp) / 60.0)))
        }
        let averageMinutes = count > 0 ? totalMinutes / count : 0
        let averageText = count > 0 ? "\(averageMinutes) min" : "--"
        let perDayMinutes = perCalendarDayErrorMinutes(outages: relevant, sessionStart: sessionStart, sessionEnd: sessionEnd, maxDays: 10)
        showSensorErrorAlert(
            indexPath: indexPath,
            sensorName: parsedSensorName(fromNote: entry.note),
            countText: "\(count) st",
            durationText: formatTotalDuration(minutes: totalMinutes),
            averageText: averageText,
            perDayErrorMinutes: perDayMinutes
        )
    }

    // MARK: - Swipe to Edit/Delete
    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let entry = currentHistory()[indexPath.row]

        let deleteAction = UIContextualAction(style: .destructive, title: "Radera") { [weak self] _, _, completion in
            guard let self = self else { completion(false); return }
            var stored = Storage.shared.sensorStartNotes
            // Remove the first matching entry (date+note) from storage
            if let idx = stored.firstIndex(where: { $0.date == entry.date && $0.note == entry.note }) {
                stored.remove(at: idx)
                Storage.shared.sensorStartNotes = stored
                // Update local datasources
                if let masterIdx = self.sensorHistory.firstIndex(where: { $0.date == entry.date && $0.note == entry.note }) {
                    self.sensorHistory.remove(at: masterIdx)
                }
                if let filteredIdx = self.filteredHistory.firstIndex(where: { $0.date == entry.date && $0.note == entry.note }) {
                    self.filteredHistory.remove(at: filteredIdx)
                }
                if self.isFiltering {
                    tableView.deleteRows(at: [indexPath], with: .automatic)
                } else {
                    tableView.deleteRows(at: [indexPath], with: .automatic)
                }
                completion(true)
            } else {
                completion(false)
            }
        }

        let editAction = UIContextualAction(style: .normal, title: "Redigera") { [weak self] _, _, completion in
            guard let self = self else { completion(false); return }
            let editVC = AddManualSensorNoteViewController()
            editVC.delegate = self
            editVC.configureForEditing(entry: entry, index: indexPath.row)
            let nav = UINavigationController(rootViewController: editVC)
            self.present(nav, animated: true)
            completion(true)
        }

        editAction.backgroundColor = UIColor.systemBlue

        let config = UISwipeActionsConfiguration(actions: [deleteAction, editAction])
        config.performsFirstActionWithFullSwipe = false
        return config
    }
    
    // MARK: - Add Manual Sensor Note
    
    @objc private func addManualSensorNote() {
        let addNoteVC = AddManualSensorNoteViewController()
        addNoteVC.delegate = self
        let navController = UINavigationController(rootViewController: addNoteVC)
        present(navController, animated: true)
    }
    
    // MARK: - Export Sensor History
    
    @objc private func exportSensorHistory() {
        DispatchQueue.global(qos: .background).async {
            do {
                let jsonData = try JSONEncoder().encode(self.sensorHistory)
                
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    LogManager.shared.log(category: .dexcom, message: "📤 Exporting JSON: \(jsonString)", isDebug: true)
                }

                // ✅ Save in the Documents Directory instead of tmp
                let fileManager = FileManager.default
                let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                let exportURL = documentsURL.appendingPathComponent("SensorHistory.json")

                try jsonData.write(to: exportURL, options: .atomic)

                DispatchQueue.main.async {
                    if fileManager.fileExists(atPath: exportURL.path) {
                        let activityVC = UIActivityViewController(activityItems: [exportURL], applicationActivities: nil)
                        self.present(activityVC, animated: true)
                    } else {
                        LogManager.shared.log(category: .dexcom, message: "❌ JSON file does not exist at \(exportURL.path)", isDebug: true)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    LogManager.shared.log(category: .dexcom, message: "❌ Failed to export sensor history: \(error)", isDebug: true)
                }
            }
        }
    }

    // MARK: - Import Sensor History
    
    @objc private func importSensorHistory() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }
}

// MARK: - Handle New Manual Notes
extension SensorHistoryViewController: AddManualSensorNoteDelegate {
    func didAddManualSensorNote(note: SensorStartHistoryEntry) {
        var storedHistory = Storage.shared.sensorStartNotes
        storedHistory.append(note)
        Storage.shared.sensorStartNotes = storedHistory
        
        loadSensorHistory() // Reload table with updated data
    }
    
    func didUpdateManualSensorNote(note: SensorStartHistoryEntry, at index: Int) {
        // Update the entry in persistent storage by matching on original index in current list
        var stored = Storage.shared.sensorStartNotes
        // Find the original entry we are replacing using the snapshot of the table's ordering
        let original = sensorHistory[index]
        if let storedIndex = stored.firstIndex(where: { $0.date == original.date && $0.note == original.note }) {
            stored[storedIndex] = note
            Storage.shared.sensorStartNotes = stored
        }
        // Refresh local cache and table order
        loadSensorHistory()
    }
}

extension SensorHistoryViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let fileURL = urls.first else { return }

        // ✅ Request access for iCloud Drive / Downloads
        if fileURL.startAccessingSecurityScopedResource() {
            defer { fileURL.stopAccessingSecurityScopedResource() } // Always clean up access

            let fileManager = FileManager.default
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let destinationURL = documentsURL.appendingPathComponent("ImportedSensorHistory.json")

            do {
                // ✅ Copy file into the app's Documents folder (bypassing permission issue)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL) // Ensure it's fresh
                }
                try fileManager.copyItem(at: fileURL, to: destinationURL)

                // ✅ Read from the local copy
                let jsonData = try Data(contentsOf: destinationURL)
                let importedHistory = try JSONDecoder().decode([SensorStartHistoryEntry].self, from: jsonData)

                DispatchQueue.main.async {
                    var storedHistory = Storage.shared.sensorStartNotes
                    for entry in importedHistory {
                        if !storedHistory.contains(where: { $0.date == entry.date && $0.note == entry.note }) {
                            storedHistory.append(entry)
                        }
                    }
                    
                    Storage.shared.sensorStartNotes = storedHistory
                    self.loadSensorHistory() // Reload UI
                    
                    LogManager.shared.log(category: .dexcom, message: "✅ Successfully imported sensor history from local copy", isDebug: true)
                }
            } catch {
                LogManager.shared.log(category: .dexcom, message: "❌ Failed to copy or import sensor history: \(error)", isDebug: true)
            }
        } else {
            LogManager.shared.log(category: .dexcom, message: "❌ Failed to access security-scoped resource for file: \(fileURL)", isDebug: true)
        }
    }
}

final class SensorSessionStatsViewController: ThemedTableViewController {
    private let buckets: SessionBuckets
    private let history: [SensorStartHistoryEntry]
    private let chartView: ScatterChartView = {
        let v = ScatterChartView()
        v.legend.enabled = false
        v.chartDescription.enabled = false
        v.rightAxis.enabled = false
        v.minOffset = 8
        // Interaction & zoom
        v.pinchZoomEnabled = false      // avoid diagonal zoom; we'll zoom X only
        v.doubleTapToZoomEnabled = true // double-tap zooms X
        v.scaleXEnabled = true          // allow horizontal zoom
        v.scaleYEnabled = false         // lock vertical scale (0–11 stays)
        v.dragEnabled = true            // allow horizontal pan after zoom
        v.highlightPerTapEnabled = false
        v.highlightPerDragEnabled = false
        v.drawMarkers = false
        v.maxVisibleCount = 1_000_000
        return v
    }()

    init(buckets: SessionBuckets, history: [SensorStartHistoryEntry]) {
        self.buckets = buckets
        self.history = history
        super.init(style: .insetGrouped)
    }

    // Helper for formatting average hours as X d Y tim
    private func avgText(count: Int, totalHours: Int) -> String {
        guard count > 0 else { return "–" }
        let avg = totalHours / count
        let d = avg / 24
        let h = avg % 24
        return "\(d) d \(h) tim"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateBackgroundForCurrentMode()
        tableView.backgroundColor = .clear
        tableView.isOpaque = false
        tableView.layer.backgroundColor = UIColor.clear.cgColor
        title = "Sessionstid sensorer"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissSelf)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        setupChartHeader()
        loadChartData()
    }

    private func setupChartHeader() {
        let container = UIView()
        container.backgroundColor = .clear
        container.isOpaque = false
        chartView.backgroundColor = .clear
        container.addSubview(chartView)
        container.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 260)
        chartView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chartView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            chartView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            chartView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            chartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
        ])
        tableView.tableHeaderView = container
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let header = tableView.tableHeaderView {
            let targetSize = CGSize(width: tableView.bounds.width, height: 260)
            if header.frame.size != targetSize {
                header.frame.size = targetSize
                tableView.tableHeaderView = header
            }
        }
    }

    private func monthStartsBetween(_ start: Date, _ end: Date) -> [Date] {
        var dates: [Date] = []
        let cal = Calendar(identifier: .gregorian)
        let startComp = cal.dateComponents([.year, .month], from: start)
        let first = cal.date(from: startComp) ?? start
        var current = first
        while current <= end {
            dates.append(current)
            current = cal.date(byAdding: .month, value: 1, to: current) ?? end.addingTimeInterval(1)
        }
        return dates
    }

    private func loadChartData() {
        guard history.count > 1 else { return }
        var histEntries: [ChartDataEntry] = []
        var histColors: [NSUIColor] = []
        for i in stride(from: history.count - 1, through: 1, by: -1) {
            let start = Date(timeIntervalSince1970: history[i].date)
            let end = Date(timeIntervalSince1970: history[i - 1].date)
            var interval = end.timeIntervalSince(start)
            if interval < 0 { interval = 0 }
            let hours = Int(interval / 3600)
            let days = min(11.0, Double(hours) / 24.0)
            // X = datum (starttid), Y = sessionslängd i dagar
            histEntries.append(ChartDataEntry(x: start.timeIntervalSince1970, y: days))
            if hours >= 228 {
                histColors.append(.systemGreen)
            } else if hours >= 120 {
                histColors.append(.systemOrange)
            } else {
                histColors.append(.systemRed)
            }
        }
        let histSet = ScatterChartDataSet(entries: histEntries, label: "")
        histSet.setColors(histColors, alpha: 1)
        histSet.setScatterShape(.circle)
        histSet.scatterShapeSize = 6
        histSet.drawValuesEnabled = false
        histSet.highlightEnabled = false

        // Add a single blue point for the ongoing session (index 0)
        var dataSets: [ChartDataSetProtocol] = [histSet]
        if let first = history.first {
            let start = Date(timeIntervalSince1970: first.date)
            var interval = Date().timeIntervalSince(start)
            if interval < 0 { interval = 0 }
            let hours = Int(interval / 3600)
            let days = min(11.0, Double(hours) / 24.0)
            let ongoingEntry = ChartDataEntry(x: start.timeIntervalSince1970, y: days)
            let ongoingSet = ScatterChartDataSet(entries: [ongoingEntry], label: "")
            ongoingSet.setColor(.systemBlue)
            ongoingSet.setScatterShape(.circle)
            ongoingSet.scatterShapeSize = 6
            ongoingSet.drawValuesEnabled = false
            ongoingSet.highlightEnabled = false
            dataSets.append(ongoingSet)
        }

        chartView.data = ScatterChartData(dataSets: dataSets)
        chartView.autoScaleMinMaxEnabled = false
        chartView.notifyDataSetChanged()

        // X-axel = datumintervall för avslutade sessioners starttider (utan pågående)
        let oldestStart = Date(timeIntervalSince1970: history.last!.date)
        let newestEnd = Date(timeIntervalSince1970: history[0].date)
        let xAxis = chartView.xAxis
        xAxis.axisMinimum = oldestStart.timeIntervalSince1970
        let rightPad: TimeInterval = 168 * 3600 // add seven days of padding so the last (blue) point isn't clipped
        xAxis.axisMaximum = newestEnd.timeIntervalSince1970 + rightPad
        xAxis.labelPosition = .bottom
        xAxis.granularity = 24 * 3600 // daglig
        xAxis.granularityEnabled = true
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "yyMMdd"
        xAxis.valueFormatter = DefaultAxisValueFormatter(block: { value, _ in
            return df.string(from: Date(timeIntervalSince1970: value))
        })
        // Keep X-axis labels readable: max ~6 labels regardless of zoom
        xAxis.setLabelCount(6, force: false)
        //xAxis.avoidFirstLastClippingEnabled = true

        // Y-axel = sessionslängd i dagar (0–11) med diskreta heltalsetiketter
        let yAxis = chartView.leftAxis
        yAxis.axisMinimum = 0
        yAxis.axisMaximum = 11
        yAxis.granularity = 1
        yAxis.valueFormatter = DefaultAxisValueFormatter(block: { value, _ in
            let iv = Int(round(value))
            // Show only even ticks between 0 and 11 (2,4,6,8,10) and append "d"
            if iv > 0 && iv < 11 && iv % 2 == 0 {
                return "\(iv)d"
            }
            return ""
        })
        yAxis.granularityEnabled = true

        // 🔹 Make X and Y grid lines dashed/dotted and more subtle
        let gridLineColor = NSUIColor.lightGray.withAlphaComponent(0.5) // Faint gray

        xAxis.gridColor = gridLineColor
        xAxis.gridLineWidth = 0.5 // Thin grid lines
        xAxis.gridLineDashLengths = [2, 2] // Dotted effect

        yAxis.gridColor = gridLineColor
        yAxis.gridLineWidth = 0.5
        yAxis.gridLineDashLengths = [2, 2] // Dotted effect

        chartView.rightAxis.enabled = false // Hide right Y-axis (already set, ensure stays off)

        chartView.setNeedsDisplay()
    }

    @objc private func dismissSelf() { dismiss(animated: true) }

    private enum Section: Int, CaseIterable { case counts, avgs }
    private enum CountRow: Int, CaseIterable { case header, all, lt1, d1to5, d5to9_5, gt9_5 }
    private enum AvgRow: Int, CaseIterable { case header, all, allExclLt1, lt1, d1to5, d5to9_5, gt9_5 }

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .counts: return CountRow.allCases.count
        case .avgs:   return AvgRow.allCases.count
        }
    }

    private func percent(_ count: Int) -> String {
        let total = max(1, buckets.total)
        let p = Double(count) * 100.0 / Double(total)
        return String(format: "%.0f%%", p)
    }

    private func rightText(count: Int) -> String { "\(count) st (\(percent(count)))" }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "cell")
        cell.selectionStyle = .none
        // Transparent cell so the themed gradient shows
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
        switch Section(rawValue: indexPath.section)! {
        case .counts:
            let row = CountRow(rawValue: indexPath.row)!
            switch row {
            case .header:
                cell.textLabel?.text = "Sessionstid"
                cell.detailTextLabel?.text = "Antal (Andel)"
                cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
                cell.detailTextLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
                cell.detailTextLabel?.textColor = .label
            case .all:
                cell.textLabel?.text = "Alla sensorer"
                cell.detailTextLabel?.text = "\(buckets.total) st (100%)"
                cell.detailTextLabel?.textColor = .label
            case .lt1:
                cell.textLabel?.text = "< 1 dagar"
                cell.textLabel?.textColor = .systemRed
                cell.detailTextLabel?.text = rightText(count: buckets.lt1d)
                cell.detailTextLabel?.textColor = .systemRed
            case .d1to5:
                cell.textLabel?.text = "1 - 5 dagar"
                cell.textLabel?.textColor = .systemRed
                cell.detailTextLabel?.text = rightText(count: buckets.d1to5)
                cell.detailTextLabel?.textColor = .systemRed
            case .d5to9_5:
                cell.textLabel?.text = "5 - 9.5 dagar"
                cell.textLabel?.textColor = .systemOrange
                cell.detailTextLabel?.text = rightText(count: buckets.d5to9_5)
                cell.detailTextLabel?.textColor = .systemOrange
            case .gt9_5:
                cell.textLabel?.text = "> 9.5 dagar"
                cell.textLabel?.textColor = .systemGreen
                cell.detailTextLabel?.text = rightText(count: buckets.gt9_5)
                cell.detailTextLabel?.textColor = .systemGreen
            }
        case .avgs:
            let row = AvgRow(rawValue: indexPath.row)!
            switch row {
            case .header:
                cell.textLabel?.text = "Sessionstid"
                cell.detailTextLabel?.text = "Medelvärde"
                cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
                cell.detailTextLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
                cell.detailTextLabel?.textColor = .label
            case .all:
                cell.textLabel?.text = "Alla sensorer"
                cell.detailTextLabel?.text = avgText(count: buckets.total, totalHours: buckets.hrs_total)
                cell.detailTextLabel?.textColor = .label
            case .allExclLt1:
                cell.textLabel?.text = "Alla utom < 1"
                let count = buckets.d1to5 + buckets.d5to9_5 + buckets.gt9_5
                let hours = buckets.hrs_d1to5 + buckets.hrs_d5to9_5 + buckets.hrs_gt9_5
                cell.detailTextLabel?.text = avgText(count: count, totalHours: hours)
                cell.detailTextLabel?.textColor = .label
            case .lt1:
                cell.textLabel?.text = "< 1 dagar"
                cell.textLabel?.textColor = .systemRed
                cell.detailTextLabel?.text = avgText(count: buckets.lt1d, totalHours: buckets.hrs_lt1d)
                cell.detailTextLabel?.textColor = .systemRed
            case .d1to5:
                cell.textLabel?.text = "1 - 5 dagar"
                cell.textLabel?.textColor = .systemRed
                cell.detailTextLabel?.text = avgText(count: buckets.d1to5, totalHours: buckets.hrs_d1to5)
                cell.detailTextLabel?.textColor = .systemRed
            case .d5to9_5:
                cell.textLabel?.text = "5 - 9.5 dagar"
                cell.textLabel?.textColor = .systemOrange
                cell.detailTextLabel?.text = avgText(count: buckets.d5to9_5, totalHours: buckets.hrs_d5to9_5)
                cell.detailTextLabel?.textColor = .systemOrange
            case .gt9_5:
                cell.textLabel?.text = "> 9.5 dagar"
                cell.textLabel?.textColor = .systemGreen
                cell.detailTextLabel?.text = avgText(count: buckets.gt9_5, totalHours: buckets.hrs_gt9_5)
                cell.detailTextLabel?.textColor = .systemGreen
            }
        }
        return cell
    }
}

// MARK: - UISearchBarDelegate
extension SensorHistoryViewController {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applyFilterAndReload()
    }
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        applyFilterAndReload()
    }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = nil
        applyFilterAndReload()
    }
}

