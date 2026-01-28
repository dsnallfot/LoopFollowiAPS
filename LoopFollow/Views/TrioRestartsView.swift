import UIKit
import Charts

/// Enkel loggvy för att fånga noteringar innehållande "Trio startades om" , inspirerad av BGCheckView.
final class TrioRestartsView: ThemedViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Model

    struct RestartEntry {
        let date: Date
        let note: String
    }

    private var entries: [RestartEntry] = []

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
    private var reloadButton: UIBarButtonItem?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Apply themed background (gradient in dark mode)
        updateBackgroundForCurrentMode()
        title = "Trio omstartslogg"

        setupNavigationBar()
        setupTableView()
        setupConstraints()

        loadRestarts()
    }

    // MARK: - Nav bar

    private func setupNavigationBar() {
        // När vi är root i navigationstacken (egen UINavigationController)
        // så är vi i modalt läge. När vi är pushade under SettingsVC är vi inte root.
        let isModalRoot = navigationController?.viewControllers.first === self

        // Reload-knapp (samma look & feel som GlucoseView)
        let reload = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshTapped)
        )
        self.reloadButton = reload

        // Klar-knapp till höger, så det känns som Treatments/Glucose
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
            action: #selector(showRestartStats)
        )

        if isModalRoot {
            // Modalt: visa Klar + statistik, reload på vänster sida
            navigationItem.rightBarButtonItems = [done, statsBtn]
            navigationItem.leftBarButtonItem = reload
        } else {
            // Pushat: ingen Klar-knapp, bara statistik.
            // Back-knappen behålls, reload supplementerar back-knappen.
            navigationItem.rightBarButtonItems = [statsBtn]
            navigationItem.leftItemsSupplementBackButton = true
            navigationItem.leftBarButtonItems = [reload]
        }
    }

    @objc private func doneTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func refreshTapped() {
        loadRestarts()
    }

    @objc private func showRestartStats() {
        let calendar = Calendar.current
        let now = Date()
        let daysBack = min(NightscoutCache.retentionDays, 90)

        guard let startDay = calendar.date(byAdding: .day, value: -(daysBack - 1), to: calendar.startOfDay(for: now)) else {
            return
        }

        var days: [Date] = []
        var counts: [Int] = []
        days.reserveCapacity(daysBack)
        counts.reserveCapacity(daysBack)

        for offset in 0..<daysBack {
            if let day = calendar.date(byAdding: .day, value: offset, to: startDay) {
                days.append(day)
                counts.append(0)
            }
        }

        var indexByDay: [Date: Int] = [:]
        for (idx, day) in days.enumerated() {
            indexByDay[calendar.startOfDay(for: day)] = idx
        }

        for entry in entries {
            if entry.date < startDay || entry.date > now { continue }
            let dayStart = calendar.startOfDay(for: entry.date)
            if let idx = indexByDay[dayStart] {
                counts[idx] += 1
            }
        }

        let restartDates = entries.map { $0.date }

        let statsVC = TrioRestartsStatsViewController(days: days, counts: counts, restartDates: restartDates)
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

    // MARK: - Setup table

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "RestartCell")
        tableView.rowHeight = 50
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
        // Themed background: let gradient show through
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.isOpaque = false
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
        guard let reloadButton = reloadButton else { return }

        if activityIndicator == nil {
            let ind = UIActivityIndicatorView(style: .medium)
            ind.hidesWhenStopped = true
            activityIndicator = ind
        }

        reloadButton.image = nil
        reloadButton.customView = activityIndicator
        activityIndicator?.startAnimating()
    }

    private func hideActivity() {
        activityIndicator?.stopAnimating()
        reloadButton?.customView = nil
        reloadButton?.image = UIImage(systemName: "arrow.clockwise")
        activityIndicator = nil
    }

    /// Hämtar alla `Note`-treatments från cachen vars notes innehåller "Trio startades om".
    private func loadRestarts() {
        showActivity()

        Task {
            let now = Date()
            let cal = Calendar.current

            let start = cal.date(
                byAdding: .day,
                value: -NightscoutCache.retentionDays,
                to: now
            ) ?? now.addingTimeInterval(-90 * 24 * 60 * 60)

            let (_, treatments) = await NightscoutCache.loadWindow(from: start, to: now)

            let restartNotes: [RestartEntry] = treatments.compactMap { t -> RestartEntry? in
                guard t.eventType == "Note" else { return nil }

                guard let note = t.notes, note.contains("Trio startades om") else { return nil }

                let date = t.created_at
                return RestartEntry(date: date, note: note)
            }
            .sorted { $0.date > $1.date }

            await MainActor.run {
                self.entries = restartNotes
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "RestartCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "RestartCell")
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

        // Leading text = note (kompakt, en rad)
        let note = entry.note
        let compact = note.replacingOccurrences(of: "\n", with: " ")
        cell.textLabel?.text = "\(compact)"
        cell.textLabel?.font = .systemFont(ofSize: 16)

        // SF-symbol i imageView (leading) – restart
        cell.imageView?.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        cell.imageView?.tintColor = .systemPurple

        // Right-aligned full date + time
        let rightLabel = UILabel()
        rightLabel.text = DateFormatter.localizedString(from: entry.date, dateStyle: .short, timeStyle: .short)
        rightLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)//.systemFont(ofSize: 14)
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
        let endDate = entry.date + 60 * 180


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
            initialEnd: nil,//endDate,
            modalWithTimestamp: true,
            modalTitleString: "Analys omstart"
        )
        let nav = UINavigationController(rootViewController: analysisVC)
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

        self.present(nav, animated: true) { [weak self] in
            self?.tableView.deselectRow(at: indexPath, animated: true)
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
}

final class TrioRestartsStatsViewController: ThemedTableViewController {

    // Full data set (upp till t.ex. 90 dagar)
    private let allDays: [Date]
    private let allCounts: [Int]
    private let allRestartDates: [Date]

    // Aktuell vy (styrd av segmented control)
    private var selectedDays: [Date] = []
    private var selectedCounts: [Int] = []

    // Restart dates filtered to the selected period (used for longest streak calc)
    private var selectedRestartDates: [Date] = []

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

    private enum ChartMode: CaseIterable {
        case count, time

        var title: String {
            switch self {
            case .count: return "Antal"
            case .time:  return "Tid"
            }
        }
    }

    private var selectedPeriod: PeriodOption = .d90

    private var selectedMode: ChartMode = .count

    private lazy var modeControl: UISegmentedControl = {
        let items = ChartMode.allCases.map { $0.title }
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = ChartMode.allCases.firstIndex(of: selectedMode) ?? 0
        sc.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        return sc
    }()

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

    private let timeChartView: ScatterChartView = {
        let v = ScatterChartView()
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

    init(days: [Date], counts: [Int], restartDates: [Date]) {
        self.allDays = days
        self.allCounts = counts
        self.allRestartDates = restartDates
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
            selectedRestartDates = []
            chartView.data = nil
            tableView.reloadData()
            return
        }

        let n = min(period.days, total)
        let startIndex = max(0, total - n)
        selectedDays = Array(allDays[startIndex..<total])
        selectedCounts = Array(allCounts[startIndex..<total])

        // Compute date range for the selected days and filter restart timestamps into it.
        if let firstDay = selectedDays.first, let lastDay = selectedDays.last {
            let cal = Calendar.current
            let start = cal.startOfDay(for: firstDay)
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: lastDay)) ?? Date.distantFuture
            selectedRestartDates = allRestartDates
                .filter { $0 >= start && $0 < end }
                .sorted()
        } else {
            selectedRestartDates = []
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
        guard index >= 0 && index < ChartMode.allCases.count else { return }
        selectedMode = ChartMode.allCases[index]

        // Visa rätt graf och ladda om data
        let showCount = (selectedMode == .count)
        chartView.isHidden = !showCount
        timeChartView.isHidden = showCount

        loadChartData()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateBackgroundForCurrentMode()
        title = "Statistik"
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

        // Default: Antal
        selectedMode = .count
        if let idx2 = ChartMode.allCases.firstIndex(of: selectedMode) {
            modeControl.selectedSegmentIndex = idx2
        }

        setupChartHeader()
        applyPeriod(initialPeriod)
    }

    // MARK: - Chart header

    private func setupChartHeader() {
        let container = UIView()
        container.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 340)
        container.backgroundColor = .clear
        container.isOpaque = false

        // Let the chart + segmented controls show the underlying gradient
        chartView.backgroundColor = .clear
        timeChartView.backgroundColor = .clear
        periodControl.backgroundColor = .clear
        modeControl.backgroundColor = .clear

        container.addSubview(periodControl)
        container.addSubview(modeControl)
        container.addSubview(chartView)
        container.addSubview(timeChartView)

        periodControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        chartView.translatesAutoresizingMaskIntoConstraints = false
        timeChartView.translatesAutoresizingMaskIntoConstraints = false

        // Default visibility
        chartView.isHidden = false
        timeChartView.isHidden = true

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

            timeChartView.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 12),
            timeChartView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            timeChartView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            timeChartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
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
        guard selectedDays.count == selectedCounts.count, !selectedDays.isEmpty else {
            chartView.data = nil
            timeChartView.data = nil
            chartView.setNeedsDisplay()
            timeChartView.setNeedsDisplay()
            return
        }

        switch selectedMode {
        case .count:
            loadCountChartData()
        case .time:
            loadTimeChartData()
        }
    }

    private func loadCountChartData() {
        var entries: [BarChartDataEntry] = []
        entries.reserveCapacity(selectedDays.count)

        var maxCount = 0
        for (idx, count) in selectedCounts.enumerated() {
            entries.append(BarChartDataEntry(x: Double(idx), y: Double(count)))
            if count > maxCount { maxCount = count }
        }

        let dataSet = BarChartDataSet(entries: entries, label: "")
        dataSet.setColor(.systemPurple.withAlphaComponent(0.7))
        dataSet.drawValuesEnabled = false
        dataSet.barBorderColor = .black
        dataSet.barBorderWidth = 0.5

        let data = BarChartData(dataSet: dataSet)
        chartView.data = data
        chartView.autoScaleMinMaxEnabled = false
        chartView.notifyDataSetChanged()
        
        chartView.drawGridBackgroundEnabled = true
        chartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)

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

        // Y-axel – dynamiskt max utifrån högsta antal restarts på en dag
        let yAxis = chartView.leftAxis
        yAxis.axisMinimum = 0
        let maxY = max(1, maxCount)
        yAxis.axisMaximum = Double(maxY) * 1.2
        yAxis.granularity = 1
        yAxis.granularityEnabled = true
        yAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
            String(format: "%.0f ggr", value)
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

    private func loadTimeChartData() {
        // Bygg upp index per dag för snabb lookup
        let cal = Calendar.current
        var indexByDay: [Date: Int] = [:]
        for (idx, d) in selectedDays.enumerated() {
            indexByDay[cal.startOfDay(for: d)] = idx
        }

        // Skapa scatterpunkter: x = dag-index, y = timmar på dygnet (0–24)
        var points: [ChartDataEntry] = []
        points.reserveCapacity(selectedRestartDates.count)

        for d in selectedRestartDates {
            let dayStart = cal.startOfDay(for: d)
            guard let dayIndex = indexByDay[dayStart] else { continue }

            let comps = cal.dateComponents([.hour, .minute, .second], from: d)
            let h = Double(comps.hour ?? 0)
            let m = Double(comps.minute ?? 0)
            let s = Double(comps.second ?? 0)
            let hourOfDay = h + (m / 60.0) + (s / 3600.0)

            points.append(ChartDataEntry(x: Double(dayIndex), y: hourOfDay))
        }

        let ds = ScatterChartDataSet(entries: points, label: "")
        ds.setColor(.systemPurple.withAlphaComponent(0.8))
        ds.setScatterShape(.circle)
        ds.scatterShapeSize = 7
        ds.drawValuesEnabled = false

        let data = ScatterChartData(dataSet: ds)
        timeChartView.data = data
        timeChartView.autoScaleMinMaxEnabled = false
        timeChartView.notifyDataSetChanged()
        
        timeChartView.drawGridBackgroundEnabled = true
        timeChartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)

        // X-axis labels = datum (kompakt format) för varje index
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

        // Y-axel = timmar på dygnet 0–24
        let yAxis = timeChartView.leftAxis
        yAxis.axisMinimum = 0
        yAxis.axisMaximum = 24

        // Vi vill kunna visa "mindre" (dashed) grid för timmarna, men endast etikettera 00/06/12/18/24.
        // Därför använder vi 1h-granularitet för grid, men tomma labels för allt utom 6-timmarssteg.
        yAxis.granularity = 1
        yAxis.granularityEnabled = true
        yAxis.setLabelCount(25, force: false)
        yAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
            let v = Int(value.rounded())
            guard [0, 6, 12, 18, 24].contains(v) else { return "" }
            return String(format: "%02d:00", v)
        }

        // Rensa tidigare limit-lines (om vi byter period/mode och laddar om)
        yAxis.removeAllLimitLines()

        // Solida "huvudlinjer" vid 00/06/12/18/24
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
    private var daysWithRestarts: Int { selectedCounts.filter { $0 > 0 }.count }
    private var totalRestarts: Int { selectedCounts.reduce(0, +) }
    private var maxRestartsPerDay: Int { selectedCounts.max() ?? 0 }

    /// Longest streak without restarts, measured as the max time gap (in hours) between two consecutive restarts within the selected period.
    private func longestGapWithoutRestartsHours() -> Int? {
        guard selectedRestartDates.count >= 2 else { return nil }
        var best: TimeInterval = 0
        for i in 1..<selectedRestartDates.count {
            let gap = selectedRestartDates[i].timeIntervalSince(selectedRestartDates[i - 1])
            if gap > best { best = gap }
        }
        return Int(best / 3600.0)
    }

    private func percentageString(_ numerator: Int, _ denominator: Int) -> String {
        guard denominator > 0 else { return "0 %" }
        let p = Double(numerator) * 100.0 / Double(denominator)
        return String(format: "%.0f%%", p)
    }

    // MARK: - Table view

    private enum Row: Int, CaseIterable {
        case totalRestarts
        case avgPerDay
        case daysWithRestarts
        case avgPerRestartDay
        case maxPerDay
        case longestNoRestartStreak
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

        let row = Row(rawValue: indexPath.row)!
        switch row {
        case .totalRestarts:
            cell.textLabel?.text = "Totalt antal omstarter"
            cell.detailTextLabel?.text = "\(totalRestarts) ggr"

        case .avgPerDay:
            cell.textLabel?.text = "Medel omstarter per dag"
            if totalDays > 0 {
                let avg = Double(totalRestarts) / Double(totalDays)
                cell.detailTextLabel?.text = String(format: "%.1f ggr", avg)
            } else {
                cell.detailTextLabel?.text = "–"
            }

        case .daysWithRestarts:
            cell.textLabel?.text = "Andel dagar med omstarter"
            cell.detailTextLabel?.text = "\(percentageString(daysWithRestarts, totalDays))"

        case .avgPerRestartDay:
            cell.textLabel?.text = "Medel omstarter per omstart-dag"
            if daysWithRestarts > 0 {
                let avg = Double(totalRestarts) / Double(daysWithRestarts)
                cell.detailTextLabel?.text = String(format: "%.1f ggr", avg)
            } else {
                cell.detailTextLabel?.text = "–"
            }

        case .maxPerDay:
            cell.textLabel?.text = "Högsta antal omstarter per dag"
            cell.detailTextLabel?.text = "\(maxRestartsPerDay) ggr"

        case .longestNoRestartStreak:
            cell.textLabel?.text = "Längsta streak utan omstarter"
            if let hours = longestGapWithoutRestartsHours() {
                cell.detailTextLabel?.text = "\(hours) h"
            } else {
                cell.detailTextLabel?.text = "–"
            }
        }

        return cell
    }
}
