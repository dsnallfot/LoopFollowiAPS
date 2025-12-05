import UIKit
import Charts

/// Enkel loggvy för fingerstick / BG Check, inspirerad av GlucoseView.
final class BGCheckView: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Model

    struct BGCheckEntry {
        let date: Date
        let mmol: Double
        let hasDextroNearby: Bool
    }

    private var entries: [BGCheckEntry] = []

    // MARK: - UI

    private let tableView = UITableView(frame: .zero, style: .plain)

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private let valueFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "sv_SE")
        nf.minimumFractionDigits = 1
        nf.maximumFractionDigits = 1
        return nf
    }()

    private var activityIndicator: UIActivityIndicatorView?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Fingerstick"
        view.backgroundColor = .systemBackground

        setupNavigationBar()
        setupTableView()
        setupConstraints()

        loadBGChecks()
    }

    // MARK: - Nav bar

    private func setupNavigationBar() {
        // Reload-knapp (samma look & feel som GlucoseView)
        let reload = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshTapped)
        )

        navigationItem.leftBarButtonItem = reload

        // Klar-knapp till höger, så det känns som Treatments/Glucose
        let done = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(doneTapped)
        )

        let statsBtn = UIBarButtonItem(
            image: UIImage(systemName: "info"),
            style: .plain,
            target: self,
            action: #selector(showBGCheckStats)
        )

        navigationItem.rightBarButtonItems = [done, statsBtn]
    }

    @objc private func doneTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func refreshTapped() {
        loadBGChecks()
    }

    @objc private func showBGCheckStats() {
        let calendar = Calendar.current
        let now = Date()
        let daysBack = min(NightscoutCache.retentionDays, 90)

        // Startdatum = början av dagen (daysBack-1) dagar bakåt
        guard let startDay = calendar.date(byAdding: .day, value: -(daysBack - 1), to: calendar.startOfDay(for: now)) else {
            return
        }

        // Bygg en array av alla dagar i intervallet, med default 0 stick per dag
        var days: [Date] = []
        var counts: [Int] = []
        var dextroCounts: [Int] = []
        days.reserveCapacity(daysBack)
        counts.reserveCapacity(daysBack)
        dextroCounts.reserveCapacity(daysBack)

        for offset in 0..<daysBack {
            if let day = calendar.date(byAdding: .day, value: offset, to: startDay) {
                days.append(day)
                counts.append(0)
                dextroCounts.append(0)
            }
        }

        // Snabb lookup för dag -> index i counts
        var indexByDay: [Date: Int] = [:]
        for (idx, day) in days.enumerated() {
            indexByDay[calendar.startOfDay(for: day)] = idx
        }

        // Räkna fingerstick per dag inom perioden och dextro per dag
        for entry in entries {
            if entry.date < startDay || entry.date > now { continue }
            let dayStart = calendar.startOfDay(for: entry.date)
            if let idx = indexByDay[dayStart] {
                counts[idx] += 1
                if entry.hasDextroNearby {
                    dextroCounts[idx] += 1
                }
            }
        }

        let statsVC = BGCheckStatsViewController(days: days, counts: counts, dextroCounts: dextroCounts)
        let nav = UINavigationController(rootViewController: statsVC)
        present(nav, animated: true)
    }

    // MARK: - Setup table

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BGCheckCell")
        tableView.rowHeight = 50
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
    }

    private func setupConstraints() {
        let safe = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: safe.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: safe.bottomAnchor)
        ])
    }

    // MARK: - Loading from cache

    private func showActivity() {
        if activityIndicator == nil {
            let ind = UIActivityIndicatorView(style: .medium)
            ind.hidesWhenStopped = true
            activityIndicator = ind
            navigationItem.titleView = ind
        }
        activityIndicator?.startAnimating()
    }

    private func hideActivity() {
        activityIndicator?.stopAnimating()
        navigationItem.titleView = nil
        activityIndicator = nil
    }

    /// Hämtar alla BG Check-treatments från cachen och mappar till BGCheckEntry.
    /// Hämtar alla BG Check-treatments från cachen och mappar till BGCheckEntry.
    private func loadBGChecks() {
        showActivity()

        Task {
            let now = Date()
            let cal = Calendar.current

            // Hämta t.ex. hela cachefönstret (samma retention som övrig cache)
            let start = cal.date(
                byAdding: .day,
                value: -NightscoutCache.retentionDays,
                to: now
            ) ?? now.addingTimeInterval(-90 * 24 * 60 * 60)

            // Antag att NightscoutCache.loadWindow(from:to:) returnerar (sgv, treatments)
            let (_, treatments) = await NightscoutCache.loadWindow(from: start, to: now)

            // 1) Plocka ut alla "dextro-treatments":
            //    • eventType == "Carb Correction"
            //    • carbs > 0
            //    • notes innehåller minst en "🍬"
            let dextroTreatments: [TreatmentJSON] = treatments.filter { t in
                guard t.eventType == "Carb Correction" else { return false }
                guard let carbs = t.carbs, carbs > 0 else { return false }
                guard let notes = t.notes, notes.contains("🍬") else { return false }
                return true
            }

            let windowSeconds: TimeInterval = 10 * 60 // ±10 min

            // 2) Bygg BGCheckEntry och sätt hasDextroNearby om vi hittar en dextro inom ±10 min
            let bgChecks: [BGCheckEntry] = treatments.compactMap { (t) -> BGCheckEntry? in
                guard t.eventType == "BG Check" else { return nil }

                // Datum – använd createdAt (från created_at) om möjligt, annars date
                let date = t.created_at

                guard let raw = t.glucose else {
                    return nil
                }

                let mmol: Double
                if let units = t.units, units.lowercased().contains("mmol") {
                    mmol = raw
                } else {
                    // mg/dL -> mmol/L
                    mmol = raw / 18.0182
                }

                // Finns det en dextro-treatment inom ±10 minuter?
                let hasDextroNearby = dextroTreatments.contains { dextro in
                    abs(dextro.created_at.timeIntervalSince(date)) <= windowSeconds
                }

                return BGCheckEntry(
                    date: date,
                    mmol: mmol,
                    hasDextroNearby: hasDextroNearby
                )
            }
            .sorted { $0.date > $1.date } // nyast överst

            await MainActor.run {
                self.entries = bgChecks
                self.tableView.reloadData()
                self.hideActivity()
            }
        }
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return entries.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BGCheckCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "BGCheckCell")
        cell.textLabel?.numberOfLines = 1

        let entry = entries[indexPath.row]

        // Leading SF Symbol + värde i mmol/L
        let mmolString = valueFormatter.string(from: NSNumber(value: entry.mmol)) ?? String(format: "%.1f", entry.mmol)

        var text = " \(mmolString) mmol/L"
        if entry.hasDextroNearby {
            text += " • 🍬"   // 👈 markera fingerstick med dextro inom ±10 min
        }

        cell.textLabel?.text = text
        cell.textLabel?.font = .systemFont(ofSize: 17)

        // SF-symbol i imageView (leading)
        cell.imageView?.image = UIImage(systemName: "drop.fill")
        cell.imageView?.tintColor = .systemRed

        // Right-aligned full date + time
        let rightLabel = UILabel()
        rightLabel.text = DateFormatter.localizedString(from: entry.date, dateStyle: .short, timeStyle: .short)
        rightLabel.font = .systemFont(ofSize: 15)
        rightLabel.textColor = .secondaryLabel
        rightLabel.textAlignment = .right
        rightLabel.sizeToFit()
        cell.accessoryView = rightLabel

        cell.selectionStyle = .default
        cell.accessoryType = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let entry = entries[indexPath.row]
        let startDate = entry.date

        // Låt raden highlightas kort enligt default-beteende
        tableView.deselectRow(at: indexPath, animated: true)

        // Hitta MainViewController via root UITabBarController för att få events,
        // men presentera modalen härifrån så vi kommer tillbaka hit när den stängs.

        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first(where: { $0.isKeyWindow }),
            let tabBar = window.rootViewController as? UITabBarController,
            let tabViewControllers = tabBar.viewControllers
        else {
            return
        }

        var mainVC: MainViewController?

        for (index, vc) in tabViewControllers.enumerated() {
            if let nav = vc as? UINavigationController {

                if let candidate = nav.viewControllers.first(where: { $0 is MainViewController }) as? MainViewController {
                    mainVC = candidate
                    break
                }
            } else if let candidate = vc as? MainViewController {
                mainVC = candidate
                break
            }
        }

        guard let mainVC else {
            return
        }

        // Bygg events via MainViewController, men presentera modalen härifrån.
        let events = mainVC.buildEventsForMealAnalysis()

        let analysisVC = MealAnalysisView(
            events: events,
            initialStart: startDate,
            modalWithTimestamp: true,
            modalTitleString: "Utv. efter Stick"
        )
        let nav = UINavigationController(rootViewController: analysisVC)
        nav.modalPresentationStyle = .formSheet
        self.present(nav, animated: true)
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
}

