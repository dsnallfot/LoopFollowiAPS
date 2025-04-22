//
//  MealAnalysisView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-04-22.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import HealthKit
import UIKit
import Charts

/// Minimal representation of a treatment event we need
struct Event {
    let date: Date
    let eventType: String   // "SMB", "Bolus", "Carb Correction", etc.
    let amount: Double      // insulin units or carb grams
}

/// Glucose data point (mmol/L)
struct BGEntry {
    let date: Date
    let mmol: Double
}

class MealAnalysisView: UIViewController {

    // All fetched events handed in by the presenting VC
    private let events: [Event]
    /// Optional initial start time provided by the caller
    private let initialStartOverride: Date?

    init(events: [Event], initialStart: Date? = nil) {
        self.events = events
        self.initialStartOverride = initialStart
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UI components & state

    private let datePicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .compact
        picker.translatesAutoresizingMaskIntoConstraints = false
        return picker
    }()

    // New start‑time picker
    private let startPicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .compact
        picker.translatesAutoresizingMaskIntoConstraints = false
        return picker
    }()

    private let startDateLabel: UILabel = {
        let label = UILabel()
        label.text = "Välj starttid"
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let startTimeLabel: UILabel = {
        let label = UILabel()
        label.text = "Välj sluttid"
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let durationControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["1h", "2h", "3h", "4h", "6h", "12h", "24h"])
        control.selectedSegmentIndex = 2   // 3 h default
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private var endTime: Date = Date()
    private var startTime: Date = Calendar.current.date(byAdding: .hour, value: -3, to: Date())!

    // MARK: - Insulin values
    private var insulinTotal     = 0.0      // delivered insulin (SMB+Bolus+TempBasal)
    private var bolusTotal       = 0.0
    private var smbTotal         = 0.0
    private var basalTotal       = 0.0      // delivered temp basal
    private var profileBasalTotal = 0.0     // scheduled basal to subtract
    private var carbsTotal       = 0.0

    // Value labels (placeholders for now)
    private let insulinTotalValueLabel = MealAnalysisView.makeValueLabel(bold: true)
    private let bolusValueLabel        = MealAnalysisView.makeValueLabel()
    private let smbValueLabel          = MealAnalysisView.makeValueLabel()
    private let basalValueLabel        = MealAnalysisView.makeValueLabel()
    private let profileBasalValueLabel = MealAnalysisView.makeValueLabel()
    private let carbsValueLabel: UILabel = {
        let label = MealAnalysisView.makeValueLabel(bold: true)
        label.text = "0 g"
        return label
    }()
    // Statistics value labels
    private let realCRValueLabel          = MealAnalysisView.makeValueLabel()
    private let manualBolusValueLabel     = MealAnalysisView.makeValueLabel()
    private let smbTempValueLabel         = MealAnalysisView.makeValueLabel()
    private let startBGValueLabel       = MealAnalysisView.makeValueLabel()
    private let endBGValueLabel         = MealAnalysisView.makeValueLabel()

    // MARK: - Glucose data
    private var bgEntries: [BGEntry] = []
    // BG chart (CombinedChartView for lines and scatter)
    private let bgChartView = CombinedChartView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Måltidsanalys"
        view.backgroundColor = .systemBackground

        // Configure picker limits (now‒24h ... ∞) and initial value
        datePicker.minimumDate = Date().addingTimeInterval(-24 * 60 * 60)
        datePicker.maximumDate = nil            // allow future times
        datePicker.date = endTime
        datePicker.addTarget(self, action: #selector(endTimeChanged(_:)), for: .valueChanged)

        startPicker.minimumDate = Date().addingTimeInterval(-24 * 60 * 60)
        startPicker.maximumDate = Date()
        startPicker.date = startTime
        // Apply caller‑provided start time override, if any
        if let override = initialStartOverride {
            startTime = override
            startPicker.date = override
            recalcEndTimeBasedOnDuration()
        }
        startPicker.addTarget(self, action: #selector(startTimeChanged(_:)), for: .valueChanged)

        // Configure duration control action
        durationControl.addTarget(self, action: #selector(durationChanged(_:)), for: .valueChanged)

        // Lay out components
        let startRow = UIStackView(arrangedSubviews: [startDateLabel, startPicker])
        startRow.axis = .horizontal
        startRow.alignment = .center
        startRow.spacing = 12

        let endRow = UIStackView(arrangedSubviews: [startTimeLabel, datePicker])
        endRow.axis = .horizontal
        endRow.alignment = .center
        endRow.spacing = 12

        let carbsRow = makeRow(iconName: "circle.fill",
                               iconColor: UIColor.systemOrange.withAlphaComponent(0.8),
                               text: "Kolhydrater Totalt",
                               valueLabel: carbsValueLabel,
                               boldText: true)

        let rowsStack = UIStackView(arrangedSubviews: [
            carbsRow,
            makeRow(iconName: "circle.fill",
                    iconColor: .systemBlue,
                    text: "Måltidsinsulin Totalt",
                    valueLabel: insulinTotalValueLabel,
                    boldText: true),
            makeRow(iconName: "circle.fill",
                    iconColor: UIColor.systemBlue.withAlphaComponent(0.8),
                    text: "varav Bolus",
                    valueLabel: bolusValueLabel,
                    secondary: true),
            makeRow(iconName: "bolt.circle.fill",
                    iconColor: UIColor.systemBlue.withAlphaComponent(0.8),
                    text: "varav SMB",
                    valueLabel: smbValueLabel,
                    secondary: true),
            makeRow(iconName: "circle.fill",
                    iconColor: UIColor.systemBlue.withAlphaComponent(0.2),
                    text: "varav Temp Basal",
                    valueLabel: basalValueLabel,
                    secondary: true),
            makeRow(iconName: "calendar",
                    iconColor: UIColor.systemBlue.withAlphaComponent(0.2),
                    text: "minus Profilbasal",
                    valueLabel: profileBasalValueLabel,
                    secondary: true)
        ])
        rowsStack.axis = .vertical
        rowsStack.spacing = 5
        rowsStack.setCustomSpacing(12, after: carbsRow) // extra space before insulin rows

        // Additional stats rows
        let statsStack = UIStackView(arrangedSubviews: [
            makeStatRow(text: " •  Verklig Insulinkvot (CR)", valueLabel: realCRValueLabel, unit: " g/E"),
            makeStatRow(text: " •  Andel Manuell Bolus",        valueLabel: manualBolusValueLabel, unit: "%"),
            makeStatRow(text: " •  Andel SMB & Temp Basal",     valueLabel: smbTempValueLabel,    unit: "%")
        ])
        statsStack.axis = .vertical
        statsStack.spacing = 4

        // BG rows
        let bgStack = UIStackView(arrangedSubviews: [
            makeStatRow(text: " •  Startglukos", valueLabel: startBGValueLabel, unit: " mmol/L"),
            makeStatRow(text: " •  Slutglukos",  valueLabel: endBGValueLabel,   unit: " mmol/L")
        ])
        bgStack.axis = .vertical
        bgStack.spacing = 4

        let mainStack = UIStackView(arrangedSubviews: [startRow, endRow, durationControl,
                                                       rowsStack, statsStack, bgStack, bgChartView])
        mainStack.axis = .vertical
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        // chart config & height
        setupBGChart()
        bgChartView.translatesAutoresizingMaskIntoConstraints = false
        bgChartView.heightAnchor.constraint(equalToConstant: 150).isActive = true
        mainStack.setCustomSpacing(12, after: bgStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
        mainStack.setCustomSpacing(20, after: durationControl)   // extra gap before totals
        mainStack.setCustomSpacing(20, after: rowsStack)   // clear separation
        mainStack.setCustomSpacing(20, after: statsStack)   // space before BG rows

        recalcEndTimeBasedOnDuration()
        updateTotals()
        fetchBG24h()

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .done,
            target: self,
            action: #selector(dismissSelf)
        )
    }

    @objc private func dismissSelf() {
        dismiss(animated: true, completion: nil)
    }

    // MARK: - Actions

    // MARK: - Time calculations

    @objc private func startTimeChanged(_ sender: UIDatePicker) {
        startTime = sender.date
        recalcEndTimeBasedOnDuration()
        updateTotals()
        updateBGLabels()
    }

    @objc private func durationChanged(_ sender: UISegmentedControl) {
        recalcEndTimeBasedOnDuration()
        updateTotals()
        updateBGLabels()
    }

    @objc private func endTimeChanged(_ sender: UIDatePicker) {
        var selected = sender.date
        let now = Date()
        if selected > now {
            selected = now
            sender.date = now
        }
        endTime = selected
        updateTotals()
        updateBGLabels()
    }

    private func recalcEndTimeBasedOnDuration() {
        guard let title = durationControl.titleForSegment(at: durationControl.selectedSegmentIndex) else { return }
        let hoursString = title.replacingOccurrences(of: "h", with: "")
        let hours = Int(hoursString) ?? 1
        endTime = Calendar.current.date(byAdding: .hour, value: hours, to: startTime) ?? startTime
        datePicker.date = endTime
        // Ensure endTime never exceeds "now"
        let now = Date()
        if endTime > now {
            endTime = now
            datePicker.date = now
        }
        updateTotals()
        updateBGLabels()
    }

    /// Integrate scheduled profile basal (units) between two dates
    private func scheduledBasal(from start: Date, to end: Date) -> Double {
        let schedule = ProfileManager.shared.basalSchedule  // array of .timeAsSeconds + value
        guard !schedule.isEmpty else { return 0 }
        let calendar = Calendar.current
        var total = 0.0
        var current = start

        func basalRate(at date: Date) -> Double {
            let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
            let secondsOfDay = comps.hour! * 3600 + comps.minute! * 60 + comps.second!
            // find last entry whose timeAsSeconds <= secondsOfDay
            var rate = schedule.last!.value
            for entry in schedule {
                if entry.timeAsSeconds <= secondsOfDay {
                    rate = entry.value
                } else {
                    break
                }
            }
            return rate
        }

        func nextChange(after date: Date) -> Date {
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            let base = calendar.date(from: comps)!
            let secondsOfDay = calendar.dateComponents([.hour, .minute, .second], from: date)
            let currentSec = secondsOfDay.hour! * 3600 + secondsOfDay.minute! * 60 + secondsOfDay.second!
            // find next entry whose timeAsSeconds > currentSec
            for entry in schedule {
                if entry.timeAsSeconds > currentSec {
                    return base.addingTimeInterval(TimeInterval(entry.timeAsSeconds))
                }
            }
            // next change is first entry of next day
            return base.addingTimeInterval(24*3600 + TimeInterval(schedule[0].timeAsSeconds))
        }

        while current < end {
            let rate = basalRate(at: current)
            let next = min(end, nextChange(after: current))
            let hours = next.timeIntervalSince(current) / 3600.0
            total += rate * hours
            current = next
        }
        return max(total, 0)
    }

    // MARK: - Summation
    private func updateTotals() {
        insulinTotal = 0; bolusTotal = 0; smbTotal = 0; basalTotal = 0; carbsTotal = 0; profileBasalTotal = 0
        for event in events where event.date >= startTime && event.date <= endTime {
            switch event.eventType {
            case "SMB":
                smbTotal   += event.amount
            case "Bolus":
                bolusTotal += event.amount
            case "Carb Correction":
                carbsTotal += event.amount
            case "Temp Basal":
                basalTotal += event.amount
            default: break
            }
        }
        // scheduled basal for the timeframe
        profileBasalTotal = scheduledBasal(from: startTime, to: endTime)
        // Net insulin for meal = delivered insulin - scheduled profile basal
        let netInsulin = (smbTotal + bolusTotal + basalTotal) - profileBasalTotal
        // Derived statistics
        let realCR = netInsulin > 0 ? carbsTotal / netInsulin : 0
        let manualBolusPct = netInsulin > 0 ? (bolusTotal / netInsulin) * 100 : 0
        let smbTempDelivered = smbTotal + basalTotal - profileBasalTotal
        let smbTempPct = netInsulin > 0 ? (smbTempDelivered / netInsulin) * 100 : 0
        // update UI
        insulinTotalValueLabel.text = String(format: "%.2f E", netInsulin)
        bolusValueLabel.text        = String(format: "%.2f E", bolusTotal)
        smbValueLabel.text          = String(format: "%.2f E", smbTotal)
        basalValueLabel.text        = String(format: "%.2f E", basalTotal)
        profileBasalValueLabel.text = String(format: "-%.2f E", profileBasalTotal)
        carbsValueLabel.text        = String(format: "%.0f g",  carbsTotal)
        realCRValueLabel.text       = String(format: "%.0f g/E", realCR)
        manualBolusValueLabel.text  = String(format: "%.0f %%", manualBolusPct)
        smbTempValueLabel.text      = String(format: "%.0f %%", smbTempPct)
        updateBGLabels()
    }

    private static func makeValueLabel(bold: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = "0.00 E"
        label.font = bold
            ? .preferredFont(forTextStyle: .body).withTraits(traits: .traitBold)
            : .preferredFont(forTextStyle: .body)
        return label
    }

    private func makeRow(iconName: String,
                         iconColor: UIColor,
                         text: String,
                         valueLabel: UILabel,
                         boldText: Bool = false,
                         secondary: Bool = false) -> UIStackView {
        let icon = UIImageView(image: UIImage(systemName: iconName))
        icon.tintColor = iconColor
        let textLabel = UILabel()
        textLabel.font = boldText
            ? .preferredFont(forTextStyle: .body).withTraits(traits: .traitBold)
            : .preferredFont(forTextStyle: .body)
        textLabel.text = text
        let spacer = UIView()
        let row = UIStackView(arrangedSubviews: [icon, textLabel, spacer, valueLabel])
        row.axis = .horizontal
        row.spacing = 5
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        if secondary {
            textLabel.textColor = .secondaryLabel
            valueLabel.textColor = .secondaryLabel
        }
        return row
    }
    // MARK: - BG chart helpers
    private func setupBGChart() {
        bgChartView.chartDescription.enabled = false
        bgChartView.legend.enabled = false
        bgChartView.rightAxis.enabled = false
        bgChartView.pinchZoomEnabled = false
        bgChartView.doubleTapToZoomEnabled = false
        bgChartView.dragEnabled = false
        bgChartView.scaleXEnabled = false
        bgChartView.scaleYEnabled = false
        bgChartView.drawOrder = [CombinedChartView.DrawOrder.scatter.rawValue,
                                 CombinedChartView.DrawOrder.line.rawValue]

        // Y axis 0‑24 mmol
        let y = bgChartView.leftAxis
        y.axisMinimum = 0
        y.axisMaximum = 24
        y.spaceTop = 0.02   // small headroom so dots at 22 are visible
        y.labelCount = 6
        y.gridColor = NSUIColor.lightGray.withAlphaComponent(0.4)
        y.gridLineWidth = 0.5
        y.gridLineDashLengths = [2,2]

        // threshold lines
        [3.9, 7.9].forEach {
            let ll = ChartLimitLine(limit: $0)
            ll.lineColor = .label.withAlphaComponent(0.6)
            ll.lineWidth = 2
            y.addLimitLine(ll)
        }

        // Draw limit lines behind the data so the red BG line stays on top
        y.drawLimitLinesBehindDataEnabled = true

        // X axis
        let x = bgChartView.xAxis
        x.labelPosition = .bottom
        x.gridColor = NSUIColor.lightGray.withAlphaComponent(0.4)
        x.gridLineWidth = 0.5
        x.gridLineDashLengths = [2,2]
        x.valueFormatter = self
        // Avoid clipping of last X‑label and give the line some breathing room
        x.avoidFirstLastClippingEnabled = true
        bgChartView.extraRightOffset = 12
    }

    private func refreshBGChart() {
        let pts = bgEntries
            .filter { $0.date >= startTime && $0.date <= endTime }
            .sorted { $0.date < $1.date }
        let entries = pts.map {
            ChartDataEntry(x: $0.date.timeIntervalSince(startTime)/3600.0,
                           y: $0.mmol)
        }
        // Main BG line dataset
        let bgDataSet = LineChartDataSet(entries: entries, label: "")
        bgDataSet.setColor(NSUIColor.systemRed)
        bgDataSet.lineWidth = 3
        bgDataSet.drawCirclesEnabled = false
        bgDataSet.drawValuesEnabled = false
        bgDataSet.mode = .linear

        // ▸ Blue dots for Bolus at y = 22 mmol
        let bolusEntries = events.filter { ["Bolus"].contains($0.eventType) &&
                                          $0.date >= startTime && $0.date <= endTime }
                                .map { ChartDataEntry(x: $0.date.timeIntervalSince(startTime)/3600.0,
                                                      y: 22.0) }
        let bolusDots = ScatterChartDataSet(entries: bolusEntries, label: "")
        bolusDots.setColor(NSUIColor.systemBlue)
        bolusDots.setScatterShape(.circle)
        bolusDots.scatterShapeSize = 8
        bolusDots.drawValuesEnabled = false
        
        // ▸ Blue triangles for SMB at y = 22 mmol
        let smbEntries = events.filter { ["SMB"].contains($0.eventType) &&
                                          $0.date >= startTime && $0.date <= endTime }
                                .map { ChartDataEntry(x: $0.date.timeIntervalSince(startTime)/3600.0,
                                                      y: 22.0) }
        let smbDots = ScatterChartDataSet(entries: smbEntries, label: "")
        smbDots.setColor(NSUIColor.systemBlue)
        smbDots.setScatterShape(.triangleFlipped)
        smbDots.scatterShapeSize = 8
        smbDots.drawValuesEnabled = false

        // ▸ Orange triangles for Carb Correction at y = 2 mmol
        let carbEntries = events.filter { $0.eventType == "Carb Correction" &&
                                          $0.date >= startTime && $0.date <= endTime }
                                .map { ChartDataEntry(x: $0.date.timeIntervalSince(startTime)/3600.0,
                                                      y: 2.0) }
        let carbDots = ScatterChartDataSet(entries: carbEntries, label: "")
        carbDots.setColor(NSUIColor.systemOrange)
        carbDots.setScatterShape(.triangle)
        carbDots.scatterShapeSize = 8
        carbDots.drawValuesEnabled = false

        // Combine
        let combined = CombinedChartData()
        combined.lineData   = LineChartData(dataSet: bgDataSet)
        combined.scatterData = ScatterChartData(dataSets: [bolusDots, smbDots, carbDots])
        bgChartView.data = combined

        // X range & labels
        let hrs = max(endTime.timeIntervalSince(startTime)/3600.0, 0.1)
        let x = bgChartView.xAxis
        x.axisMinimum = 0
        x.axisMaximum = hrs
        if hrs <= 6 {
            x.granularity = 1
            x.labelCount = Int(hrs.rounded(.up)) + 1
        } else {
            x.granularity = 3
            x.labelCount = Int((hrs/3).rounded(.up)) + 1
        }
        bgChartView.notifyDataSetChanged()
    }

    private func makeStatRow(text: String,
                             valueLabel: UILabel,
                             unit: String) -> UIStackView {
        let textLabel = UILabel()
        textLabel.text = text
        let spacer = UIView()
        // Append unit to value label later; start blank
        valueLabel.text = "--\(unit)"
        let row = UIStackView(arrangedSubviews: [textLabel, spacer, valueLabel])
        row.axis = .horizontal
        row.spacing = 5
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textLabel.textColor = .label
        valueLabel.textColor = .label
        return row
    }

    // MARK: - BG Handling
    private func fetchBG24h() {
        BGProvider.fetch { [weak self] sgv in
            guard let self = self else { return }
            // convert mg/dL → mmol/L (18.0182) and store
            self.bgEntries = sgv.map {
                BGEntry(date: Date(timeIntervalSince1970: $0.date),
                        mmol: Double($0.sgv) / 18.0182)
            }
            self.updateBGLabels()
            self.refreshBGChart()
        }
    }

    private func nearestBG(to date: Date) -> Double? {
        return bgEntries.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?.mmol
    }

    private func updateBGLabels() {
        let startBG = nearestBG(to: startTime)
        let endBG   = nearestBG(to: endTime)
        startBGValueLabel.text = startBG != nil ? String(format: "%.1f mmol/L", startBG!) : "-- mmol/L"
        endBGValueLabel.text   = endBG   != nil ? String(format: "%.1f mmol/L", endBG!)   : "-- mmol/L"
        refreshBGChart()
    }
}

extension MealAnalysisView: AxisValueFormatter {
    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let date = startTime.addingTimeInterval(value * 3600)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

private extension UIFont {
    func withTraits(traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
