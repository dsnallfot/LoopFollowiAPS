//
//  SensorHistoryViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-03-09.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
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

class SensorHistoryViewController: UITableViewController {
    
    private var sensorHistory: [SensorStartHistoryEntry] = []
    private let openedAt = Date() // snapshot when modal opened

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Sensorhistorik"
        setupNavigationBar()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SensorHistoryCell")
        loadSensorHistory()
    }
    
    // MARK: - Navigation Bar Setup
    
    private func setupNavigationBar() {
        let addButton = UIBarButtonItem(
            image: UIImage(systemName: "plus.circle"),
            style: .plain,
            target: self,
            action: #selector(addManualSensorNote)
        )

        let shareButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"), // Export/Share
            style: .plain,
            target: self,
            action: #selector(exportSensorHistory)
        )

        let importButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.down"), // Import
            style: .plain,
            target: self,
            action: #selector(importSensorHistory)
        )

        navigationItem.leftBarButtonItems = [addButton, shareButton, importButton]

        let infoButton = UIBarButtonItem(
            image: UIImage(systemName: "info.circle"),
            style: .plain,
            target: self,
            action: #selector(showSessionStats)
        )

        let doneButton = UIBarButtonItem(
            title: "Klar",
            style: .done,
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
        present(nav, animated: true)
    }

    private func loadSensorHistory() {
        sensorHistory = Storage.shared.sensorStartNotes
        sensorHistory.sort { $0.date > $1.date }
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

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sensorHistory.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SensorHistoryCell", for: indexPath)
        let entry = sensorHistory[indexPath.row]
        let cleanedNote = entry.note
            .replacingOccurrences(of: "+0000", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let formattedDate = dateFormatter.string(from: Date(timeIntervalSince1970: entry.date))

        // Build: "<date> <session-info>" (first line), then "<note>" (second line)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: cell.textLabel?.font as Any,
            .foregroundColor: cell.textLabel?.textColor ?? UIColor.label
        ]
        let append = sessionAppendInfo(for: indexPath.row)
        let sessionAttrs: [NSAttributedString.Key: Any] = [
            .font: cell.textLabel?.font as Any,
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
        return cell
    }

    private func sessionAppendInfo(for index: Int) -> (text: String, color: UIColor) {
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

        let prefix = isOngoing ? " (Pågående: " : " (Sessionstid: "
        var snippet = "\(prefix)\(days) d \(hours) tim)"
        if !isOngoing && totalHours < 24 { snippet += " ⛔️" }
        return (snippet, color)
    }

    // MARK: - Swipe to Edit/Delete
    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let entry = sensorHistory[indexPath.row]

        let deleteAction = UIContextualAction(style: .destructive, title: "Radera") { [weak self] _, _, completion in
            guard let self = self else { completion(false); return }
            var stored = Storage.shared.sensorStartNotes
            // Remove the first matching entry (date+note) from storage
            if let idx = stored.firstIndex(where: { $0.date == entry.date && $0.note == entry.note }) {
                stored.remove(at: idx)
                Storage.shared.sensorStartNotes = stored
                // Update local datasource and table view
                self.sensorHistory.remove(at: indexPath.row)
                tableView.deleteRows(at: [indexPath], with: .automatic)
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
                    print("📤 Exporting JSON: \(jsonString)")
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
                        print("❌ JSON file does not exist at \(exportURL.path)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("❌ Failed to export sensor history: \(error)")
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
                    
                    print("✅ Successfully imported sensor history from local copy")
                }
            } catch {
                print("❌ Failed to copy or import sensor history: \(error)")
            }
        } else {
            print("❌ Failed to access security-scoped resource for file: \(fileURL)")
        }
    }
}

final class SensorSessionStatsViewController: UITableViewController {
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
        title = "Sessionstid sensorer"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .done,
            target: self,
            action: #selector(dismissSelf)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        setupChartHeader()
        loadChartData()
    }

    private func setupChartHeader() {
        let container = UIView()
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
        var entries: [ChartDataEntry] = []
        var colors: [NSUIColor] = []
        for i in stride(from: history.count - 1, through: 1, by: -1) {
            let start = Date(timeIntervalSince1970: history[i].date)
            let end = Date(timeIntervalSince1970: history[i - 1].date)
            var interval = end.timeIntervalSince(start)
            if interval < 0 { interval = 0 }
            let hours = Int(interval / 3600)
            let days = min(11.0, Double(hours) / 24.0)
            // X = datum (starttid), Y = sessionslängd i dagar
            entries.append(ChartDataEntry(x: start.timeIntervalSince1970, y: days))
            if hours >= 228 {
                colors.append(.systemGreen)
            } else if hours >= 120 {
                colors.append(.systemOrange)
            } else {
                colors.append(.systemRed)
            }
        }
        let set = ScatterChartDataSet(entries: entries, label: "")
        set.setColors(colors, alpha: 1)
        set.setScatterShape(.circle)
        set.scatterShapeSize = 10 // bigger points
        set.drawValuesEnabled = false
        // Disable per-datapoint highlighting
        set.highlightEnabled = false
        chartView.data = ScatterChartData(dataSet: set)
        chartView.autoScaleMinMaxEnabled = false
        chartView.notifyDataSetChanged()

        // X-axel = datumintervall för avslutade sessioners starttider (utan pågående)
        let oldestStart = Date(timeIntervalSince1970: history.last!.date)
        let newestEnd = Date(timeIntervalSince1970: history[0].date)
        let xAxis = chartView.xAxis
        xAxis.axisMinimum = oldestStart.timeIntervalSince1970
        xAxis.axisMaximum = newestEnd.timeIntervalSince1970
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