final class BGCheckStatsViewController: UITableViewController {

    // Full data set (upp till t.ex. 90 dagar)
    private let allDays: [Date]
    private let allCounts: [Int]
    private let allDextroCounts: [Int]

    // Aktuell vy (styrd av segmented control)
    private var selectedDays: [Date] = []
    private var selectedCounts: [Int] = []
    private var selectedDextroCounts: [Int] = []

    private enum PeriodOption: CaseIterable {
        case d7, d14, d30, d90

        var days: Int {
            switch self {
            case .d7:  return 7
            case .d14: return 14
            case .d30: return 30
            case .d90: return 90
            }
        }

        var title: String {
            switch self {
            case .d7:  return "7 d"
            case .d14: return "14 d"
            case .d30: return "30 d"
            case .d90: return "90 d"
            }
        }
    }

    private var selectedPeriod: PeriodOption = .d90

    private lazy var periodControl: UISegmentedControl = {
        let items = PeriodOption.allCases.map { $0.title }
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = PeriodOption.allCases.firstIndex(of: selectedPeriod) ?? (items.count - 1)
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
        v.maxVisibleCount = 1000000
        return v
    }()

    init(days: [Date], counts: [Int], dextroCounts: [Int]) {
        self.allDays = days
        self.allCounts = counts
        self.allDextroCounts = dextroCounts
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func defaultPeriod() -> PeriodOption {
        let count = allDays.count
        if count >= 90 { return .d90 }
        if count >= 30 { return .d30 }
        if count >= 14 { return .d14 }
        if count >= 7  { return .d7 }
        return .d7
    }

    private func applyPeriod(_ period: PeriodOption) {
        selectedPeriod = period
        let total = allDays.count
        guard total > 0 else {
            selectedDays = []
            selectedCounts = []
            selectedDextroCounts = []
            chartView.data = nil
            tableView.reloadData()
            return
        }

        let n = min(period.days, total)
        let startIndex = max(0, total - n)
        selectedDays = Array(allDays[startIndex..<total])
        selectedCounts = Array(allCounts[startIndex..<total])
        selectedDextroCounts = Array(allDextroCounts[startIndex..<total])

        loadChartData()
        tableView.reloadData()
    }

    @objc private func periodChanged(_ sender: UISegmentedControl) {
        let index = sender.selectedSegmentIndex
        guard index >= 0 && index < PeriodOption.allCases.count else { return }
        let period = PeriodOption.allCases[index]
        applyPeriod(period)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stickstatistik"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissSelf)
        )

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BGStatsCell")

        // Välj en rimlig defaultperiod baserat på hur många dagar vi har
        let initialPeriod = defaultPeriod()
        selectedPeriod = initialPeriod
        if let idx = PeriodOption.allCases.firstIndex(of: initialPeriod) {
            periodControl.selectedSegmentIndex = idx
        }

        setupChartHeader()
        applyPeriod(initialPeriod)
    }

