//
//  EnteredByView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2026-01-26.
//

import UIKit
import Charts

/// Radmodell för tabellen "Manuella behandlingar"
private struct EnteredByRow {
    let title: String
    let bolusCount: Int
    let bolusPercent: Int?
    let mealCount: Int
    let mealPercent: Int?
    let totalCount: Int
    let totalPercent: Int?
    let isBold: Bool
    let isSpacer: Bool
    let hideValues: Bool           // för rena rubriker
    let displayAsPercentOnly: Bool // för LF/CC-rader i nedersta sektionen
    let highlightAsTotal: Bool     // blå text för totals-rader
    let highlightRowBackground: Bool // lila radbakgrund
}

/// Enkel cell med fyra kolumn-labels
private final class EnteredByCell: UITableViewCell {

    let titleLabel = UILabel()
    let bolusLabel = UILabel()
    let mealLabel  = UILabel()
    let totalLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        titleLabel.textAlignment = .left
        bolusLabel.textAlignment = .right
        mealLabel.textAlignment  = .right
        totalLabel.textAlignment = .right

        // Små typsnitt, monospaced för siffror
        let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        bolusLabel.font = valueFont
        mealLabel.font  = valueFont
        totalLabel.font = valueFont

        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, bolusLabel, mealLabel, totalLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Se till att de tre värdekolumnerna är lika breda och “hålls ihop”
        bolusLabel.setContentHuggingPriority(.required, for: .horizontal)
        mealLabel.setContentHuggingPriority(.required, for: .horizontal)
        totalLabel.setContentHuggingPriority(.required, for: .horizontal)

        contentView.addSubview(stack)

        // Kolumnbredder: ge bolus-kolumnen en relativ bredd mot cellens bredd
        // och låt Måltider/Total matcha samma bredd. Detta gäller för alla rader
        // (inklusive headern) och ger Excel-liknande raka kolumner.
        let bolusWidth = bolusLabel.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.13)
        let mealWidth  = mealLabel.widthAnchor.constraint(equalTo: bolusLabel.widthAnchor)
        let totalWidth = totalLabel.widthAnchor.constraint(equalTo: bolusLabel.widthAnchor)

        NSLayoutConstraint.activate([
            bolusWidth,
            mealWidth,
            totalWidth,
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with row: EnteredByRow, isHeader: Bool) {
        if row.isSpacer {
            titleLabel.text = ""
            bolusLabel.text = ""
            mealLabel.text  = ""
            totalLabel.text = ""
            return
        }

        // Reset bakgrund pga cell-återanvändning
            contentView.backgroundColor = .clear
            backgroundColor = .clear

            titleLabel.text = row.title

        // Färg för totals-rader
        let totalColor = UIColor.insulin.withAlphaComponent(1.0)
        let defaultColor = UIColor.label

        let appliedColor: UIColor = row.highlightAsTotal ? totalColor : defaultColor
        titleLabel.textColor = appliedColor
        bolusLabel.textColor = appliedColor
        mealLabel.textColor  = appliedColor
        totalLabel.textColor = appliedColor
        
        if row.highlightRowBackground {
                contentView.backgroundColor = UIColor.insulin.withAlphaComponent(0.5)
            }

        func format(_ count: Int, _ percent: Int?, asPercentOnly: Bool) -> String {
            if row.hideValues {
                return ""
            }
            if asPercentOnly {
                guard let p = percent else { return "0 %" }
                return "\(p) %"
            } else {
                return "\(count)"
            }
        }

        bolusLabel.text = format(row.bolusCount, row.bolusPercent, asPercentOnly: row.displayAsPercentOnly)
        mealLabel.text  = format(row.mealCount, row.mealPercent, asPercentOnly: row.displayAsPercentOnly)
        totalLabel.text = format(row.totalCount, row.totalPercent, asPercentOnly: row.displayAsPercentOnly)

        if isHeader {
            let headerFont = UIFont.preferredFont(forTextStyle: .caption2)
                .withTraits(traits: .traitBold)
            titleLabel.font = headerFont
            bolusLabel.font = headerFont
            mealLabel.font  = headerFont
            totalLabel.font = headerFont
        } else if row.highlightAsTotal {
            // Gulmarkerade totals-rader: fet text i alla kolumner
            let totalFont = UIFont.preferredFont(forTextStyle: .footnote)
                .withTraits(traits: .traitBold)
            titleLabel.font = totalFont
            bolusLabel.font = totalFont
            mealLabel.font  = totalFont
            totalLabel.font = totalFont
        } else if row.isBold {
            // Rubrikrader (t.ex. Mamma Totalt) – fet titel, normala siffror
            titleLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
                .withTraits(traits: .traitBold)
            let valueFont = UIFont.preferredFont(forTextStyle: .footnote)
            bolusLabel.font = valueFont
            mealLabel.font  = valueFont
            totalLabel.font = valueFont
        } else {
            let valueFont = UIFont.preferredFont(forTextStyle: .footnote)
            titleLabel.font = valueFont
            bolusLabel.font = valueFont
            mealLabel.font  = valueFont
            totalLabel.font = valueFont
        }    }
}

