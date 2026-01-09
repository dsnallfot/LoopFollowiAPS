import UIKit
import Charts
import UniformTypeIdentifiers


struct PumpSessionBuckets {
    // Counts
    var lt1h: Int = 0        // < 1 h
    var h1to50: Int = 0      // 1 - 50 h
    var h50to70: Int = 0     // 50 - 70 h
    var gt70: Int = 0        // > 70 h

    // Total hours per bucket (for averages)
    var hrs_lt1h: Int = 0
    var hrs_h1to50: Int = 0
    var hrs_h50to70: Int = 0
    var hrs_gt70: Int = 0

    // Overall totals
    var total: Int { lt1h + h1to50 + h50to70 + gt70 }
    var hrs_total: Int { hrs_lt1h + hrs_h1to50 + hrs_h50to70 + hrs_gt70 }
}

class PumpHistoryViewController: ThemedViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {

    private var pumpHistory: [PumpChangeHistoryEntry] = []
    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    /// Snapshot när modalen öppnas – används för pågående session (från senaste pumpbyte till nu).
    private let openedAt = Date()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Pumplogg"
        //view.backgroundColor = .systemBackground
        updateBackgroundForCurrentMode()

        setupNavigationBar()
        setupTableView()
        setupConstraints()

        loadPumpHistoryFromStorage()
        fetchInitialPumpChangesIfNeeded()
    }

    // MARK: - UI setup

    private func setupNavigationBar() {
        // --- Left side: custom stack with controlled spacing and 2pt inset from the bubble edge ---
        let addBtn = UIButton(type: .system)
        addBtn.setImage(UIImage(systemName: "plus"), for: .normal)
        addBtn.tintColor = .label
        addBtn.addTarget(self, action: #selector(addManualPumpChange), for: .touchUpInside)

        let shareBtn = UIButton(type: .system)
        shareBtn.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareBtn.tintColor = .label
        shareBtn.addTarget(self, action: #selector(exportPumpHistory), for: .touchUpInside)

        let importBtn = UIButton(type: .system)
        importBtn.setImage(UIImage(systemName: "square.and.arrow.down"), for: .normal)
        importBtn.tintColor = .label
        importBtn.addTarget(self, action: #selector(importPumpHistory), for: .touchUpInside)

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

        let doneBtn = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(doneTapped)
        )

        let statsBtn = UIBarButtonItem(
            image: UIImage(systemName: "chart.bar.xaxis.ascending"),
            style: .plain,
            target: self,
            action: #selector(showPumpSessionStats)
        )

        navigationItem.leftBarButtonItem = leftItem
        navigationItem.rightBarButtonItems = [doneBtn, statsBtn]
    }

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PumpHistoryCell")
        // Themed background: let gradient show through
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.isOpaque = false
    }

    private func setupConstraints() {
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: guide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func addManualPumpChange() {
        let addVC = AddManualPumpViewController()
        addVC.delegate = self
        let nav = UINavigationController(rootViewController: addVC)
        present(nav, animated: true)
    }

    @objc private func showPumpSessionStats() {
        let history = Storage.shared.pumpChangeHistory.sorted { $0.date > $1.date }
        guard !history.isEmpty else { return }

        let buckets = computePumpSessionBuckets(from: history)
        let statsVC = PumpSessionStatsViewController(buckets: buckets, history: history)
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
    
    // MARK: - Export Pump History

    @objc private func exportPumpHistory() {
        // Exportera det som ligger i storage (inte bara aktuell filterad tabell)
        let historyToExport = Storage.shared.pumpChangeHistory

        DispatchQueue.global(qos: .background).async {
            do {
                let jsonData = try JSONEncoder().encode(historyToExport)

                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    LogManager.shared.log(category: .treatments, message: "📤 Exporting pump JSON: \(jsonString)", isDebug: true)
                }

                let fileManager = FileManager.default
                let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                let exportURL = documentsURL.appendingPathComponent("PumpHistory.json")

                try jsonData.write(to: exportURL, options: .atomic)

                DispatchQueue.main.async {
                    if fileManager.fileExists(atPath: exportURL.path) {
                        let activityVC = UIActivityViewController(activityItems: [exportURL], applicationActivities: nil)
                        self.present(activityVC, animated: true)
                    } else {
                        LogManager.shared.log(category: .treatments, message: "❌ Pump JSON file does not exist at \(exportURL.path)", isDebug: true)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    LogManager.shared.log(category: .treatments, message: "❌ Failed to export pump history: \(error)", isDebug: true)
                }
            }
        }
    }

    // MARK: - Import Pump History

    @objc private func importPumpHistory() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }

    // MARK: - Storage

    private func loadPumpHistoryFromStorage() {
        pumpHistory = Storage.shared.pumpChangeHistory.sorted { $0.date > $1.date }
        tableView.reloadData()
    }

    // MARK: - Nightscout initial fetch (~90 dagar)

    /// Enkel intern modell för CAge / Site Change från Nightscout.
    private struct PumpCageData: Codable {
        let created_at: String
    }

    private func fetchInitialPumpChangesIfNeeded() {
        // Om vi redan har historik i storage hoppar vi över första fetchen.
        guard Storage.shared.pumpChangeHistory.isEmpty else { return }

        let now = Date()
        guard let since = Calendar.current.date(byAdding: .day, value: -200, to: now) else { return }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(secondsFromGMT: 0)

        let params: [String: String] = [
            "find[eventType]": "Site Change",
            "find[created_at][$gte]": iso.string(from: since),
            "find[created_at][$lte]": iso.string(from: now)
        ]

        // Vi använder .cage för semantik, men endpointen är samma som treatments.
        NightscoutUtils.executeRequest(
            eventType: .cage,
            parameters: params
        ) { (result: Result<[PumpCageData], Error>) in
            switch result {
            case .failure(let error):
                LogManager.shared.log(
                    category: .treatments,
                    message: "❌ Failed to fetch pump Site Change history: \(error)",
                    isDebug: true
                )
            case .success(let cageEntries):
                var merged = Storage.shared.pumpChangeHistory
                for c in cageEntries {
                    guard let date = NightscoutUtils.parseDate(c.created_at) else { continue }
                    let entry = PumpChangeHistoryEntry(date: date.timeIntervalSince1970)
                    if !merged.contains(where: { $0.date == entry.date }) {
                        merged.append(entry)
                    }
                }
                merged.sort { $0.date > $1.date }
                Storage.shared.pumpChangeHistory = merged
                self.pumpHistory = merged
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - Helpers – sessionstid

    private func computePumpSessionBuckets(from history: [PumpChangeHistoryEntry]) -> PumpSessionBuckets {
        var buckets = PumpSessionBuckets()

        // Vi behöver minst två byten för att kunna definiera en avslutad pumppass-session
        guard history.count > 1 else { return buckets }

        // history förväntas vara sorterad DESC (0 = nyast)
        for i in 1..<history.count {
            let start = Date(timeIntervalSince1970: history[i].date)
            let end = Date(timeIntervalSince1970: history[i - 1].date)
            var interval = end.timeIntervalSince(start)
            if interval < 0 { interval = 0 }
            let hours = Int(interval / 3600)
            let clamped = min(hours, 80) // klipp vid 80h (72h + 8h grace)

            switch hours {
            case ..<1:
                buckets.lt1h += 1
                buckets.hrs_lt1h += clamped
            case 1..<50:
                buckets.h1to50 += 1
                buckets.hrs_h1to50 += clamped
            case 50..<70:
                buckets.h50to70 += 1
                buckets.hrs_h50to70 += clamped
            default:
                buckets.gt70 += 1
                buckets.hrs_gt70 += clamped
            }
        }

        return buckets
    }

    private func sessionColor(for hours: Int, isOngoing: Bool) -> UIColor {
        if isOngoing { return .systemBlue }
        if hours < 50 { return .systemRed }
        if hours < 70 { return .systemOrange }
        return .systemGreen
    }

    private func sessionInfo(for index: Int) -> (text: String, hours: Int, isOngoing: Bool) {
        let current = pumpHistory[index]
        let currentStart = Date(timeIntervalSince1970: current.date)
        let isOngoing = (index == 0)
        let endDate: Date = isOngoing ? openedAt : Date(timeIntervalSince1970: pumpHistory[index - 1].date)
        let interval = max(0, endDate.timeIntervalSince(currentStart))
        let hours = Int(interval / 3600)
        let prefix = isOngoing ? "Pågående" : "Session"
        return ("(\(prefix): \(hours) timmar)", hours, isOngoing)
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return pumpHistory.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "PumpHistoryCell",
            for: indexPath
        )

        let entry = pumpHistory[indexPath.row]
        let date = Date(timeIntervalSince1970: entry.date)

        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        let dateString = df.string(from: date)

        let sessionInfo = sessionInfo(for: indexPath.row)

        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        let smallBody = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: baseFont.withSize(baseFont.pointSize - 1))

        let attrsBase: [NSAttributedString.Key: Any] = [
            .font: smallBody,
            .foregroundColor: cell.textLabel?.textColor ?? UIColor.label
        ]

        let sessionAttrs: [NSAttributedString.Key: Any] = [
            .font: smallBody,
            .foregroundColor: sessionColor(for: sessionInfo.hours, isOngoing: sessionInfo.isOngoing)
        ]

        let composed = NSMutableAttributedString()
        composed.append(NSAttributedString(string: dateString, attributes: attrsBase))
        composed.append(NSAttributedString(string: " \(sessionInfo.text)\n", attributes: sessionAttrs))
        composed.append(NSAttributedString(string: "Omnipod Dash startades", attributes: attrsBase))

        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.attributedText = composed
        
        // Transparent cell so the themed gradient shows through
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.backgroundView = nil
        if #available(iOS 14.0, *) {
            var bg = UIBackgroundConfiguration.clear()
            bg.backgroundColor = .clear
            cell.backgroundConfiguration = bg
        }
        cell.textLabel?.backgroundColor = .clear
        cell.detailTextLabel?.backgroundColor = .clear

        return cell
    }

    // MARK: - Swipe actions (Redigera / Radera)

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {

        let entry = pumpHistory[indexPath.row]

        let deleteAction = UIContextualAction(style: .destructive, title: "Radera") { _, _, completion in
            var stored = Storage.shared.pumpChangeHistory
            if let idx = stored.firstIndex(where: { $0.date == entry.date }) {
                stored.remove(at: idx)
                Storage.shared.pumpChangeHistory = stored
            }
            self.pumpHistory.removeAll(where: { $0.date == entry.date })
            tableView.deleteRows(at: [indexPath], with: .automatic)
            completion(true)
        }

        let editAction = UIContextualAction(style: .normal, title: "Redigera") { _, _, completion in
            let editVC = AddManualPumpViewController()
            editVC.delegate = self
            editVC.configureForEditing(entry: entry, index: indexPath.row)
            let nav = UINavigationController(rootViewController: editVC)
            self.present(nav, animated: true)
            completion(true)
        }

        editAction.backgroundColor = .systemBlue

        let config = UISwipeActionsConfiguration(actions: [deleteAction, editAction])
        config.performsFirstActionWithFullSwipe = false
        return config
    }
}

// MARK: - AddManualPumpDelegate

extension PumpHistoryViewController: AddManualPumpDelegate {
    func didAddManualPumpChange(entry: PumpChangeHistoryEntry) {
        var stored = Storage.shared.pumpChangeHistory
        if !stored.contains(where: { $0.date == entry.date }) {
            stored.append(entry)
            stored.sort { $0.date > $1.date }
            Storage.shared.pumpChangeHistory = stored
        }
        pumpHistory = stored
        tableView.reloadData()
    }

    func didUpdateManualPumpChange(entry: PumpChangeHistoryEntry, at index: Int) {
        var stored = Storage.shared.pumpChangeHistory

        // Original entry i tabellens nuvarande ordning
        let original = pumpHistory[index]
        if let storedIndex = stored.firstIndex(where: { $0.date == original.date }) {
            stored[storedIndex] = entry
            stored.sort { $0.date > $1.date }
            Storage.shared.pumpChangeHistory = stored
        }
        pumpHistory = stored
        tableView.reloadData()
    }
}


final class PumpSessionStatsViewController: ThemedTableViewController {
    private let buckets: PumpSessionBuckets
    private let history: [PumpChangeHistoryEntry]
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
        v.scaleYEnabled = false         // lock vertical scale (0–80 stays)
        v.dragEnabled = true            // allow horizontal pan after zoom
        v.highlightPerTapEnabled = false
        v.highlightPerDragEnabled = false
        v.drawMarkers = false
        v.maxVisibleCount = 1_000_000
        return v
    }()

    init(buckets: PumpSessionBuckets, history: [PumpChangeHistoryEntry]) {
        self.buckets = buckets
        self.history = history
        super.init(style: .insetGrouped)
    }

    // Helper for formatting average hours as "X h"
    private func avgText(count: Int, totalHours: Int) -> String {
        guard count > 0 else { return "–" }
        let avg = totalHours / count
        return "\(avg) h"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateBackgroundForCurrentMode()
        tableView.backgroundColor = .clear
        tableView.isOpaque = false
        tableView.layer.backgroundColor = UIColor.clear.cgColor
        title = "Sessionstid pumpar"
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

    private func loadChartData() {
        guard history.count > 1 else { return }
        var histEntries: [ChartDataEntry] = []
        var histColors: [NSUIColor] = []
        // history ska vara sorterad DESC (0 = nyast)
        for i in stride(from: history.count - 1, through: 1, by: -1) {
            let start = Date(timeIntervalSince1970: history[i].date)
            let end = Date(timeIntervalSince1970: history[i - 1].date)
            var interval = end.timeIntervalSince(start)
            if interval < 0 { interval = 0 }
            let hours = Int(interval / 3600)
            let clampedHours = min(hours, 80) // klipp vid 80h
            let y = Double(clampedHours)

            // X = datum (starttid), Y = sessionslängd i timmar (0–80)
            histEntries.append(ChartDataEntry(x: start.timeIntervalSince1970, y: y))

            let color: NSUIColor
            if hours >= 70 {
                color = .systemGreen
            } else if hours >= 50 {
                color = .systemOrange
            } else {
                color = .systemRed
            }
            histColors.append(color)
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
            let clampedHours = min(hours, 80)
            let y = Double(clampedHours)

            let ongoingEntry = ChartDataEntry(x: start.timeIntervalSince1970, y: y)
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
        let rightPad: TimeInterval = 168 * 3600 // add seven days of padding so the last point isn't clipped
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
        xAxis.setLabelCount(6, force: false)

        // Y-axel = sessionslängd i timmar (0–80)
        let yAxis = chartView.leftAxis
        yAxis.axisMinimum = 0
        yAxis.axisMaximum = 80
        yAxis.granularity = 10
        yAxis.valueFormatter = DefaultAxisValueFormatter(block: { value, _ in
            let iv = Int(round(value))
            if iv % 20 == 0 { // visa 0,20,40,60,80
                return "\(iv)h"
            }
            return ""
        })
        yAxis.granularityEnabled = true

        // 🔹 Make X and Y grid lines dashed/dotted and more subtle
        let gridLineColor = NSUIColor.lightGray.withAlphaComponent(0.5)

        xAxis.gridColor = gridLineColor
        xAxis.gridLineWidth = 0.5
        xAxis.gridLineDashLengths = [2, 2]

        yAxis.gridColor = gridLineColor
        yAxis.gridLineWidth = 0.5
        yAxis.gridLineDashLengths = [2, 2]

        chartView.rightAxis.enabled = false
        chartView.setNeedsDisplay()
    }

    @objc private func dismissSelf() { dismiss(animated: true) }

    private enum Section: Int, CaseIterable { case counts, avgs }
    private enum CountRow: Int, CaseIterable { case header, all, lt1, h1to50, h50to70, gt70 }
    private enum AvgRow: Int, CaseIterable { case header, all, allExclLt1, lt1, h1to50, h50to70, gt70 }

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
                cell.textLabel?.text = "Alla pumpar"
                cell.detailTextLabel?.text = "\(buckets.total) st (100%)"
                cell.detailTextLabel?.textColor = .label
            case .lt1:
                cell.textLabel?.text = "< 1 h"
                cell.textLabel?.textColor = .systemRed
                cell.detailTextLabel?.text = rightText(count: buckets.lt1h)
                cell.detailTextLabel?.textColor = .systemRed
            case .h1to50:
                cell.textLabel?.text = "1 - 50 h"
                cell.textLabel?.textColor = .systemRed
                cell.detailTextLabel?.text = rightText(count: buckets.h1to50)
                cell.detailTextLabel?.textColor = .systemRed
            case .h50to70:
                cell.textLabel?.text = "50 - 70 h"
                cell.textLabel?.textColor = .systemOrange
                cell.detailTextLabel?.text = rightText(count: buckets.h50to70)
                cell.detailTextLabel?.textColor = .systemOrange
            case .gt70:
                cell.textLabel?.text = "> 70 h"
                cell.textLabel?.textColor = .systemGreen
                cell.detailTextLabel?.text = rightText(count: buckets.gt70)
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
                cell.textLabel?.text = "Alla pumpar"
                cell.detailTextLabel?.text = avgText(count: buckets.total, totalHours: buckets.hrs_total)
                cell.detailTextLabel?.textColor = .label
            case .allExclLt1:
                cell.textLabel?.text = "Alla utom < 1"
                let count = buckets.h1to50 + buckets.h50to70 + buckets.gt70
                let hours = buckets.hrs_h1to50 + buckets.hrs_h50to70 + buckets.hrs_gt70
                cell.detailTextLabel?.text = avgText(count: count, totalHours: hours)
                cell.detailTextLabel?.textColor = .label
            case .lt1:
                cell.textLabel?.text = "< 1 h"
                cell.textLabel?.textColor = .systemRed
                cell.detailTextLabel?.text = avgText(count: buckets.lt1h, totalHours: buckets.hrs_lt1h)
                cell.detailTextLabel?.textColor = .systemRed
            case .h1to50:
                cell.textLabel?.text = "1 - 50 h"
                cell.textLabel?.textColor = .systemRed
                cell.detailTextLabel?.text = avgText(count: buckets.h1to50, totalHours: buckets.hrs_h1to50)
                cell.detailTextLabel?.textColor = .systemRed
            case .h50to70:
                cell.textLabel?.text = "50 - 70 h"
                cell.textLabel?.textColor = .systemOrange
                cell.detailTextLabel?.text = avgText(count: buckets.h50to70, totalHours: buckets.hrs_h50to70)
                cell.detailTextLabel?.textColor = .systemOrange
            case .gt70:
                cell.textLabel?.text = "> 70 h"
                cell.textLabel?.textColor = .systemGreen
                cell.detailTextLabel?.text = avgText(count: buckets.gt70, totalHours: buckets.hrs_gt70)
                cell.detailTextLabel?.textColor = .systemGreen
            }
        }
        return cell
    }
}

