

import UIKit
import Charts

/// Loggvy för lågbehandlingar (Dextro), inspirerad av BGCheckView.
final class LowTreatmentsView: ThemedViewController, UITableViewDataSource, UITableViewDelegate {

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
        title = "Dextrologg"
        //view.backgroundColor = .systemBackground
        updateBackgroundForCurrentMode()

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
            image: UIImage(systemName: "chart.bar.xaxis.ascending"),
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

        // Ensure the modal container doesn't paint an opaque gray background over the themed table.
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

    // MARK: - Setup table

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LowTreatmentCell")
        tableView.rowHeight = 50
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
        
        tableView.backgroundColor = .clear
        tableView.isOpaque = false
        tableView.backgroundView = nil
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

        // Transparent cell so the themed gradient shows through
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.backgroundView = nil
        if #available(iOS 14.0, *) {
            cell.backgroundConfiguration = nil
        }
        cell.textLabel?.backgroundColor = .clear
        cell.detailTextLabel?.backgroundColor = .clear

        let entry = entries[indexPath.row]
        let gramsString = gramsFormatter.string(from: NSNumber(value: entry.grams)) ?? String(format: "%.0f", entry.grams)

        // Leading SF Symbol + text "Dextro • xx g" + ev. markering om fingerstick inom ±15 min
        var text = " Dextro • \(gramsString) g"
        if entry.hasBGCheckNearby {
            text += " 🩸"
        }
        cell.textLabel?.text = text
        cell.textLabel?.font = .systemFont(ofSize: 17)

        cell.imageView?.image = UIImage(systemName: "pill.fill")
        cell.imageView?.tintColor = .label

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
        // Match Treatments-style selection highlight (subtle overlay over the gradient)
        cell.selectionStyle = .default
        let selected = UIView()
        selected.backgroundColor = UIColor.label.withAlphaComponent(0.2)
        selected.layer.cornerRadius = 10
        selected.layer.masksToBounds = true
        cell.selectedBackgroundView = selected
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let entry = entries[indexPath.row]
        let startDate = entry.date


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
        self.present(nav, animated: true) { [weak self] in
            self?.tableView.deselectRow(at: indexPath, animated: true)
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
}

// MARK: - Statistikvy

final class LowTreatmentsStatsViewController: ThemedTableViewController {

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
        case time