final class EnteredByView: ThemedViewController, UITableViewDataSource, UITableViewDelegate {

    private let startTime: Date
    private let endTime: Date
    private var currentStart: Date
    private var currentEnd: Date
    private var treatments: [Treatment] = []

    private let dateLabel = UILabel()
    // New date picker UI
    private let startDatePicker = UIDatePicker()
    private let endDatePicker = UIDatePicker()
    private let datePickersStack = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let chartView: BarChartView = {
        let v = BarChartView()
        v.legend.enabled = false
        v.chartDescription.enabled = false
        v.rightAxis.enabled = false
        v.minOffset = 8

        // Ingen zoom/scroll – allt viktigt syns i grundläget
        v.pinchZoomEnabled = false
        v.doubleTapToZoomEnabled = false
        v.scaleXEnabled = false
        v.scaleYEnabled = false
        v.dragEnabled = false
        v.highlightPerTapEnabled = false
        v.highlightPerDragEnabled = false
        v.drawMarkers = false
        v.maxVisibleCount = 1000000

        return v
    }()
    
    private let chartLoadingIndicator: UIActivityIndicatorView = {
        let v = UIActivityIndicatorView(style: .medium)
        v.hidesWhenStopped = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let xAxisLabelsStack: UIStackView = {()
        let labels = ["Mamma", "Pappa", "Resurs", "Trio"].map { title -> UILabel in
            let label = UILabel()
            label.text = title
            label.textAlignment = .center
            label.font = UIFont.preferredFont(forTextStyle: .caption2)
            label.textColor = .label
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            return label
        }

        let stack = UIStackView(arrangedSubviews: labels)
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var rows: [EnteredByRow] = []

    // Event-typer vi tolkar som bolus respektive måltid
    // Endast manuella bolusar – SMB är automatisk och ska inte räknas här
    private let bolusTypes: Set<String> = ["Bolus", "Correction Bolus", "Meal Bolus", "Insulinpenna"]
    private let mealTypes: Set<String>  = ["Carb Correction", "Kolhydrater", "Dextro", "Måltid"]

    init(startTime: Date, endTime: Date) {
        self.startTime = startTime
        self.endTime   = endTime
        self.currentStart = startTime
        self.currentEnd   = endTime
        super.init(nibName: nil, bundle: nil)
    }
    


    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Manuella behandlingar"
        updateBackgroundForCurrentMode()

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissSelf)
        )

