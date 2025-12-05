

import UIKit
import Charts

/// Loggvy för lågbehandlingar (Dextro), inspirerad av BGCheckView.
final class LowTreatmentsView: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Model

    struct LowTreatmentEntry {
        let date: Date
        let grams: Double
        let hasBGCheckNearby: Bool
    }

    private var entries: [LowTreatmentEntry] = []

    // BG Check-data för statistik (hela cachefönstret)
    private var bgCheckDatesForStats: [Date] = []
    private var bgCheckMmolForStats: [Double] = []

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
        let treatmentHasBGCheck = filteredEntries.map { $0.hasBGCheckNearby }

        let statsVC = LowTreatmentsStatsViewController(
            days: days,
            counts: counts,
            gramsPerDay: gramsPerDay,
            treatmentDates: treatmentDates,
            treatmentGrams: treatmentGrams,
            treatmentHasBGCheck: treatmentHasBGCheck,
            bgCheckDates: bgCheckDatesForStats,
            bgCheckMmol: bgCheckMmolForStats
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
            
            // Plocka ut alla BG Check-datum (för korsning mot dextro) samt mmol-värde
            var bgCheckDates: [Date] = []
            var bgCheckMmol: [Double] = []
            for t in treatments {
                guard t.eventType == "BG Check" else { continue }
                let date = t.created_at
                guard let raw = t.glucose else { continue }

                let mmol: Double
                if let units = t.units, units.lowercased().contains("mmol") {
                    mmol = raw
                } else {
                    // mg/dL -> mmol/L
                    mmol = raw / 18.0182
                }

                bgCheckDates.append(date)
                bgCheckMmol.append(mmol)
            }

            let windowSeconds: TimeInterval = 15 * 60 // ±15 min

            let lowTreatments: [LowTreatmentEntry] = treatments.compactMap { t -> LowTreatmentEntry? in
                // Endast Carb Correction med carbs > 0 och minst en 🍬 i notes
                guard t.eventType == "Carb Correction" else { return nil }
                guard let carbs = t.carbs, carbs > 0 else { return nil }
                guard let notes = t.notes, notes.contains("🍬") else { return nil }

                let date = t.created_at

                // Finns det ett fingerstick (BG Check) inom ±15 minuter?
                let hasBGCheckNearby = bgCheckDates.contains { bgDate in
                    abs(bgDate.timeIntervalSince(date)) <= windowSeconds
                }

                return LowTreatmentEntry(
                    date: date,
                    grams: carbs,
                    hasBGCheckNearby: hasBGCheckNearby
                )
            }
            .sorted { $0.date > $1.date } // nyast överst

            await MainActor.run {
                self.entries = lowTreatments
                self.bgCheckDatesForStats = bgCheckDates
                self.bgCheckMmolForStats = bgCheckMmol
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

        // Leading SF Symbol + text "Dextro • xx g" + ev. markering om fingerstick inom ±15 min
        var text = " Dextro • \(gramsString) g"
        if entry.hasBGCheckNearby {
            text += " 🩸"
        }
        cell.textLabel?.text = text
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
            modalTitleString: "Utv. efter Dextro"
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
    private let allTreatmentHasBGCheck: [Bool]

    // Underliggande BG Check-data (globala för cachefönstret)
    private let allBGCheckDates: [Date]
    private let allBGCheckMmol: [Double]

    // Aktuell vy (styrd av period/antal-gram)
    private var selectedDays: [Date] = []
    private var selectedCounts: [Int] = []
    private var selectedGramsPerDay: [Double] = []

    private var selectedTreatmentDates: [Date] = []
    private var selectedTreatmentGrams: [Double] = []
    private var selectedTreatmentHasBGCheck: [Bool] = []

    private var selectedBGCheckDates: [Date] = []
    private var selectedBGCheckMmol: [Double] = []

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
        case lowAndBg

        var title: String {
            switch self {
            case .count: return "Behandlingar"
            case .grams: return "Mängd (g)"
            case .lowAndBg: return "Dextro & Stick"
            }
        }
    }

    private var selectedPeriod: PeriodOption = .d14
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
    
    private let lineChartView: LineChartView = {
        let v = LineChartView()
        v.chartDescription.enabled = false
        v.legend.enabled = true
        v.minOffset = 8
        v.pinchZoomEnabled = false
        v.doubleTapToZoomEnabled = true
        v.scaleXEnabled = true
        v.scaleYEnabled = false
        v.dragEnabled = true
        v.highlightPerTapEnabled = false
        v.highlightPerDragEnabled = false
        v.drawMarkers = false
        v.rightAxis.enabled = true
        return v
    }()

    init(
        days: [Date],
        counts: [Int],
        gramsPerDay: [Double],
        treatmentDates: [Date],
        treatmentGrams: [Double],
        treatmentHasBGCheck: [Bool],
        bgCheckDates: [Date],
        bgCheckMmol: [Double]
    ) {
        self.allDays = days
        self.allCounts = counts
        self.allGramsPerDay = gramsPerDay
        self.allTreatmentDates = treatmentDates
        self.allTreatmentGrams = treatmentGrams
        self.allTreatmentHasBGCheck = treatmentHasBGCheck
        self.allBGCheckDates = bgCheckDates
        self.allBGCheckMmol = bgCheckMmol
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

        // Begränsa behandlingar och BG Check till vald period
        if let firstDay = selectedDays.first, let lastDay = selectedDays.last {
            let cal = Calendar.current
            let periodStart = cal.startOfDay(for: firstDay)
            let periodEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: lastDay)) ?? lastDay

            var dates: [Date] = []
            var grams: [Double] = []
            var hasBG: [Bool] = []

            for idx in allTreatmentDates.indices {
                let d = allTreatmentDates[idx]
                if d >= periodStart && d < periodEnd {
                    dates.append(d)
                    grams.append(allTreatmentGrams[idx])
                    hasBG.append(allTreatmentHasBGCheck[idx])
                }
            }
            selectedTreatmentDates = dates
            selectedTreatmentGrams = grams
            selectedTreatmentHasBGCheck = hasBG

            var bgDates: [Date] = []
            var bgMmol: [Double] = []
            for idx in allBGCheckDates.indices {
                let d = allBGCheckDates[idx]
                if d >= periodStart && d < periodEnd {
                    bgDates.append(d)
                    bgMmol.append(allBGCheckMmol[idx])
                }
            }
            selectedBGCheckDates = bgDates
            selectedBGCheckMmol = bgMmol
        } else {
            selectedTreatmentDates = []
            selectedTreatmentGrams = []
            selectedTreatmentHasBGCheck = []
            selectedBGCheckDates = []
            selectedBGCheckMmol = []
        }

        if selectedMode == .lowAndBg {
            loadLowAndBgChartData()
        } else {
            loadChartData()
        }
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

        chartView.isHidden = (selectedMode == .lowAndBg)
        lineChartView.isHidden = (selectedMode != .lowAndBg)

        if selectedMode == .lowAndBg {
            loadLowAndBgChartData()
        } else {
            loadChartData()
        }
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
        container.addSubview(lineChartView)

        periodControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        chartView.translatesAutoresizingMaskIntoConstraints = false
        lineChartView.translatesAutoresizingMaskIntoConstraints = false

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
            chartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),

            lineChartView.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 12),
            lineChartView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            lineChartView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            lineChartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
        ])

        // Utgångsläge: bar-chart visas, line-chart göms
        chartView.isHidden = selectedMode == .lowAndBg
        lineChartView.isHidden = selectedMode != .lowAndBg

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
        case .lowAndBg:
            // Ska normalt inte visas i bar-chart-läget,
            // men vi faller tillbaka till antal behandlingar för säkerhets skull.
            yValues = selectedCounts.map { Double($0) }
        }

        var entries: [BarChartDataEntry] = []
        entries.reserveCapacity(selectedDays.count)

        var maxValue: Double = 0
        for (idx, value) in yValues.enumerated() {
            entries.append(BarChartDataEntry(x: Double(idx), y: value))
            if value > maxValue { maxValue = value }
        }

        let dataSet = BarChartDataSet(entries: entries, label: "")
        dataSet.setColor(.systemOrange)
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
    
    /// Formatterar x-värden (timmar från periodens start) till datumsträngar på x-axeln.
    private final class DateAxisFormatter: AxisValueFormatter {
        private let referenceDate: Date
        private let dateFormatter: DateFormatter

        init(referenceDate: Date) {
            self.referenceDate = referenceDate
            let df = DateFormatter()
            df.locale = Locale(identifier: "sv_SE")
            df.dateFormat = "MM-dd"
            self.dateFormatter = df
        }

        func stringForValue(_ value: Double, axis: AxisBase?) -> String {
            // value = antal timmar från periodens start
            let seconds = value * 3600.0
            let date = referenceDate.addingTimeInterval(seconds)
            return dateFormatter.string(from: date)
        }
    }

    private func loadLowAndBgChartData() {
        guard !selectedDays.isEmpty else {
            lineChartView.data = nil
            lineChartView.setNeedsDisplay()
            return
        }

        let cal = Calendar.current
        // Referens = periodens första dag kl 00:00
        let referenceStart = cal.startOfDay(for: selectedDays.first!)

        // Dextro-punkter: vänster y-axel (g)
        var dextroEntries: [ChartDataEntry] = []
        var maxGrams: Double = 0
        for (date, grams) in zip(selectedTreatmentDates, selectedTreatmentGrams) {
            // x = antal timmar sedan periodens start (ger granularitet ner på minuter)
            let hoursSinceStart = date.timeIntervalSince(referenceStart) / 3600.0
            dextroEntries.append(ChartDataEntry(x: hoursSinceStart, y: grams))
            if grams > maxGrams { maxGrams = grams }
        }

        // Stick-punkter: höger y-axel (mmol/L)
        var bgEntries: [ChartDataEntry] = []
        var maxMmol: Double = 0
        for (date, mmol) in zip(selectedBGCheckDates, selectedBGCheckMmol) {
            let hoursSinceStart = date.timeIntervalSince(referenceStart) / 3600.0
            bgEntries.append(ChartDataEntry(x: hoursSinceStart, y: mmol))
            if mmol > maxMmol { maxMmol = mmol }
        }

        let dextroSet = LineChartDataSet(entries: dextroEntries, label: "Dextro (g)  ")
        dextroSet.axisDependency = .left
        dextroSet.setColor(.label)
        dextroSet.setCircleColor(.label)
        dextroSet.circleRadius = 3
        dextroSet.drawCirclesEnabled = true
        dextroSet.drawValuesEnabled = false
        dextroSet.lineWidth = 0

        let bgSet = LineChartDataSet(entries: bgEntries, label: "Fingerstick (mmol/L)")
        bgSet.axisDependency = .right
        bgSet.setColor(.systemRed)
        bgSet.setCircleColor(.systemRed)
        bgSet.circleRadius = 3
        bgSet.drawCirclesEnabled = true
        bgSet.drawValuesEnabled = false
        bgSet.lineWidth = 0

        let data = LineChartData(dataSets: [dextroSet, bgSet])
        lineChartView.data = data

        // X-axel: värden i timmar från periodens start, formatteras till datum
        let xAxis = lineChartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.granularity = 24.0   // ca en etikett per dygn
        xAxis.granularityEnabled = true
        xAxis.valueFormatter = DateAxisFormatter(referenceDate: referenceStart)
        xAxis.setLabelCount(min(6, selectedDays.count), force: false)

        let leftAxis = lineChartView.leftAxis
        leftAxis.axisMinimum = 0
        let maxYLeft = max(1, maxGrams)
        leftAxis.axisMaximum = maxYLeft * 1.2

        let rightAxis = lineChartView.rightAxis
        rightAxis.enabled = true
        rightAxis.axisMinimum = 0
        let maxYRight = max(1, maxMmol)
        rightAxis.axisMaximum = maxYRight * 1.2

        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.5)
        xAxis.gridColor = gridLineColor
        xAxis.gridLineWidth = 0.5
        xAxis.gridLineDashLengths = [2, 2]

        leftAxis.gridColor = .clear//gridLineColor
        leftAxis.gridLineWidth = 0.5
        leftAxis.gridLineDashLengths = [2, 2]
        
        rightAxis.gridColor = gridLineColor//.clear
        rightAxis.gridLineWidth = 0.5
        rightAxis.gridLineDashLengths = [2, 2]

        lineChartView.setNeedsDisplay()
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

private var dextroWithFingerstickCount: Int {
    selectedTreatmentHasBGCheck.filter { $0 }.count
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
    case dextroWithFingerstickShare
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

        case .dextroWithFingerstickShare:
            cell.textLabel?.text = "Andel dextro med fingerstick"
            cell.detailTextLabel?.text = percentageString(dextroWithFingerstickCount, totalTreatments)
        }

        return cell
    }
}