    // MARK: - Chart header

    private func setupChartHeader() {
        let container = UIView()
        container.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 300)

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
            chartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
        ])

        tableView.tableHeaderView = container
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let header = tableView.tableHeaderView {
            let targetSize = CGSize(width: tableView.bounds.width, height: 300)
            if header.frame.size != targetSize {
                header.frame.size = targetSize
                tableView.tableHeaderView = header
            }
        }
    }

    private func loadChartData() {
        guard selectedDays.count == selectedCounts.count, !selectedDays.isEmpty else {
            chartView.data = nil
            chartView.setNeedsDisplay()
            return
        }

        var entries: [BarChartDataEntry] = []
        entries.reserveCapacity(selectedDays.count)

        var maxCount = 0
        for (idx, count) in selectedCounts.enumerated() {
            entries.append(BarChartDataEntry(x: Double(idx), y: Double(count)))
            if count > maxCount { maxCount = count }
        }

        let dataSet = BarChartDataSet(entries: entries, label: "")
        dataSet.setColor(.systemRed)
        dataSet.drawValuesEnabled = false

        let data = BarChartData(dataSet: dataSet)
        chartView.data = data
        chartView.autoScaleMinMaxEnabled = false
        chartView.notifyDataSetChanged()

        // X-axis labels = datum (kompakt format) för varje index
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "dd/MM"

        let labels = selectedDays.map { df.string(from: $0) }
        let xAxis = chartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.granularity = 1
        xAxis.granularityEnabled = true
        xAxis.valueFormatter = IndexAxisValueFormatter(values: labels)
        xAxis.setLabelCount(min(6, labels.count), force: false)

        // Y-axel – dynamiskt max utifrån högsta antal stick på en dag
        let yAxis = chartView.leftAxis
        yAxis.axisMinimum = 0
        let maxY = max(1, maxCount)
        yAxis.axisMaximum = Double(maxY) * 1.2
        yAxis.granularity = 1
        yAxis.granularityEnabled = true

        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.5)
        xAxis.gridColor = gridLineColor
        xAxis.gridLineWidth = 0.5
        xAxis.gridLineDashLengths = [2, 2]

        yAxis.gridColor = gridLineColor
        yAxis.gridLineWidth = 0.5
        yAxis.gridLineDashLengths = [2, 2]

        chartView.rightAxis.enabled = false
        chartView.setNeedsDisplay()
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    // MARK: - Stats helpers

    private var totalDays: Int { selectedDays.count }
    private var daysWithSticks: Int { selectedCounts.filter { $0 > 0 }.count }
    private var totalSticks: Int { selectedCounts.reduce(0, +) }
    private var totalDextroSticks: Int { selectedDextroCounts.reduce(0, +) }
    private var maxSticksPerDay: Int { selectedCounts.max() ?? 0 }

    private func longestStreakWithoutSticks() -> Int {
        var best = 0
        var current = 0
        for c in selectedCounts {
            if c == 0 {
                current += 1
                if current > best { best = current }
            } else {
                current = 0
            }
        }
        return best
    }

    private func percentageString(_ numerator: Int, _ denominator: Int) -> String {
        guard denominator > 0 else { return "0 %" }
        let p = Double(numerator) * 100.0 / Double(denominator)
        return String(format: "%.0f% %", p)
    }

    // MARK: - Table view

    private enum Row: Int, CaseIterable {
        case totalSticks
        case avgPerDay
        case daysWithSticks
        case avgPerStickDay
        case maxPerStickDay
        case longestNoStickStreak
        case dextroShare
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "BGStatsCell")
        cell.selectionStyle = .none

        let row = Row(rawValue: indexPath.row)!
        switch row {
        case .totalSticks:
            cell.textLabel?.text = "Totalt antal stick"
            cell.detailTextLabel?.text = "\(totalSticks) st"

        case .avgPerDay:
            cell.textLabel?.text = "Medel stick per dag"
            if totalDays > 0 {
                let avg = Double(totalSticks) / Double(totalDays)
                cell.detailTextLabel?.text = String(format: "%.1f st", avg)
            } else {
                cell.detailTextLabel?.text = "–"
            }
            
        case .daysWithSticks:
            cell.textLabel?.text = "Andel dagar med stick"
            cell.detailTextLabel?.text = "\(percentageString(daysWithSticks, totalDays))"
            
        case .avgPerStickDay:
            cell.textLabel?.text = "Medel stick per stick-dag"
            if daysWithSticks > 0 {
                let avg = Double(totalSticks) / Double(daysWithSticks)
                cell.detailTextLabel?.text = String(format: "%.1f st", avg)
            } else {
                cell.detailTextLabel?.text = "–"
            }

        case .maxPerStickDay:
            cell.textLabel?.text = "Högsta antal stick per stick-dag"
            cell.detailTextLabel?.text = "\(maxSticksPerDay) st"
        case .longestNoStickStreak:
            cell.textLabel?.text = "Längsta streak utan stick"
            let streak = longestStreakWithoutSticks()
            cell.detailTextLabel?.text = "\(streak) dagar"
        case .dextroShare:
            cell.textLabel?.text = "Andel stick ⇢ 🍬"
            if totalSticks > 0 {
                cell.detailTextLabel?.text = percentageString(totalDextroSticks, totalSticks)
            } else {
                cell.detailTextLabel?.text = "–"
            }
        }

        return cell
    }
}