        //setupHeaderLabel() // No longer needed as visible UI
        setupDatePickers()
        setupTableView()
        loadTreatmentsAndBuildRows()
    }
    private func loadTreatmentsAndBuildRows(forcedStart: Date? = nil, forcedEnd: Date? = nil) {
        Task {
            await MainActor.run {
                self.startDatePicker.isEnabled = false
                self.endDatePicker.isEnabled = false
                self.chartLoadingIndicator.startAnimating()
            }

            let from = forcedStart ?? self.startTime
            let to   = forcedEnd   ?? self.endTime

            // Persist the updated window
            self.currentStart = from
            self.currentEnd   = to

            let (_, treatsJSON) = await NightscoutCache.loadWindow(from: from, to: to)

            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            iso.timeZone = TimeZone(secondsFromGMT: 0)

            let loadedTreatments: [Treatment] = treatsJSON.compactMap { tjson in
                Treatment(dictionary: [
                    "_id":       tjson._id as AnyObject,
                    "eventType": tjson.eventType as AnyObject,
                    "enteredBy": tjson.enteredBy as AnyObject,
                    "created_at": iso.string(from: tjson.created_at) as AnyObject,
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

            await MainActor.run {
                self.treatments = loadedTreatments
                self.buildRows()
                self.chartLoadingIndicator.stopAnimating()
                self.startDatePicker.isEnabled = true
                self.endDatePicker.isEnabled = true
            }
        }
    }

    // MARK: - UI

    // Date pickers for selecting whole days
    private func setupDatePickers() {
        startDatePicker.datePickerMode = .date
        endDatePicker.datePickerMode = .date

        startDatePicker.preferredDatePickerStyle = .compact
        endDatePicker.preferredDatePickerStyle = .compact

        startDatePicker.locale = Locale(identifier: "sv_SE")
        endDatePicker.locale = Locale(identifier: "sv_SE")
        let today = Calendar.current.startOfDay(for: Date())
        startDatePicker.maximumDate = today
        endDatePicker.maximumDate = today

        startDatePicker.addTarget(self, action: #selector(datePickerChanged), for: .valueChanged)
        endDatePicker.addTarget(self, action: #selector(datePickerChanged), for: .valueChanged)

        // Initiera med inkommande datumintervall (hela dagar)
        startDatePicker.date = Calendar.current.startOfDay(for: startTime)
        endDatePicker.date = Calendar.current.startOfDay(for: endTime)

        datePickersStack.axis = .horizontal
        datePickersStack.alignment = .center
        datePickersStack.distribution = .equalSpacing
        datePickersStack.translatesAutoresizingMaskIntoConstraints = false

        let fromLabel = UILabel()
        fromLabel.text = "Vald period:"
        fromLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)

        let toLabel = UILabel()
        toLabel.text = ""
        toLabel.font = UIFont.preferredFont(forTextStyle: .footnote)

        datePickersStack.addArrangedSubview(fromLabel)
        datePickersStack.addArrangedSubview(UIView()) // spacer
        datePickersStack.addArrangedSubview(startDatePicker)
        //datePickersStack.addArrangedSubview(toLabel)
        datePickersStack.addArrangedSubview(endDatePicker)
    }

    @objc private func datePickerChanged() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        if startDatePicker.date > today { startDatePicker.date = today }
        if endDatePicker.date > today { endDatePicker.date = today }
        if endDatePicker.date < startDatePicker.date {
            endDatePicker.date = startDatePicker.date
        }

        let newStart = cal.startOfDay(for: startDatePicker.date)
        let newEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: endDatePicker.date)) ?? endDatePicker.date

        loadTreatmentsAndBuildRows(forcedStart: newStart, forcedEnd: newEnd)
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.separatorColor = UIColor.white.withAlphaComponent(0.08)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(EnteredByCell.self, forCellReuseIdentifier: "EnteredByCell")

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Bygg en header som innehåller datumrad + stapeldiagram
        let header = UIView()
        header.backgroundColor = .clear

        datePickersStack.translatesAutoresizingMaskIntoConstraints = false
        chartView.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(datePickersStack)
        header.addSubview(chartView)
        header.addSubview(xAxisLabelsStack)

        chartView.addSubview(chartLoadingIndicator)

        NSLayoutConstraint.activate([
            chartLoadingIndicator.centerXAnchor.constraint(equalTo: chartView.centerXAnchor),
            chartLoadingIndicator.centerYAnchor.constraint(equalTo: chartView.centerYAnchor)
        ])

        NSLayoutConstraint.activate([
            datePickersStack.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            datePickersStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            datePickersStack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),

            chartView.topAnchor.constraint(equalTo: datePickersStack.bottomAnchor, constant: 8),
            chartView.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            chartView.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            chartView.heightAnchor.constraint(equalToConstant: 140),

            xAxisLabelsStack.topAnchor.constraint(equalTo: chartView.bottomAnchor, constant: -2),
            xAxisLabelsStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 32),
            xAxisLabelsStack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            xAxisLabelsStack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8)
        ])

        // Sätt initial storlek; bredd justeras i viewDidLayoutSubviews
        header.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 230)
        tableView.tableHeaderView = header
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let header = tableView.tableHeaderView {
            let targetSize = CGSize(width: tableView.bounds.width, height: 230)
            if header.frame.size != targetSize {
                header.frame.size = targetSize
                tableView.tableHeaderView = header
            }
        }
    }

    @objc private func dismissSelf() {
        dismiss(animated: true, completion: nil)
    }

    private func updateChart(mamma: (bolus: Int, meal: Int),
                             pappa: (bolus: Int, meal: Int),
                             resurs: (bolus: Int, meal: Int),
                             trioBolus: Int,
                             trioMeal: Int) {

        let groups: [(bolus: Int, meal: Int)] = [
            mamma,
            pappa,
            resurs,
            (trioBolus, trioMeal)
        ]
        let labels = ["Mamma", "Pappa", "Resurs", "Trio"]

        var entries: [BarChartDataEntry] = []
        entries.reserveCapacity(groups.count)

        var maxTotal = 0
        for (index, g) in groups.enumerated() {
            let bolus = Double(g.bolus)
            let meal  = Double(g.meal)
            entries.append(BarChartDataEntry(x: Double(index), yValues: [bolus, meal]))
            let total = g.bolus + g.meal
            if total > maxTotal { maxTotal = total }
        }

        let dataSet = BarChartDataSet(entries: entries, label: "")
        dataSet.colors = [UIColor.insulin, UIColor.carbs]
        dataSet.stackLabels = ["Bolus", "Måltid"]
        dataSet.drawValuesEnabled = false

        let data = BarChartData(dataSet: dataSet)
        data.barWidth = 0.6
        chartView.data = data

        chartView.drawGridBackgroundEnabled = true
        chartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)

        // X-axis – använd bara position för bars; etiketter ritas i egen UIStackView under grafen
        let xAxis = chartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.granularity = 1
        xAxis.granularityEnabled = true
        xAxis.drawLabelsEnabled = false  // vi visar custom-etiketter i xAxisLabelsStack

        // Se alltid till att alla fyra kategorier syns, även om någon har 0 i data
        xAxis.axisMinimum = -0.5
        xAxis.axisMaximum = Double(labels.count) - 0.5
        xAxis.centerAxisLabelsEnabled = false

        chartView.fitBars = true

        // Y-axis configuration
        let yAxis = chartView.leftAxis
        yAxis.axisMinimum = 0
        let maxY = max(1, maxTotal)
        yAxis.axisMaximum = Double(maxY) * 1.2
        yAxis.granularity = maxY <= 10 ? 1 : max(1, floor(Double(maxY) / 5.0))
        yAxis.granularityEnabled = true
        
        yAxis.gridColor = UIColor.lightGray.withAlphaComponent(0.5)
        yAxis.gridLineWidth = 0.5
        yAxis.gridLineDashLengths = [2, 2]

        chartView.rightAxis.enabled = false
        
        // Custom X-axis renderer to draw grid lines between bars
        chartView.xAxis.drawGridLinesEnabled = false  // Disable default grid
        
        chartView.notifyDataSetChanged()
        chartView.setNeedsDisplay()
    }

    // MARK: - Data / beräkningar

    private func buildRows() {
        // Filtrera behandlingar inom det nuvarande fönstret och som är relevanta (bolus/måltid)
        let relevant = treatments.filter { treatment in
            let t = treatment.timestamp
            guard t >= currentStart && t <= currentEnd else { return false }

            let et = treatment.eventType

            // Exkludera automatiska Fett & Protein-poster:
            // Carb Correction utan foodType är auto/FPU och ska inte räknas som manuell måltid här.
            if et == "Carb Correction" {
                let foodType = treatment.rawData["foodType"] as? String ?? ""
                if foodType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return false
                }
            }

            return bolusTypes.contains(et) || mealTypes.contains(et)
        }

        guard !relevant.isEmpty else {
            chartView.data = nil
            chartView.setNeedsDisplay()
            chartLoadingIndicator.stopAnimating()
            startDatePicker.isEnabled = true
            endDatePicker.isEnabled = true
            rows = [
                EnteredByRow(
                    title: "Inga manuella behandlingar i valt tidsintervall",
                    bolusCount: 0, bolusPercent: nil,
                    mealCount: 0, mealPercent: nil,
                    totalCount: 0, totalPercent: nil,
                    isBold: false,
                    isSpacer: false,
                    hideValues: false,
                    displayAsPercentOnly: false,
                    highlightAsTotal: false,
                    highlightRowBackground: false
                )
            ]
            tableView.reloadData()
            return
        }

        // Totals
        var totalBolus = 0
        var totalMeal  = 0

        // Person + app-kombinationer, t.ex. "Mamma_LF"
        typealias Key = String
        var bolusByKey: [Key: Int] = [:]
        var mealByKey:  [Key: Int] = [:]

        // App-summeringar oberoende av person
        var bolusByApp: [String: Int] = [:]   // "LF", "CC", "Trio"
        var mealByApp:  [String: Int] = [:]

        func inc(_ dict: inout [Key: Int], key: Key, amount: Int = 1) {
            dict[key, default: 0] += amount
        }

        func classifyPerson(_ enteredBy: String) -> String? {
            if enteredBy.contains("Mamma") { return "Mamma" }
            if enteredBy.contains("Pappa") { return "Pappa" }
            if enteredBy.contains("Resurs") { return "Resurs" }
            return nil
        }

        func classifyApp(_ enteredBy: String) -> String {
            if enteredBy.contains(" LF") || enteredBy.contains("LF") || enteredBy.contains("Loop") {
                return "LF"   // Loop Follow
            }
            if enteredBy.contains(" CC") || enteredBy.contains("CC") || enteredBy.contains("Carb") {
                return "CC"   // Carb Counter
            }
            // default: Trio / annat
            return "Trio"
        }

        for t in relevant {
            let et = t.eventType
            let enteredBy = (t.rawData["enteredBy"] as? String) ?? ""

            let isBolus = bolusTypes.contains(et)
            let isMeal  = mealTypes.contains(et)

            if isBolus { totalBolus += 1 }
            if isMeal  { totalMeal  += 1 }

            let app = classifyApp(enteredBy)
            let person = classifyPerson(enteredBy)

            if isBolus {
                bolusByApp[app, default: 0] += 1
            }
            if isMeal {
                mealByApp[app, default: 0] += 1
            }

            if let person = person {
                let key = "\(person) \(app)"
                if isBolus { inc(&bolusByKey, key: key) }
                if isMeal  { inc(&mealByKey,  key: key) }
            }
        }

        let totalAll = totalBolus + totalMeal

        func pct(_ part: Int, of total: Int) -> Int? {
            guard total > 0, part > 0 else { return 0 }
            return Int(round((Double(part) / Double(total)) * 100.0))
        }

        // Hjälpare för att plocka combos
        func countsFor(person: String) -> (bolus: Int, meal: Int) {
            let lfKey = "\(person) LF"
            let ccKey = "\(person) CC"
            let trioKey = "\(person) Trio"

            let bolus = (bolusByKey[lfKey] ?? 0) +
                        (bolusByKey[ccKey] ?? 0) +
                        (bolusByKey[trioKey] ?? 0)
            let meal  = (mealByKey[lfKey] ?? 0) +
                        (mealByKey[ccKey] ?? 0) +
                        (mealByKey[trioKey] ?? 0)
            return (bolus, meal)
        }

        func countsFor(person: String, app: String) -> (bolus: Int, meal: Int) {
            let key = "\(person) \(app)"
            return (bolusByKey[key] ?? 0, mealByKey[key] ?? 0)
        }

        // Person-summor
        let mamma = countsFor(person: "Mamma")
        let pappa = countsFor(person: "Pappa")
        let resurs = countsFor(person: "Resurs")

        let mammaTotal = mamma.bolus + mamma.meal
        let pappaTotal = pappa.bolus + pappa.meal
        let resursTotal = resurs.bolus + resurs.meal

        // Första blocket – Mamma / Pappa / Resurs / Trio / Totalt
        let firstTrioBolus = max(0, totalBolus - mamma.bolus - pappa.bolus - resurs.bolus)
        let firstTrioMeal  = max(0, totalMeal  - mamma.meal  - pappa.meal  - resurs.meal)
        let firstTrioTotal = firstTrioBolus + firstTrioMeal

        let totalRowTotal = totalAll

        // Uppdatera stapeldiagrammet (Mamma/Pappa/Resurs/Trio)
        updateChart(
            mamma: mamma,
            pappa: pappa,
            resurs: resurs,
            trioBolus: firstTrioBolus,
            trioMeal: firstTrioMeal
        )

        // Andra blocket – Loop Follow / Carb Counter / Trio / Totalt
        let lfBolus = bolusByApp["LF"] ?? 0
        let lfMeal  = mealByApp["LF"] ?? 0
        let lfTotal = lfBolus + lfMeal

        let ccBolus = bolusByApp["CC"] ?? 0
        let ccMeal  = mealByApp["CC"] ?? 0
        let ccTotal = ccBolus + ccMeal

        let appTrioBolus = bolusByApp["Trio"] ?? 0
        let appTrioMeal  = mealByApp["Trio"] ?? 0
        let appTrioTotal = appTrioBolus + appTrioMeal

        // Tredje blocket – Mamma/Pappa/Resurs per app
        let mammaLF = countsFor(person: "Mamma", app: "LF")
        let mammaCC = countsFor(person: "Mamma", app: "CC")
        let pappaLF = countsFor(person: "Pappa", app: "LF")
        let pappaCC = countsFor(person: "Pappa", app: "CC")
        let resursLF = countsFor(person: "Resurs", app: "LF")
        let resursCC = countsFor(person: "Resurs", app: "CC")

        func row(_ title: String,
                 bolus: Int, meal: Int,
                 isBold: Bool = false,
                 isSpacer: Bool = false,
                 hideValues: Bool = false,
                 displayAsPercentOnly: Bool = false,
                 highlightAsTotal: Bool = false,
                 highlightRowBackground: Bool = false) -> EnteredByRow {

            let total = bolus + meal
            return EnteredByRow(
                title: title,
                bolusCount: bolus,
                bolusPercent: pct(bolus, of: totalBolus),
                mealCount: meal,
                mealPercent: pct(meal, of: totalMeal),
                totalCount: total,
                totalPercent: pct(total, of: totalAll),
                isBold: isBold,
                isSpacer: isSpacer,
                hideValues: hideValues,
                displayAsPercentOnly: displayAsPercentOnly,
                highlightAsTotal: highlightAsTotal,
                highlightRowBackground: highlightRowBackground
            )
        }

        var rows: [EnteredByRow] = []

        // Header-rad
        rows.append(
            EnteredByRow(
                title: "Inlagt av",
                bolusCount: 0, bolusPercent: nil,
                mealCount: 0, mealPercent: nil,
                totalCount: 0, totalPercent: nil,
                isBold: true,
                isSpacer: false,
                hideValues: false,
                displayAsPercentOnly: false,
                highlightAsTotal: false,
                highlightRowBackground: true
            )
        )

        // Första blocket
        rows.append(row("Mamma", bolus: mamma.bolus, meal: mamma.meal))
        rows.append(row("Pappa", bolus: pappa.bolus, meal: pappa.meal))
        rows.append(row("Resurs", bolus: resurs.bolus, meal: resurs.meal))
        rows.append(row("Trio",   bolus: firstTrioBolus, meal: firstTrioMeal))
        rows.append(row("Totalt", bolus: totalBolus, meal: totalMeal, isBold: true, highlightAsTotal: true))

        // Spacer
        rows.append(
            EnteredByRow(title: "",
                         bolusCount: 0, bolusPercent: nil,
                         mealCount: 0, mealPercent: nil,
                         totalCount: 0, totalPercent: nil,
                         isBold: false,
                         isSpacer: true,
                         hideValues: true,
                         displayAsPercentOnly: false,
                         highlightAsTotal: false,
                         highlightRowBackground: false)
        )

        // Section header: Behandlingar per system
        rows.append(
            row("Behandlingar/system",
                bolus: 0,
                meal: 0,
                isBold: true,
                hideValues: true,
                highlightRowBackground: true)
        )

        // Andra blocket – appar
        rows.append(row("Loop Follow", bolus: lfBolus, meal: lfMeal))
        rows.append(row("Carb Counter", bolus: ccBolus, meal: ccMeal))
        rows.append(row("Trio", bolus: appTrioBolus, meal: appTrioMeal))
        rows.append(row("Totalt", bolus: totalBolus, meal: totalMeal, isBold: true, highlightAsTotal: true))

        // Spacer
        rows.append(
            EnteredByRow(title: "",
                         bolusCount: 0, bolusPercent: nil,
                         mealCount: 0, mealPercent: nil,
                         totalCount: 0, totalPercent: nil,
                         isBold: false,
                         isSpacer: true,
                         hideValues: true,
                         displayAsPercentOnly: false,
                         highlightAsTotal: false,
                         highlightRowBackground: false)
        )

        // Section header: Andel behandlingar per system
        rows.append(
            row("Andel behandlingar/system",
                bolus: 0,
                meal: 0,
                isBold: true,
                hideValues: true,
                highlightRowBackground: true)
        )

        // Tredje blocket – Mamma/Pappa/Resurs per app (andel per system)

        // Mamma
        rows.append(row("Mamma Totalt",
                        bolus: mamma.bolus,
                        meal: mamma.meal,
                        isBold: true,
                        highlightAsTotal: true))

        let mammaLFRow = EnteredByRow(
            title: "Mamma LF",
            bolusCount: mammaLF.bolus,
            bolusPercent: pct(mammaLF.bolus, of: mamma.bolus),
            mealCount: mammaLF.meal,
            mealPercent: pct(mammaLF.meal, of: mamma.meal),
            totalCount: mammaLF.bolus + mammaLF.meal,
            totalPercent: pct(mammaLF.bolus + mammaLF.meal, of: mammaTotal),
            isBold: false,
            isSpacer: false,
            hideValues: false,
            displayAsPercentOnly: true,
            highlightAsTotal: false,
            highlightRowBackground: false
        )
        rows.append(mammaLFRow)

        let mammaCCRow = EnteredByRow(
            title: "Mamma CC",
            bolusCount: mammaCC.bolus,
            bolusPercent: pct(mammaCC.bolus, of: mamma.bolus),
            mealCount: mammaCC.meal,
            mealPercent: pct(mammaCC.meal, of: mamma.meal),
            totalCount: mammaCC.bolus + mammaCC.meal,
            totalPercent: pct(mammaCC.bolus + mammaCC.meal, of: mammaTotal),
            isBold: false,
            isSpacer: false,
            hideValues: false,
            displayAsPercentOnly: true,
            highlightAsTotal: false,
            highlightRowBackground: false
        )
        rows.append(mammaCCRow)

        // Spacer
        rows.append(
            EnteredByRow(title: "",
                         bolusCount: 0, bolusPercent: nil,
                         mealCount: 0, mealPercent: nil,
                         totalCount: 0, totalPercent: nil,
                         isBold: false,
                         isSpacer: true,
                         hideValues: true,
                         displayAsPercentOnly: false,
                         highlightAsTotal: false,
                         highlightRowBackground: false)
        )

        // Pappa
        rows.append(row("Pappa Totalt",
                        bolus: pappa.bolus,
                        meal: pappa.meal,
                        isBold: true,
                        highlightAsTotal: true))

        let pappaLFRow = EnteredByRow(
            title: "Pappa LF",
            bolusCount: pappaLF.bolus,
            bolusPercent: pct(pappaLF.bolus, of: pappa.bolus),
            mealCount: pappaLF.meal,
            mealPercent: pct(pappaLF.meal, of: pappa.meal),
            totalCount: pappaLF.bolus + pappaLF.meal,
            totalPercent: pct(pappaLF.bolus + pappaLF.meal, of: pappaTotal),
            isBold: false,
            isSpacer: false,
            hideValues: false,
            displayAsPercentOnly: true,
            highlightAsTotal: false,
            highlightRowBackground: false
        )
        rows.append(pappaLFRow)

        let pappaCCRow = EnteredByRow(
            title: "Pappa CC",
            bolusCount: pappaCC.bolus,
            bolusPercent: pct(pappaCC.bolus, of: pappa.bolus),
            mealCount: pappaCC.meal,
            mealPercent: pct(pappaCC.meal, of: pappa.meal),
            totalCount: pappaCC.bolus + pappaCC.meal,
            totalPercent: pct(pappaCC.bolus + pappaCC.meal, of: pappaTotal),
            isBold: false,
            isSpacer: false,
            hideValues: false,
            displayAsPercentOnly: true,
            highlightAsTotal: false,
            highlightRowBackground: false
        )
        rows.append(pappaCCRow)

        // Spacer
        rows.append(
            EnteredByRow(title: "",
                         bolusCount: 0, bolusPercent: nil,
                         mealCount: 0, mealPercent: nil,
                         totalCount: 0, totalPercent: nil,
                         isBold: false,
                         isSpacer: true,
                         hideValues: true,
                         displayAsPercentOnly: false,
                         highlightAsTotal: false,
                         highlightRowBackground: false)
        )

        // Resurs
        rows.append(row("Resurs Totalt",
                        bolus: resurs.bolus,
                        meal: resurs.meal,
                        isBold: true,
                        highlightAsTotal: true))

        let resursLFRow = EnteredByRow(
            title: "Resurs LF",
            bolusCount: resursLF.bolus,
            bolusPercent: pct(resursLF.bolus, of: resurs.bolus),
            mealCount: resursLF.meal,
            mealPercent: pct(resursLF.meal, of: resurs.meal),
            totalCount: resursLF.bolus + resursLF.meal,
            totalPercent: pct(resursLF.bolus + resursLF.meal, of: resursTotal),
            isBold: false,
            isSpacer: false,
            hideValues: false,
            displayAsPercentOnly: true,
            highlightAsTotal: false,
            highlightRowBackground: false
        )
        rows.append(resursLFRow)

        let resursCCRow = EnteredByRow(
            title: "Resurs CC",
            bolusCount: resursCC.bolus,
            bolusPercent: pct(resursCC.bolus, of: resurs.bolus),
            mealCount: resursCC.meal,
            mealPercent: pct(resursCC.meal, of: resurs.meal),
            totalCount: resursCC.bolus + resursCC.meal,
            totalPercent: pct(resursCC.bolus + resursCC.meal, of: resursTotal),
            isBold: false,
            isSpacer: false,
            hideValues: false,
            displayAsPercentOnly: true,
            highlightAsTotal: false,
            highlightRowBackground: false
        )
        rows.append(resursCCRow)

        self.rows = rows
        tableView.reloadData()
    }

    // MARK: - UITableViewDataSource / Delegate

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "EnteredByCell", for: indexPath) as? EnteredByCell else {
            return UITableViewCell()
        }
        let row = rows[indexPath.row]

        // Första raden = rubrikrad
        if indexPath.row == 0 {
            let headerFont = UIFont.preferredFont(forTextStyle: .footnote)
                .withTraits(traits: .traitBold)

            cell.titleLabel.text = "Inlagt av"
            cell.bolusLabel.text = "Bolus"
            cell.mealLabel.text  = "Måltid"
            cell.totalLabel.text = "Total"

            cell.titleLabel.font = headerFont
            cell.bolusLabel.font = headerFont
            cell.mealLabel.font  = headerFont
            cell.totalLabel.font = headerFont

            // Make header columns shrink font size to fit width instead of truncating
            cell.bolusLabel.adjustsFontSizeToFitWidth = true
            cell.bolusLabel.minimumScaleFactor = 0.5
            cell.mealLabel.adjustsFontSizeToFitWidth = true
            cell.mealLabel.minimumScaleFactor = 0.5
            cell.totalLabel.adjustsFontSizeToFitWidth = true
            cell.totalLabel.minimumScaleFactor = 0.5
            cell.titleLabel.adjustsFontSizeToFitWidth = true
            cell.titleLabel.minimumScaleFactor = 0.7

            let defaultColor = UIColor.label
            cell.titleLabel.textColor = defaultColor
            cell.bolusLabel.textColor = defaultColor
            cell.mealLabel.textColor  = defaultColor
            cell.totalLabel.textColor = defaultColor
            
            cell.contentView.backgroundColor = UIColor.insulin.withAlphaComponent(0.5)
            cell.backgroundColor = .clear

            return cell
        }

        // Övriga rader = data
        cell.configure(with: row, isHeader: false)
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let row = rows[indexPath.row]
        if row.isSpacer {
            return 12
        }
        return 26
    }
}