        var title: String {
            switch self {
            case .count: return "Behandling"
            case .grams: return "Mängd"
            case .lowAndBg: return "Dex & Stick"
            case .time: return "Tid"
            }
        }
    }

    private enum TimeFilterOption: CaseIterable {
        case allTime
        case dayTime
        case nightTime

        var title: String {
            switch self {
            case .allTime:  return "Alla"
            case .dayTime:  return "Dag (06–22)"
            case .nightTime: return "Natt (22–06)"
            }
        }
    }

    private var selectedPeriod: PeriodOption = .d14
    private var selectedMode: ModeOption = .count
    private var selectedTimeFilter: TimeFilterOption = .allTime

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

    private lazy var timeFilterControl: UISegmentedControl = {
        let items = TimeFilterOption.allCases.map { $0.title }
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = TimeFilterOption.allCases.firstIndex(of: selectedTimeFilter) ?? 0
        sc.addTarget(self, action: #selector(timeFilterChanged(_:)), for: .valueChanged)
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
    
    private let scatterChartView: ScatterChartView = {
        let v = ScatterChartView()
        v.chartDescription.enabled = false
        v.legend.enabled = true
        v.minOffset = 8
        v.pinchZoomEnabled = false
        v.doubleTapToZoomEnabled = true
        v.scaleXEnabled = true
        v.scaleYEnabled = false
        v.dragEnabled = true
        v.highlightPerTapEnabled = true
        v.highlightPerDragEnabled = false
        v.drawMarkers = true
        v.rightAxis.enabled = true
        return v
    }()
    
    // Scatterplot: Dextro-behandlingar per datum (x) och tid på dygnet (y)
    private let timeChartView: ScatterChartView = {
        let v = ScatterChartView()
        v.chartDescription.enabled = false
        v.legend.enabled = true
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
        // Defaulta till 14 dagar om möjligt,
        // annars falla tillbaka till kortare perioder vid behov.
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

        switch selectedMode {
        case .lowAndBg:
            loadLowAndBgChartData()
        case .time:
            loadTreatmentTimeChartData()
        case .count, .grams:
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

        let showBars = (selectedMode == .count || selectedMode == .grams)
        chartView.isHidden = !showBars
        scatterChartView.isHidden = (selectedMode != .lowAndBg)
        timeChartView.isHidden = (selectedMode != .time)

        switch selectedMode {
        case .lowAndBg:
            loadLowAndBgChartData()
        case .time:
            loadTreatmentTimeChartData()
        case .count, .grams:
            loadChartData()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateBackgroundForCurrentMode()
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.isOpaque = false
        tableView.layer.backgroundColor = UIColor.clear.cgColor
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
        // Time filter default
        if let filterIdx = TimeFilterOption.allCases.firstIndex(of: selectedTimeFilter) {
            timeFilterControl.selectedSegmentIndex = filterIdx
        }

        setupChartHeader()
        applyPeriod(initialPeriod)
    }

    // MARK: - Chart header

    private func setupChartHeader() {
        let container = UIView()
        container.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 340)
        container.backgroundColor = .clear

        container.addSubview(periodControl)
        container.addSubview(modeControl)
        container.addSubview(timeFilterControl)
        container.addSubview(chartView)
        container.addSubview(scatterChartView)
        container.addSubview(timeChartView)

        periodControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        timeFilterControl.translatesAutoresizingMaskIntoConstraints = false
        chartView.translatesAutoresizingMaskIntoConstraints = false
        scatterChartView.translatesAutoresizingMaskIntoConstraints = false
        timeChartView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            periodControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            periodControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            periodControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            modeControl.topAnchor.constraint(equalTo: periodControl.bottomAnchor, constant: 8),
            modeControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            modeControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            timeFilterControl.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 8),
            timeFilterControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            timeFilterControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            chartView.topAnchor.constraint(equalTo: timeFilterControl.bottomAnchor, constant: 12),
            chartView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            chartView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            chartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),

            scatterChartView.topAnchor.constraint(equalTo: timeFilterControl.bottomAnchor, constant: 12),
            scatterChartView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            scatterChartView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            scatterChartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -0),
            
            timeChartView.topAnchor.constraint(equalTo: timeFilterControl.bottomAnchor, constant: 12),
            timeChartView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            timeChartView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            timeChartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -0),
        ])

        // Utgångsläge: bar-chart visas, line-chart göms
        chartView.isHidden = !(selectedMode == .count || selectedMode == .grams)
        scatterChartView.isHidden = (selectedMode != .lowAndBg)
        timeChartView.isHidden = (selectedMode != .time)

        tableView.tableHeaderView = container
    }
    @objc private func timeFilterChanged(_ sender: UISegmentedControl) {
        let index = sender.selectedSegmentIndex
        guard index >= 0 && index < TimeFilterOption.allCases.count else { return }
        selectedTimeFilter = TimeFilterOption.allCases[index]

        switch selectedMode {
        case .lowAndBg:
            loadLowAndBgChartData()
        case .time:
            loadTreatmentTimeChartData()
        case .count, .grams:
            loadChartData()
        }
    }

    private func passesTimeFilter(_ date: Date) -> Bool {
        switch selectedTimeFilter {
        case .allTime:
            return true
        case .dayTime:
            let hour = Calendar.current.component(.hour, from: date)
            return hour >= 6 && hour < 22   // 06:00–21:59
        case .nightTime:
            let hour = Calendar.current.component(.hour, from: date)
            return hour >= 22 || hour < 6   // 22:00–05:59
        }
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
        // Vi utgår nu bara från vald period + underliggande behandlingar,
        // och räknar om per dag utifrån selectedTimeFilter.
        guard !selectedDays.isEmpty else {
            chartView.data = nil
            chartView.setNeedsDisplay()
            return
        }

        let cal = Calendar.current

        // startOfDay -> dagindex i selectedDays
        var indexByDayStart: [Date: Int] = [:]
        for (idx, day) in selectedDays.enumerated() {
            let dayStart = cal.startOfDay(for: day)
            indexByDayStart[dayStart] = idx
        }

        // Grundarrayen för staplarna (en stapel per dag)
        var yValues = Array(repeating: 0.0, count: selectedDays.count)

        switch selectedMode {
        case .count, .lowAndBg:
            // Räkna antal behandlingar per dag (filtrerat på dag/natt/allTime)
            for date in selectedTreatmentDates {
                guard passesTimeFilter(date) else { continue }
                let dayStart = cal.startOfDay(for: date)
                if let idx = indexByDayStart[dayStart] {
                    yValues[idx] += 1.0
                }
            }

        case .grams:
            // Summera gram per dag (filtrerat på dag/natt/allTime)
            for (date, grams) in zip(selectedTreatmentDates, selectedTreatmentGrams) {
                guard passesTimeFilter(date) else { continue }
                let dayStart = cal.startOfDay(for: date)
                if let idx = indexByDayStart[dayStart] {
                    yValues[idx] += grams
                }
            }
        case .time:
            // Används inte i stapeldiagram
            break
        }

        // Om allt är noll → töm grafen
        if yValues.allSatisfy({ $0 == 0 }) {
            chartView.data = nil
            chartView.setNeedsDisplay()
            return
        }

        // Bygg BarChartDataEntries
        var entries: [BarChartDataEntry] = []
        entries.reserveCapacity(selectedDays.count)

        var maxValue: Double = 0
        for (idx, value) in yValues.enumerated() {
            entries.append(BarChartDataEntry(x: Double(idx), y: value))
            if value > maxValue { maxValue = value }
        }

        let dataSet = BarChartDataSet(entries: entries, label: "")
        dataSet.setColor(.white)
        dataSet.drawValuesEnabled = false
        dataSet.barBorderColor = .black
        dataSet.barBorderWidth = 0.5

        let data = BarChartData(dataSet: dataSet)
        chartView.data = data
        chartView.autoScaleMinMaxEnabled = false
        chartView.notifyDataSetChanged()

        // X-axis labels = datum (kompakt format) för varje dag i selectedDays
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

        // Y-axel – dynamiskt max
        let yAxis = chartView.leftAxis
        yAxis.axisMinimum = 0
        let maxY = max(1, maxValue)
        yAxis.axisMaximum = maxY * 1.2
        yAxis.granularity = maxY <= 10 ? 1 : max(1, floor(maxY / 5))
        yAxis.granularityEnabled = true

        // Enhet på vänster y-axel beroende på läge
        switch selectedMode {
        case .count, .lowAndBg:
            yAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
                String(format: "%.0f ggr", value)
            }
        case .grams:
            yAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
                String(format: "%.0f g", value)
            }
        case .time:
            // Ingen stapel → ingen formatter behövs
            break
        }

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
            df.dateFormat = "dd/MM"
            self.dateFormatter = df
        }

        func stringForValue(_ value: Double, axis: AxisBase?) -> String {
            // value = antal timmar från periodens start
            let seconds = value * 3600.0
            let date = referenceDate.addingTimeInterval(seconds)
            return dateFormatter.string(from: date)
        }
    }
    
    /// Marker som visar tre rader text för Dextro respektive fingerstick i scatter-grafen.
    private final class DextroBgMarker: MarkerView {

        private let label = UILabel()
        private let contentInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        private let referenceDate: Date
        private let dateFormatter: DateFormatter

        init(referenceDate: Date) {
            self.referenceDate = referenceDate

            let df = DateFormatter()
            df.locale = Locale(identifier: "sv_SE")
            df.dateFormat = "yyyy-MM-dd HH:mm"
            self.dateFormatter = df

            super.init(frame: .zero)

            label.numberOfLines = 0
            label.font = .systemFont(ofSize: 12)
            label.textColor = .label

            addSubview(label)

            backgroundColor = UIColor.systemGray4.withAlphaComponent(0.8)
            layer.cornerRadius = 6
            layer.borderWidth = 1
            layer.borderColor = UIColor.label.cgColor
            clipsToBounds = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func refreshContent(entry: ChartDataEntry, highlight: Highlight) {
            guard
                let scatterData = chartView?.data as? ScatterChartData,
                highlight.dataSetIndex >= 0,
                highlight.dataSetIndex < scatterData.dataSetCount
            else {
                return
            }

            let dataSet = scatterData.dataSets[highlight.dataSetIndex]

            // BG (fingerstick) ligger på höger-axeln, dextro på vänster.
            let isFingerstick = dataSet.axisDependency == .right

            // x är antal timmar sedan periodens start
            let date = referenceDate.addingTimeInterval(entry.x * 3600.0)
            let dateString = dateFormatter.string(from: date)

            let line1: String
            let line2: String

            if isFingerstick {
                line1 = "Fingerstick"
                line2 = String(format: "%.1f mmol/L", entry.y)
            } else {
                line1 = "Dextro"
                line2 = String(format: "%.0f g kh", entry.y)
            }

            label.text = "\(line1)\n\(line2)\n\(dateString)"
            label.sizeToFit()

            let size = CGSize(
                width: label.bounds.width + contentInsets.left + contentInsets.right,
                height: label.bounds.height + contentInsets.top + contentInsets.bottom
            )
            bounds = CGRect(origin: .zero, size: size)

            label.frame = CGRect(
                x: contentInsets.left,
                y: contentInsets.top,
                width: size.width - contentInsets.left - contentInsets.right,
                height: size.height - contentInsets.top - contentInsets.bottom
            )

            layoutIfNeeded()

            // Centera markern över punkten och placera den strax ovanför
            let sizeMarker = bounds.size
            self.offset = CGPoint(
                x: -sizeMarker.width / 2.0,
                y: -sizeMarker.height - 8.0
            )

            super.refreshContent(entry: entry, highlight: highlight)
        }
    }

    private func loadLowAndBgChartData() {
        guard !selectedDays.isEmpty else {
            scatterChartView.data = nil
            scatterChartView.setNeedsDisplay()
            return
        }

        let cal = Calendar.current
        // Referens = periodens första dag kl 00:00
        let referenceStart = cal.startOfDay(for: selectedDays.first!)
        let now = Date()
        let hoursSinceStartNow = max(0.0, now.timeIntervalSince(referenceStart) / 3600.0)

        // Sortera Dextro-behandlingar kronologiskt (äldst -> nyast)
        let sortedDextro = zip(selectedTreatmentDates, selectedTreatmentGrams)
            .sorted { $0.0 < $1.0 }

        // Sortera BG Checks kronologiskt (äldst -> nyast)
        let sortedBG = zip(selectedBGCheckDates, selectedBGCheckMmol)
            .sorted { $0.0 < $1.0 }

        // Dextro-punkter: vänster y-axel (g)
        var dextroEntries: [ChartDataEntry] = []
        var maxGrams: Double = 0
        for (date, grams) in sortedDextro {
            guard passesTimeFilter(date) else { continue }
            // x = antal timmar sedan periodens start (ger granularitet ner på minuter)
            let hoursSinceStart = date.timeIntervalSince(referenceStart) / 3600.0
            dextroEntries.append(ChartDataEntry(x: hoursSinceStart, y: grams))
            if grams > maxGrams { maxGrams = grams }
        }

        // Stick-punkter: höger y-axel (mmol/L)
        var bgEntries: [ChartDataEntry] = []
        var maxMmol: Double = 0
        for (date, mmol) in sortedBG {
            guard passesTimeFilter(date) else { continue }
            let hoursSinceStart = date.timeIntervalSince(referenceStart) / 3600.0
            bgEntries.append(ChartDataEntry(x: hoursSinceStart, y: mmol))
            if mmol > maxMmol { maxMmol = mmol }
        }


        let dextroSet = ScatterChartDataSet(entries: dextroEntries, label: "Dextro (g)")
        dextroSet.axisDependency = .left
        dextroSet.setColor(.black)
        dextroSet.setScatterShape(.circle)
        dextroSet.scatterShapeSize = 7
        dextroSet.drawValuesEnabled = false
        dextroSet.scatterShapeHoleRadius = 3
        dextroSet.scatterShapeHoleColor = .white
        dextroSet.highlightEnabled = true
        dextroSet.setDrawHighlightIndicators(false)

        let bgSet = ScatterChartDataSet(entries: bgEntries, label: "Fingerstick (mmol/L)")
        bgSet.axisDependency = .right
        bgSet.setColor(.black)
        bgSet.setScatterShape(.circle)
        bgSet.scatterShapeSize = 7
        bgSet.drawValuesEnabled = false
        bgSet.scatterShapeHoleRadius = 3
        bgSet.scatterShapeHoleColor = .systemRed
        bgSet.highlightEnabled = true
        bgSet.setDrawHighlightIndicators(false)

        let data = ScatterChartData(dataSets: [dextroSet, bgSet])
        scatterChartView.data = data

        // Marker med tre rader text för dextro/fingerstick
        let marker = DextroBgMarker(referenceDate: referenceStart)
        marker.chartView = scatterChartView
        scatterChartView.marker = marker

        // --- Custom legend (centrerad under grafen) --- //
        let legend = scatterChartView.legend
        legend.enabled = true
        legend.drawInside = false
        legend.orientation = .horizontal
        legend.verticalAlignment = .bottom
        legend.horizontalAlignment = .center
        legend.xEntrySpace = 12
        legend.yEntrySpace = 6
        legend.formToTextSpace = 6
        legend.yOffset = 8
        // Lite extra luft mellan plot-ytan och legend (yOffset påverkar inte alltid layouten)
        scatterChartView.extraBottomOffset = 4

        let dextroLegendEntry = LegendEntry(label: "Dextro (g)")
        dextroLegendEntry.form = .circle
        dextroLegendEntry.formSize = 8
        dextroLegendEntry.formColor = .white

        let bgLegendEntry = LegendEntry(label: "Fingerstick (mmol/L)")
        bgLegendEntry.form = .circle
        bgLegendEntry.formSize = 8
        bgLegendEntry.formColor = .systemRed

        legend.setCustom(entries: [dextroLegendEntry, bgLegendEntry])

        // X-axel: värden i timmar från periodens start, formatteras till datum
        let xAxis = scatterChartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.granularity = 24.0   // ca en etikett per dygn
        xAxis.granularityEnabled = true
        xAxis.valueFormatter = DateAxisFormatter(referenceDate: referenceStart)
        xAxis.setLabelCount(min(6, selectedDays.count), force: false)
        xAxis.axisMinimum = 0.0
        xAxis.axisMaximum = hoursSinceStartNow

        let leftAxis = scatterChartView.leftAxis
        leftAxis.axisMinimum = 0
        let maxYLeft = max(1, maxGrams)
        leftAxis.axisMaximum = maxYLeft * 1.2
        // Enhet på vänster y-axel
        leftAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
            String(format: "%.0f g", value)
        }

        let rightAxis = scatterChartView.rightAxis
        rightAxis.enabled = true
        rightAxis.axisMinimum = 0
        let maxYRight = max(1, maxMmol)
        rightAxis.axisMaximum = maxYRight * 1.2
        // Enhet på höger y-axel
        rightAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
            String(format: "%.0f mmol", value)
        }
        rightAxis.labelTextColor = .systemRed

        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.5)
        xAxis.gridColor = gridLineColor
        xAxis.gridLineWidth = 0.5
        xAxis.gridLineDashLengths = [2, 2]

        leftAxis.gridColor = .clear
        leftAxis.gridLineWidth = 0.5
        leftAxis.gridLineDashLengths = [2, 2]

        rightAxis.gridColor = gridLineColor
        rightAxis.gridLineWidth = 0.5
        rightAxis.gridLineDashLengths = [2, 2]

        scatterChartView.notifyDataSetChanged()
        scatterChartView.setNeedsDisplay()
    }
    
    private func loadTreatmentTimeChartData() {
        guard !selectedDays.isEmpty else {
            timeChartView.data = nil
            timeChartView.setNeedsDisplay()
            return
        }

        let cal = Calendar.current

        // Index per dag för x-position
        var indexByDay: [Date: Int] = [:]
        for (idx, d) in selectedDays.enumerated() {
            indexByDay[cal.startOfDay(for: d)] = idx
        }

        func hourOfDay(for date: Date) -> Double {
            let comps = cal.dateComponents([.hour, .minute, .second], from: date)
            let h = Double(comps.hour ?? 0)
            let m = Double(comps.minute ?? 0)
            let s = Double(comps.second ?? 0)
            return h + (m / 60.0) + (s / 3600.0)
        }

        // Vita punkter = alla dextro, lila = dextro med fingerstick (hasBGCheckNearby == true)
        var allPoints: [ChartDataEntry] = []
        var purplePoints: [ChartDataEntry] = []
        allPoints.reserveCapacity(selectedTreatmentDates.count)
        purplePoints.reserveCapacity(selectedTreatmentDates.count)

        for i in selectedTreatmentDates.indices {
            let date = selectedTreatmentDates[i]
            guard passesTimeFilter(date) else { continue }

            let dayStart = cal.startOfDay(for: date)
            guard let dayIndex = indexByDay[dayStart] else { continue }

            let entry = ChartDataEntry(x: Double(dayIndex), y: hourOfDay(for: date))
            allPoints.append(entry)

            if i < selectedTreatmentHasBGCheck.count, selectedTreatmentHasBGCheck[i] {
                purplePoints.append(entry)
            }
        }
        
        // Viktigt: sortera entries för att undvika Charts-bug där punkter kan försvinna vid zoom/scroll
        allPoints.sort {
            if $0.x == $1.x { return $0.y < $1.y }
            return $0.x < $1.x
        }
        purplePoints.sort {
            if $0.x == $1.x { return $0.y < $1.y }
            return $0.x < $1.x
        }

        let whiteColor = UIColor.white.withAlphaComponent(0.90)
        let purpleColor = UIColor.systemPurple.withAlphaComponent(0.95)

        let dsAll = ScatterChartDataSet(entries: allPoints, label: "Dextrobehandling")
        dsAll.setColor(whiteColor)
        dsAll.setScatterShape(.circle)
        dsAll.scatterShapeSize = 7
        dsAll.drawValuesEnabled = false

        let dsPurple = ScatterChartDataSet(entries: purplePoints, label: "Dextro med fingerstick")
        dsPurple.setColor(purpleColor)
        dsPurple.setScatterShape(.circle)
        dsPurple.scatterShapeSize = 7
        dsPurple.drawValuesEnabled = false

        // Lila sist så de syns ovanpå vitt
        timeChartView.data = ScatterChartData(dataSets: [dsAll, dsPurple])
        timeChartView.autoScaleMinMaxEnabled = false
        timeChartView.notifyDataSetChanged()

        // Custom legend: vit cirkel + lila cirkel
        let legend = timeChartView.legend
        legend.enabled = true
        legend.drawInside = false
        legend.orientation = .horizontal
        legend.verticalAlignment = .bottom
        legend.horizontalAlignment = .center
        legend.xEntrySpace = 12
        legend.formToTextSpace = 6
        legend.yOffset = 6

        let e1 = LegendEntry(label: "Dextrobehandling")
        e1.form = .circle
        e1.formSize = 8
        e1.formColor = whiteColor

        let e2 = LegendEntry(label: "Dextro med fingerstick")
        e2.form = .circle
        e2.formSize = 8
        e2.formColor = purpleColor

        legend.setCustom(entries: [e1, e2])
        timeChartView.extraBottomOffset = 8

        // X-axis labels = datum (dd/MM)
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "dd/MM"
        let labels = selectedDays.map { df.string(from: $0) }

        let xAxis = timeChartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.granularity = 1
        xAxis.granularityEnabled = true
        xAxis.valueFormatter = IndexAxisValueFormatter(values: labels)
        xAxis.setLabelCount(min(6, labels.count), force: false)

        // Y-axel = timmar 0–24 (dashad grid) + solida huvudlinjer 00/06/12/18/24
        let yAxis = timeChartView.leftAxis
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

        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.5)
        xAxis.gridColor = gridLineColor
        xAxis.gridLineWidth = 0.5
        xAxis.gridLineDashLengths = [2, 2]

        yAxis.gridColor = gridLineColor
        yAxis.gridLineWidth = 0.5
        yAxis.gridLineDashLengths = [2, 2]

        timeChartView.rightAxis.enabled = false
        timeChartView.setNeedsDisplay()
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

        // Transparent cell so the themed gradient shows
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.backgroundView = nil
        if #available(iOS 14.0, *) {
            var bg = UIBackgroundConfiguration.clear()
            bg.backgroundColor = .systemGray.withAlphaComponent(0.1)
            cell.backgroundConfiguration = bg
        }

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
