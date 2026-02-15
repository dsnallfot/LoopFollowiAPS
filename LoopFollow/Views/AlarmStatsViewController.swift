//
//  AlarmStatsViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2026-02-15.
//

import UIKit
import Charts

final class AlarmStatsViewController: ThemedViewController {
    
    /// Called when the view controller is dismissed, so the caller can refresh its UI
    var onDismiss: (() -> Void)?

    // MARK: - UI

    private let rangeControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["7", "14", "30", "90"])
        sc.selectedSegmentIndex = 0
        return sc
    }()

    private let chartModeControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Antal", "Tid"])
        sc.selectedSegmentIndex = 0
        return sc
    }()

    private let barChartView = BarChartView()
    private let scatterChartView = ScatterChartView()

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private struct StatRow {
        let title: String
        let value: String
    }

    private var statRows: [StatRow] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Alarmhistorik"
        updateBackgroundForCurrentMode()
        configureDoneButton()

        rangeControl.addTarget(self, action: #selector(didChangeControls), for: .valueChanged)
        chartModeControl.addTarget(self, action: #selector(didChangeControls), for: .valueChanged)

        setupUI()
        setupCharts()
        reloadAll()
    }
    
    private func configureDoneButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )
    }
    
    @objc private func doneTapped() {
        // Inform caller so it can refresh its UI (e.g. ModernAlarmViewController)
        onDismiss?()
        dismiss(animated: true, completion: nil)
    }

    @objc private func didChangeControls() {
        reloadAll()
    }

    // MARK: - UI setup

    private func setupUI() {
        let controlsStack = UIStackView(arrangedSubviews: [rangeControl, chartModeControl])
        controlsStack.axis = .vertical
        controlsStack.spacing = 10
        controlsStack.translatesAutoresizingMaskIntoConstraints = false

        barChartView.translatesAutoresizingMaskIntoConstraints = false
        scatterChartView.translatesAutoresizingMaskIntoConstraints = false

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.isScrollEnabled = false
        tableView.backgroundColor = .clear
        tableView.backgroundView = tableView.backgroundView
        tableView.isOpaque = false
        tableView.layer.backgroundColor = UIColor.clear.cgColor

        view.addSubview(controlsStack)
        view.addSubview(barChartView)
        view.addSubview(scatterChartView)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            controlsStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            controlsStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            controlsStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),

            barChartView.topAnchor.constraint(equalTo: controlsStack.bottomAnchor, constant: 12),
            barChartView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            barChartView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            barChartView.heightAnchor.constraint(equalToConstant: 260),

            scatterChartView.topAnchor.constraint(equalTo: controlsStack.bottomAnchor, constant: 12),
            scatterChartView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            scatterChartView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            scatterChartView.heightAnchor.constraint(equalToConstant: 260),

            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        // Table should attach to whichever chart is visible
        let tableTopToBar = tableView.topAnchor.constraint(equalTo: barChartView.bottomAnchor, constant: 8)
        tableTopToBar.priority = .required
        tableTopToBar.isActive = true

        let tableTopToScatter = tableView.topAnchor.constraint(equalTo: scatterChartView.bottomAnchor, constant: 8)
        tableTopToScatter.priority = .required
        tableTopToScatter.isActive = true

        updateVisibleChart()
    }

    private func updateVisibleChart() {
        let showCount = (chartModeControl.selectedSegmentIndex == 0)
        barChartView.isHidden = !showCount
        scatterChartView.isHidden = showCount
    }

    // MARK: - Charts

    private func setupCharts() {
        // Bar chart (counts/day)
        barChartView.chartDescription.enabled = false
        barChartView.legend.enabled = false
        barChartView.rightAxis.enabled = false
        barChartView.dragEnabled = false
        barChartView.pinchZoomEnabled = false
        barChartView.doubleTapToZoomEnabled = false
        barChartView.scaleXEnabled = false
        barChartView.scaleYEnabled = false


        // Needed for gridBackgroundColor to actually render
        barChartView.drawGridBackgroundEnabled = true
        barChartView.backgroundColor = .clear
        barChartView.drawBordersEnabled = false

        barChartView.xAxis.labelPosition = .bottom
        barChartView.xAxis.drawGridLinesEnabled = true
        barChartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)
        barChartView.xAxis.granularity = 1

        barChartView.leftAxis.axisMinimum = 0
        barChartView.leftAxis.drawGridLinesEnabled = true

        // Scatter chart (time-of-day)
        scatterChartView.chartDescription.enabled = false
        scatterChartView.legend.enabled = false
        scatterChartView.rightAxis.enabled = false
        scatterChartView.dragEnabled = false
        scatterChartView.pinchZoomEnabled = false
        scatterChartView.doubleTapToZoomEnabled = false
        scatterChartView.scaleXEnabled = false
        scatterChartView.scaleYEnabled = false

        // Needed for gridBackgroundColor to actually render
        scatterChartView.drawGridBackgroundEnabled = true
        scatterChartView.backgroundColor = .clear
        scatterChartView.drawBordersEnabled = false

        scatterChartView.xAxis.labelPosition = .bottom
        scatterChartView.xAxis.drawGridLinesEnabled = true
        scatterChartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)
        scatterChartView.xAxis.granularity = 1

        scatterChartView.leftAxis.axisMinimum = 0
        scatterChartView.leftAxis.axisMaximum = 24
        scatterChartView.leftAxis.granularity = 2
        scatterChartView.leftAxis.drawGridLinesEnabled = true
    }

    // MARK: - Data

    private func selectedDays() -> Int {
        switch rangeControl.selectedSegmentIndex {
        case 0: return 7
        case 1: return 14
        case 2: return 30
        default: return 90
        }
    }

    private func reloadAll() {
        updateVisibleChart()

        let days = selectedDays()
        let now = Date()
        let calendar = Calendar.current

        let startOfToday = calendar.startOfDay(for: now)
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) else { return }

        let raw = Storage.shared.alarmHistory
        let windowStart = startDate.timeIntervalSince1970
        let windowEnd = now.timeIntervalSince1970

        let alarmsInWindow = raw
            .filter { $0.date >= windowStart && $0.date <= windowEnd }
            .sorted { $0.date < $1.date }

        var counts: [Int] = Array(repeating: 0, count: days)
        var scatterEntries: [ChartDataEntry] = []

        for alarm in alarmsInWindow {
            let alarmDate = Date(timeIntervalSince1970: alarm.date)
            let dayIndex = calendar.dateComponents([.day], from: startDate, to: calendar.startOfDay(for: alarmDate)).day ?? 0
            if dayIndex >= 0 && dayIndex < days {
                counts[dayIndex] += 1

                let comps = calendar.dateComponents([.hour, .minute], from: alarmDate)
                let h = Double(comps.hour ?? 0)
                let m = Double(comps.minute ?? 0) / 60.0
                let timeOfDay = h + m

                scatterEntries.append(ChartDataEntry(x: Double(dayIndex), y: timeOfDay))
            }
        }

        updateBarChart(counts: counts, startDate: startDate, days: days)
        updateScatterChart(entries: scatterEntries, startDate: startDate, days: days)

        statRows = buildStats(days: days, startDate: startDate, now: now, alarms: alarmsInWindow, counts: counts)
        tableView.reloadData()
    }

    private func updateBarChart(counts: [Int], startDate: Date, days: Int) {
        var entries: [BarChartDataEntry] = []
        entries.reserveCapacity(counts.count)

        for (i, c) in counts.enumerated() {
            entries.append(BarChartDataEntry(x: Double(i), y: Double(c)))
        }

        let set = BarChartDataSet(entries: entries)
        set.drawValuesEnabled = false
        set.setColor(.label)
        set.barBorderColor = .systemGray
        set.barBorderWidth = 0.5

        let data = BarChartData(dataSet: set)
        data.barWidth = 0.8
        barChartView.data = data

        barChartView.xAxis.valueFormatter = AlarmDateAxisFormatter(startDate: startDate)
        barChartView.xAxis.labelCount = min(days, 7)

        barChartView.notifyDataSetChanged()
        barChartView.setNeedsDisplay()
    }

    private func updateScatterChart(entries: [ChartDataEntry], startDate: Date, days: Int) {
        let set = ScatterChartDataSet(entries: entries)
        set.drawValuesEnabled = false
        set.setScatterShape(.circle)
        set.setColor(.label)
        set.scatterShapeSize = 5

        let data = ScatterChartData(dataSet: set)
        scatterChartView.data = data

        scatterChartView.xAxis.valueFormatter = AlarmDateAxisFormatter(startDate: startDate)
        scatterChartView.xAxis.labelCount = min(days, 7)

        scatterChartView.notifyDataSetChanged()
        scatterChartView.setNeedsDisplay()
    }

    private func buildStats(days: Int, startDate: Date, now: Date, alarms: [AlarmHistoryEntry], counts: [Int]) -> [StatRow] {
        let total = alarms.count
        let avgPerDay = days > 0 ? Double(total) / Double(days) : 0
        let maxSameDay = counts.max() ?? 0

        // Night alarms between 22:00–06:00
        let calendar = Calendar.current
        var nightTotal = 0
        for a in alarms {
            let d = Date(timeIntervalSince1970: a.date)
            let h = calendar.component(.hour, from: d)
            if h >= 22 || h < 6 { nightTotal += 1 }
        }
        let avgNightPerDay = days > 0 ? Double(nightTotal) / Double(days) : 0

        // Longest streak without alarms (hours) within selected window
        let windowStart = startDate.timeIntervalSince1970
        let windowEnd = now.timeIntervalSince1970

        var last = windowStart
        var longest: TimeInterval = 0

        for a in alarms {
            let gap = a.date - last
            if gap > longest { longest = gap }
            last = a.date
        }

        let tail = windowEnd - last
        if tail > longest { longest = tail }

        let longestHours = longest / 3600.0

        func fmt1(_ v: Double) -> String {
            if v.isNaN || v.isInfinite { return "0.0" }
            return String(format: "%.1f", v)
        }

        return [
            StatRow(title: "Triggade larm totalt", value: "\(total) st"),
            StatRow(title: "Medel larm per dag", value: "\(fmt1(avgPerDay)) st"),
            StatRow(title: "Högsta antal larm samma dag", value: "\(maxSameDay) st"),
            StatRow(title: "Medel larm nattid (22–06)", value: "\(fmt1(avgNightPerDay)) st"),
            StatRow(title: "Längste streak utan larm", value: "\(fmt1(longestHours)) h")
        ]
    }
}

extension AlarmStatsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { statRows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        let row = statRows[indexPath.row]
        cell.textLabel?.text = row.title
        cell.detailTextLabel?.text = row.value
        cell.selectionStyle = .none
        
        // Transparent cell so the themed gradient shows
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.backgroundView = nil
        if #available(iOS 14.0, *) {
            var bg = UIBackgroundConfiguration.clear()
            bg.backgroundColor = .systemGray.withAlphaComponent(0.15)
            cell.backgroundConfiguration = bg
        }
        cell.textLabel?.backgroundColor = .clear
        cell.detailTextLabel?.backgroundColor = .clear
        return cell
    }
}

private final class AlarmDateAxisFormatter: AxisValueFormatter {
    private let startDate: Date
    private let calendar = Calendar.current
    private let df: DateFormatter = {
        let d = DateFormatter()
        d.dateFormat = "d/M" // e.g. 5/2
        return d
    }()

    init(startDate: Date) {
        self.startDate = startDate
    }

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let i = Int(round(value))
        guard i >= 0 else { return "" }
        guard let d = calendar.date(byAdding: .day, value: i, to: startDate) else { return "" }
        return df.string(from: d)
    }
}