// MARK: - UIDocumentPickerDelegate

extension PumpHistoryViewController {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let fileURL = urls.first else { return }

        // ✅ Request access for iCloud Drive / Downloads
        if fileURL.startAccessingSecurityScopedResource() {
            defer { fileURL.stopAccessingSecurityScopedResource() } // Always clean up access

            let fileManager = FileManager.default
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let destinationURL = documentsURL.appendingPathComponent("ImportedPumpHistory.json")

            do {
                // ✅ Copy file into the app's Documents folder (bypassing permission issue)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL) // Ensure it's fresh
                }
                try fileManager.copyItem(at: fileURL, to: destinationURL)

                // ✅ Read from the local copy
                let jsonData = try Data(contentsOf: destinationURL)
                let importedHistory = try JSONDecoder().decode([PumpChangeHistoryEntry].self, from: jsonData)

                DispatchQueue.main.async {
                    var storedHistory = Storage.shared.pumpChangeHistory
                    for entry in importedHistory {
                        if !storedHistory.contains(where: { $0.date == entry.date }) {
                            storedHistory.append(entry)
                        }
                    }

                    storedHistory.sort { $0.date > $1.date }
                    Storage.shared.pumpChangeHistory = storedHistory
                    self.pumpHistory = storedHistory
                    self.tableView.reloadData()

                    LogManager.shared.log(
                        category: .treatments,
                        message: "✅ Successfully imported pump history from local copy",
                        isDebug: true
                    )
                }
            } catch {
                LogManager.shared.log(
                    category: .treatments,
                    message: "❌ Failed to copy or import pump history: \(error)",
                    isDebug: true
                )
            }
        } else {
            LogManager.shared.log(
                category: .treatments,
                message: "❌ Failed to access security-scoped resource for pump file: \(fileURL)",
                isDebug: true
            )
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        LogManager.shared.log(
            category: .treatments,
            message: "ℹ️ Pump history import cancelled",
            isDebug: true
        )
    }
}

