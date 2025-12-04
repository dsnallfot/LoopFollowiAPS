

import UIKit
import Charts

/// Loggvy för lågbehandlingar (Dextro), inspirerad av BGCheckView.
final class LowTreatmentsView: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Model

    struct LowTreatmentEntry {
        let date: Date
        let grams: Double
    }

    private var entries: [LowTreatmentEntry] = []

    // MARK: - UI

    private let tableView = UITableView(frame: .zero, style: .plain)

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private let gramsFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "sv_SE")
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 0
        return nf
    }()

    private var activityIndicator: UIActivityIndicatorView?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Dextro"
        view.backgroundColor = .systemBackground

        setupNavigationBar()
        setupTableView()
        setupConstraints()

        loadLowTreatments()
    }

    // MARK: - Nav bar

    private func setupNavigationBar() {
        let reload = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshTapped)
        )
        navigationItem.leftBarButtonItem = reload

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
            action: #selector(showLowTreatmentStats)
        )

        navigationItem.rightBarButtonItems = [done, statsBtn]
    }

    @objc private func doneTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func refreshTapped() {
        loadLowTreatments()
    }

    @objc private func showLowTreatmentStats() {
        let calendar = Calendar.current
        let now = Date()
        let daysBack = min(NightscoutCache.retentionDays, 90)

        // Startdatum = början av dagen (daysBack-1) dagar bakåt
        guard let startDay = calendar.date(
            byAdding: .day,
            value: -(daysBack - 1),
            to: calendar.startOfDay(for: now)
        ) else {
            return
        }

        // Begränsa till perioden vi ska visa i statistiken
        let filteredEntries = entries.filter { $0.date >= startDay && $0.date <= now }

        // Bygg en array av alla dagar i intervallet, med default 0 lågbehandlingar per dag
        var days: [Date] = []
        var counts: [Int] = []
        var gramsPerDay: [Double] = []
        days.reserveCapacity(daysBack)
        counts.reserveCapacity(daysBack)
        gramsPerDay.reserveCapacity(daysBack)

        for offset in 0..<daysBack {
            if let day = calendar.date(byAdding: .day, value: offset, to: startDay) {
                days.append(day)
                counts.append(0)
                gramsPerDay.append(0)
            }
        }

        // Snabb lookup för dag -> index i arrays
        var indexByDay: [Date: Int] = [:]
        for (idx, day) in days.enumerated() {
            indexByDay[calendar.startOfDay(for: day)] = idx
        }

        // Räkna lågbehandlingar och gram per dag
        for entry in filteredEntries {
            let dayStart = calendar.startOfDay(for: entry.date)
            if let idx = indexByDay[dayStart] {
                counts[idx] += 1
                gramsPerDay[idx] += entry.grams
            }
        }

        // Underliggande lista med enskilda behandlingar (för medel/max/streak-beräkningar)
        let treatmentDates = filteredEntries.map { $0.date }
        let treatmentGrams = filteredEntries.map { $0.grams }

        let statsVC = LowTreatmentsStatsViewController(
            days: days,
            counts: counts,
            gramsPerDay: gramsPerDay,
            treatmentDates: treatmentDates,
            treatmentGrams: treatmentGrams
        )
        let nav = UINavigationController(rootViewController: statsVC)
        present(nav, animated: true)
    }

    // MARK: - Setup table

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LowTreatmentCell")
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

    /// Hämtar alla Carb Correction-treatments med 🍬 i notes (lågbehandlingar) och mappar till LowTreatmentEntry.
    private func loadLowTreatments() {
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

            let lowTreatments: [LowTreatmentEntry] = treatments.compactMap { t -> LowTreatmentEntry? in
                // Endast Carb Correction med carbs > 0 och minst en 🍬 i notes
                guard t.eventType == "Carb Correction" else { return nil }
                guard let carbs = t.carbs, carbs > 0 else { return nil }
                guard let notes = t.notes, notes.contains("🍬") else { return nil }

                let date = t.created_at
                return LowTreatmentEntry(date: date, grams: carbs)
            }
            .sorted { $0.date > $1.date } // nyast överst

            await MainActor.run {
                self.entries = lowTreatments
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "LowTreatmentCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "LowTreatmentCell")
        cell.textLabel?.numberOfLines = 1

        let entry = entries[indexPath.row]
        let gramsString = gramsFormatter.string(from: NSNumber(value: entry.grams)) ?? String(format: "%.0f", entry.grams)

        // Leading SF Symbol + text "Låg behandling xx g"
        cell.textLabel?.text = " Dextro • \(gramsString) g"
        cell.textLabel?.font = .systemFont(ofSize: 17)

        cell.imageView?.image = UIImage(systemName: "pill")
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
            modalTitleString: "Utfall efter Dextro"
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

// MARK: - Statistikvy

final class LowTreatmentsStatsViewController: UITableViewController {

    // Full data set (upp till t.ex. 90 dagar)
    private let allDays: [Date]
    private let allCounts: [Int]
    private let allGramsPerDay: [Double]

    // Underliggande enskilda behandlingar
    private let allTreatmentDates: [Date]
    private let allTreatmentGrams: [Double]

    // Aktuell vy (styrd av period/antal-gram)
    private var selectedDays: [Date] = []
    private var selectedCounts: [Int] = []
    private var selectedGramsPerDay: [Double] = []

    private var selectedTreatmentDates: [Date] = []
    private var selectedTreatmentGrams: [Double] = []

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

    private enum ModeOption: CaseIterable {
        case count
        case grams

        var title: String {
            switch self {
            case .count: return "Behandlingar"
            case .grams: return "Mängd (g)"
            }
        }
    }

    private var selectedPeriod: PeriodOption = .d90
    private var selectedMode: ModeOption = .count

    private lazy var periodControl: UISegmentedControl = {
        let items = PeriodOption.allCases.map { $0.title }
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = PeriodOption.allCases.firstIndex(of: selectedPeriod) ?? (items.count - 1)
        sc.addTarget(self, action: #selector(periodChanged(_:)), for: .valueChanged)
        return sc
    }()

    private lazy var modeControl: UISegmentedControl = {
        let items = ModeOption.allCases.map { $0.title }
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = ModeOption.allCases.firstIndex(of: selectedMode) ?? 0
        sc.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
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

    init(
        days: [Date],
        counts: [Int],
        gramsPerDay: [Double],
        treatmentDates: [Date],
        treatmentGrams: [Double]
    ) {
        self.allDays = days
        self.allCounts = counts
        self.allGramsPerDay = gramsPerDay
        self.allTreatmentDates = treatmentDates
        self.allTreatmentGrams = treatmentGrams
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
            selectedGramsPerDay = []
            selectedTreatmentDates = []
            selectedTreatmentGrams = []
            chartView.data = nil
            tableView.reloadData()
            return
        }

        let n = min(period.days, total)
        let startIndex = max(0, total - n)
        selectedDays = Array(allDays[startIndex..<total])
        selectedCounts = Array(allCounts[startIndex..<total])
        selectedGramsPerDay = Array(allGramsPerDay[startIndex..<total])

        // Begränsa behandlingar till vald period (mellan första/sista dagen)
        if let firstDay = selectedDays.first, let lastDay = selectedDays.last {
            let cal = Calendar.current
            let periodStart = cal.startOfDay(for: firstDay)
            let periodEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: lastDay)) ?? lastDay

            var dates: [Date] = []
            var grams: [Double] = []
            for (d, g) in zip(allTreatmentDates, allTreatmentGrams) {
                if d >= periodStart && d < periodEnd {
                    dates.append(d)
                    grams.append(g)
                }
            }
            selectedTreatmentDates = dates
            selectedTreatmentGrams = grams
        } else {
            selectedTreatmentDates = []
            selectedTreatmentGrams = []
        }

        loadChartData()
        tableView.reloadData()
    }

    @objc private func periodChanged(_ sender: UISegmentedControl) {
        let index = sender.selectedSegmentIndex
        guard index >= 0 && index < PeriodOption.allCases.count else { return }
        let period = PeriodOption.allCases[index]
        applyPeriod(period)
    }

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        let index = sender.selectedSegmentIndex
        guard index >= 0 && index < ModeOption.allCases.count else { return }
        selectedMode = ModeOption.allCases[index]
        loadChartData()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Dextrostatistik"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissSelf)
        )

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LowStatsCell")

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
        container.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 340)

        container.addSubview(periodControl)
        container.addSubview(modeControl)
        container.addSubview(chartView)

        periodControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        chartView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            periodControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            periodControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            periodControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            modeControl.topAnchor.constraint(equalTo: periodControl.bottomAnchor, constant: 8),
            modeControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            modeControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            chartView.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 12),
            chartView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            chartView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            chartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
        ])

        tableView.tableHeaderView = container
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let header = tableView.tableHeaderView {
            let targetSize = CGSize(width: tableView.bounds.width, height: 340)
            if header.frame.size != targetSize {
                header.frame.size = targetSize
                tableView.tableHeaderView = header
            }
        }
    }

    private func loadChartData() {
        guard selectedDays.count == selectedCounts.count,
              selectedDays.count == selectedGramsPerDay.count,
              !selectedDays.isEmpty else {
            chartView.data = nil
            chartView.setNeedsDisplay()
            return
        }

        let yValues: [Double]
        switch selectedMode {
        case .count:
            yValues = selectedCounts.map { Double($0) }
        case .grams:
            yValues = selectedGramsPerDay
        }

        var entries: [BarChartDataEntry] = []
        entries.reserveCapacity(selectedDays.count)

        var maxValue: Double = 0
        for (idx, value) in yValues.enumerated() {
            entries.append(BarChartDataEntry(x: Double(idx), y: value))
            if value > maxValue { maxValue = value }
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
        df.dateFormat = "MM-dd"

        let labels = selectedDays.map { df.string(from: $0) }
        let xAxis = chartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.granularity = 1
        xAxis.granularityEnabled = true
        xAxis.valueFormatter = IndexAxisValueFormatter(values: labels)
        xAxis.setLabelCount(min(6, labels.count), force: false)

        // Y-axel – dynamiskt max utifrån högsta antal/summa gram per dag
        let yAxis = chartView.leftAxis
        yAxis.axisMinimum = 0
        let maxY = max(1, maxValue)
        yAxis.axisMaximum = maxY * 1.2
        yAxis.granularity = maxY <= 10 ? 1 : max(1, floor(maxY / 5))
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
    private var daysWithTreatments: Int { selectedCounts.filter { $0 > 0 }.count }
    private var totalTreatments: Int { selectedTreatmentDates.count }
    private var totalGrams: Double { selectedTreatmentGrams.reduce(0, +) }

    // Fördelning på antal dextro per behandling, baserat på gram kh
    // 1 dextro ≈ 0–3 g, 2 dextro ≈ 4–6 g, 3+ dextro > 6 g
    private var oneDextroCount: Int {
        selectedTreatmentGrams.filter { $0 >= 0 && $0 <= 3 }.count
    }

    private var twoDextroCount: Int {
        selectedTreatmentGrams.filter { $0 > 3 && $0 <= 6 }.count
    }

    private var threePlusDextroCount: Int {
        selectedTreatmentGrams.filter { $0 > 6 }.count
    }

    // Nattetid definieras som 22:00–06:00
    private var nightTreatmentCount: Int {
        guard !selectedTreatmentDates.isEmpty else { return 0 }
        let cal = Calendar.current
        var count = 0
        for date in selectedTreatmentDates {
            let hour = cal.component(.hour, from: date)
            if hour >= 22 || hour < 6 {
                count += 1
            }
        }
        return count
    }

    private func longestStreakWithoutTreatmentHours() -> Int {
        guard selectedTreatmentDates.count >= 2 else {
            return 0
        }
        let sorted = selectedTreatmentDates.sorted()
        var maxGap: TimeInterval = 0
        for i in 1..<sorted.count {
            let gap = sorted[i].timeIntervalSince(sorted[i - 1])
            if gap > maxGap { maxGap = gap }
        }
        let hours = Int(maxGap / 3600)
        return hours
    }

    private func percentageString(_ numerator: Int, _ denominator: Int) -> String {
        guard denominator > 0 else { return "0 %"
        }
        let p = Double(numerator) * 100.0 / Double(denominator)
        return String(format: "%.0f% %", p)
    }

    // MARK: - Table view

    private enum Row: Int, CaseIterable {
        case totalTreatments
        case avgTreatmentsPerDay
        case daysWithTreatmentsShare
        case oneDextroShare
        case twoDextroShare
        case threePlusDextroShare
        case nightTreatmentsCount
        case nightTreatmentsShare
        case longestNoTreatmentStreak
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "LowStatsCell")
        cell.selectionStyle = .none

        let row = Row(rawValue: indexPath.row)!
        switch row {
        case .totalTreatments:
            cell.textLabel?.text = "Dextrobehandlingar totalt"
            cell.detailTextLabel?.text = "\(totalTreatments) st"

        case .avgTreatmentsPerDay:
            cell.textLabel?.text = "Medel behandlingar per dag"
            if totalDays > 0 {
                let avg = Double(totalTreatments) / Double(totalDays)
                cell.detailTextLabel?.text = String(format: "%.1f st", avg)
            } else {
                cell.detailTextLabel?.text = "–"
            }

        case .daysWithTreatmentsShare:
            cell.textLabel?.text = "Andel dagar med dextro"
            cell.detailTextLabel?.text = percentageString(daysWithTreatments, totalDays)

        case .oneDextroShare:
            cell.textLabel?.text = "Behandling med 1 dextro"
            cell.detailTextLabel?.text = percentageString(oneDextroCount, totalTreatments)

        case .twoDextroShare:
            cell.textLabel?.text = "Behandling med 2 dextro"
            cell.detailTextLabel?.text = percentageString(twoDextroCount, totalTreatments)

        case .threePlusDextroShare:
            cell.textLabel?.text = "Behandling med 3+ dextro"
            cell.detailTextLabel?.text = percentageString(threePlusDextroCount, totalTreatments)

        case .nightTreatmentsCount:
            cell.textLabel?.text = "Dextrobehandlingar natt (22–06)"
            cell.detailTextLabel?.text = "\(nightTreatmentCount) st"

        case .nightTreatmentsShare:
            cell.textLabel?.text = "Andel natt av total (22–06)"
            cell.detailTextLabel?.text = percentageString(nightTreatmentCount, totalTreatments)

        case .longestNoTreatmentStreak:
            cell.textLabel?.text = "Längsta streak utan dextro"
            let hours = longestStreakWithoutTreatmentHours()
            cell.detailTextLabel?.text = "\(hours) h"
        }

        return cell
    }
}
