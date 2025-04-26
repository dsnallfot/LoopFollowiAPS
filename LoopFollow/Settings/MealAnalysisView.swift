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
    let eventType: String      // "SMB", "Bolus", "Carb Correction", etc.
    let amount: Double         // insulin units or carb grams
    let foodType: String?      // non-nil for Carb Corrections with fat/protein equivalents
}

/// Glucose data point (mmol/L)
struct BGEntry {
    let date: Date
    let mmol: Double
}

class MealAnalysisView: UIViewController {

    // MARK: - BG Bar Width Constraints
    private var belowWidthConstraint: NSLayoutConstraint?
    private var inWidthConstraint: NSLayoutConstraint?
    private var aboveWidthConstraint: NSLayoutConstraint?

    // MARK: - BG Bar Properties
    // Promoted from viewDidLoad to file-private properties for access in updateBGLabels()
    private let belowBar = UILabel()
    private let inBar = UILabel()
    private let aboveBar = UILabel()
    private let inRangeRow = UIStackView()

    // All fetched events handed in by the presenting VC
    private let events: [Event]
    /// Optional initial start time provided by the caller
    private let initialStartOverride: Date?
    private let modalWithTimestamp: Bool
    private let modalTitleString: String

    init(events: [Event], initialStart: Date? = nil, modalWithTimestamp: Bool = true, modalTitleString: String = "") {
        self.events = events
        self.initialStartOverride = initialStart
        self.modalWithTimestamp = modalWithTimestamp
        self.modalTitleString = modalTitleString
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UI components & state

    // New start‑time picker
    private let startPicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .compact
        picker.translatesAutoresizingMaskIntoConstraints = false
        return picker
    }()
    
    private let endPicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .compact
        picker.translatesAutoresizingMaskIntoConstraints = false
        return picker
    }()

    private let startTimeLabel: UILabel = {
        let label = UILabel()
        label.text = "Vald starttid"
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let endTimeLabel: UILabel = {
        let label = UILabel()
        label.text = "Vald sluttid"
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let durationControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["1h", "2h", "3h", "4h", "6h", "12h", "24h", "Idag", "Ⓢ"])
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
    private var fpuTotal       = 0.0

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
    private let fpuValueLabel: UILabel = {
        let label = MealAnalysisView.makeValueLabel()
        label.text = "0 g"
        label.textColor = .secondaryLabel
        return label
    }()
    // Statistics value labels
    private let realCRValueLabel          = MealAnalysisView.makeValueLabel()
    private let manualBolusValueLabel     = MealAnalysisView.makeValueLabel()
    private let smbTempValueLabel         = MealAnalysisView.makeValueLabel()
    private let changeBGValueLabel = MealAnalysisView.makeValueLabel()
    private let inRangeValueLabel     = MealAnalysisView.makeValueLabel()
    private var inRange: Double = 0.0

    // MARK: - Glucose data
    private var bgEntries: [BGEntry] = []
    // BG chart (CombinedChartView for lines and scatter)
    private let bgChartView = CombinedChartView()

    override func viewDidLoad() {
        super.viewDidLoad()
        if modalWithTimestamp {
            //title = "Utveckling efter måltid"
            title = modalTitleString
        } else {
            title = "Utveckling fram till nu"
        }

        // When opened without a linked meal, default to the last 24 h window
        if !modalWithTimestamp {
            endTime = Date()
            startTime = Calendar.current.date(byAdding: .hour, value: -24, to: endTime)!
            durationControl.selectedSegmentIndex = 6   // "24h", keep default (index 6)
        }
        view.backgroundColor = .systemBackground

        // Configure picker limits (now‒24h ... ∞) and initial value
        endPicker.minimumDate = Date().addingTimeInterval(TimeInterval(-24 * 60 * 60 * UserDefaultsRepository.downloadDays.value))
        endPicker.maximumDate = Date()
        endPicker.date = endTime
        endPicker.addTarget(self, action: #selector(endTimeChanged(_:)), for: .valueChanged)

        startPicker.minimumDate = Date().addingTimeInterval(TimeInterval(-24 * 60 * 60 * UserDefaultsRepository.downloadDays.value))
        startPicker.maximumDate = Date()
        startPicker.date = startTime
        // Apply caller‑provided start time override only when analysing a meal
        if modalWithTimestamp, let override = initialStartOverride {
            startTime = override
            startPicker.date = override
            recalcEndTimeBasedOnDuration()
        }
        startPicker.addTarget(self, action: #selector(startTimeChanged(_:)), for: .valueChanged)

        // Configure duration control action
        durationControl.addTarget(self, action: #selector(durationChanged(_:)), for: .valueChanged)

        let startGroup = UIStackView(arrangedSubviews: [startTimeLabel, startPicker])
        startGroup.axis = .horizontal
        startGroup.alignment = .center
        startGroup.spacing = 5
        startGroup.setContentHuggingPriority(.required, for: .horizontal)

        let endGroup = UIStackView(arrangedSubviews: [endTimeLabel, endPicker])
        endGroup.axis = .horizontal
        endGroup.alignment = .center
        endGroup.spacing = 5
        endGroup.setContentHuggingPriority(.required, for: .horizontal)

        let timeRow = UIStackView(arrangedSubviews: [startGroup, endGroup])
        timeRow.axis = .vertical
        timeRow.alignment = .fill
        timeRow.spacing = 5

        let carbsRow = makeRow(
            iconName: "arrowtriangle.up.circle",
            iconColor: UIColor.systemOrange.withAlphaComponent(1.0),
            text: "Kolhydrater Totalt",
            valueLabel: carbsValueLabel,
            boldText: true
        )

        let fpuRow = makeRow(
            iconName: "arrowtriangle.up.circle",
            iconColor: UIColor.brown.withAlphaComponent(0.8),
            text: "varav Kolhydratsekvivalenter (FPU)",
            valueLabel: fpuValueLabel,
            secondary: true
        )

        let rowsStack = UIStackView(arrangedSubviews: [
            carbsRow,
            fpuRow,
            makeRow(iconName: "circle.fill",
                    iconColor: .systemBlue,
                    text: "Måltidsinsulin Netto",
                    valueLabel: insulinTotalValueLabel,
                    boldText: true),
            makeRow(iconName: "record.circle",
                    iconColor: UIColor.systemBlue.withAlphaComponent(1.0),
                    text: "varav Manuell Bolus",
                    valueLabel: bolusValueLabel,
                    secondary: true),
            makeRow(iconName: "arrowtriangle.down.circle",
                    iconColor: UIColor.systemBlue.withAlphaComponent(1.0),
                    text: "varav SMB",
                    valueLabel: smbValueLabel,
                    secondary: true),
            makeRow(iconName: "square.fill",
                    iconColor: UIColor.systemBlue.withAlphaComponent(0.45),
                    text: "varav Temp Basal",
                    valueLabel: basalValueLabel,
                    secondary: true),
            makeRow(iconName: "calendar",
                    iconColor: UIColor.systemBlue.withAlphaComponent(0.45),
                    text: "minus Profilbasal",
                    valueLabel: profileBasalValueLabel,
                    secondary: true)
        ])
        rowsStack.axis = .vertical
        rowsStack.spacing = 5
        rowsStack.setCustomSpacing(5, after: carbsRow) // extra space before fpuRow
        rowsStack.setCustomSpacing(15, after: fpuRow) // extra space before insulin rows

        // Additional stats rows
        let statsStack = UIStackView(arrangedSubviews: [
            makeStatRow(text: "✧  Verklig Insulinkvot (CR)", valueLabel: realCRValueLabel, unit: " g/E"),
            makeStatRow(text: "✧  Andel Manuell Bolus",        valueLabel: manualBolusValueLabel, unit: " %"),
            makeStatRow(text: "✧  Andel SMB & Temp Basal",     valueLabel: smbTempValueLabel,    unit: " %")
        ])
        statsStack.axis = .vertical
        statsStack.spacing = 5

        // BG rows
        // Configure inRangeRow and BG bars (now properties)
        inRangeRow.axis = .horizontal
        inRangeRow.spacing = 0
        inRangeRow.distribution = .fillProportionally
        inRangeRow.heightAnchor.constraint(equalToConstant: 30).isActive = true
        inRangeRow.layer.cornerRadius = 6
        inRangeRow.clipsToBounds = true

        // Configure belowBar
        belowBar.backgroundColor = UIColor(named: "LoopRed")
        belowBar.textColor = .white
        belowBar.font = .preferredFont(forTextStyle: .caption1).withTraits(traits: .traitBold)
        belowBar.textAlignment = .center
        belowBar.adjustsFontSizeToFitWidth = false
        belowBar.minimumScaleFactor = 0.5
        // Configure inBar
        inBar.backgroundColor = UIColor(named: "LoopGreen")
        inBar.textColor = .white
        inBar.font = .preferredFont(forTextStyle: .caption1).withTraits(traits: .traitBold)
        inBar.textAlignment = .center
        inBar.adjustsFontSizeToFitWidth = false
        inBar.minimumScaleFactor = 0.5
        // Configure aboveBar
        aboveBar.backgroundColor = .systemPurple
        aboveBar.textColor = .white
        aboveBar.font = .preferredFont(forTextStyle: .caption1).withTraits(traits: .traitBold)
        aboveBar.textAlignment = .center
        aboveBar.adjustsFontSizeToFitWidth = false
        aboveBar.minimumScaleFactor = 0.5
        // Add bars directly to inRangeRow
        inRangeRow.addArrangedSubview(belowBar)
        inRangeRow.addArrangedSubview(inBar)
        inRangeRow.addArrangedSubview(aboveBar)
        // Initial width constraints for bars (equal split, sum to 1.0)
        belowWidthConstraint = belowBar.widthAnchor.constraint(equalTo: inRangeRow.widthAnchor, multiplier: 0.33)
        inWidthConstraint    = inBar.widthAnchor   .constraint(equalTo: inRangeRow.widthAnchor, multiplier: 0.34)
        aboveWidthConstraint = aboveBar.widthAnchor.constraint(equalTo: inRangeRow.widthAnchor, multiplier: 0.33)
        [belowWidthConstraint, inWidthConstraint, aboveWidthConstraint].forEach { $0?.isActive = true }
        // Minimum width constraints (once)
        belowBar.widthAnchor.constraint(greaterThanOrEqualToConstant: 1).isActive = true
        inBar   .widthAnchor.constraint(greaterThanOrEqualToConstant: 1).isActive = true
        aboveBar.widthAnchor.constraint(greaterThanOrEqualToConstant: 1).isActive = true
        let bgStack = UIStackView(arrangedSubviews: [
            makeStatRow(text: "✧  Glukosförändring", valueLabel: changeBGValueLabel, unit: " mmol/L"),
            inRangeRow
        ])
        bgStack.axis = .vertical
        bgStack.spacing = 15

        let mainStack = UIStackView(arrangedSubviews: [
            timeRow,
            durationControl,
            rowsStack,
            bgChartView,
            statsStack,
            bgStack
        ])
        mainStack.axis = .vertical
        mainStack.spacing = 5
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        // chart config & height
        setupBGChart()
        bgChartView.translatesAutoresizingMaskIntoConstraints = false
        bgChartView.heightAnchor.constraint(equalToConstant: 190).isActive = true

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8), // reduced padding
            mainStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
        mainStack.setCustomSpacing(20, after: durationControl)   // extra gap before totals
        mainStack.setCustomSpacing(10, after: rowsStack)   // clear separation
        mainStack.setCustomSpacing(15, after: bgChartView)   // extra gap before stats
        mainStack.setCustomSpacing(5, after: statsStack)   // smaller gap after stats

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
        if modalWithTimestamp {
            recalcEndTimeBasedOnDuration()
        } else {
            updateTotals()
            updateBGLabels()
        }
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
        if modalWithTimestamp {
            updateTotals()
            updateBGLabels()
        } else {
            recalcEndTimeBasedOnDuration()
        }
    }

    private func recalcEndTimeBasedOnDuration() {
        guard let title = durationControl.titleForSegment(at: durationControl.selectedSegmentIndex) else { return }
        if title == "Idag" {
            let calendar = Calendar.current
            let now = Date()
            endTime = now
            startTime = calendar.startOfDay(for: now)
            startPicker.date = startTime
            endPicker.date = endTime
        } else if title == "Ⓢ" {
            let calendar = Calendar.current
            let now = Date()
            let components = calendar.dateComponents([.year, .month, .day], from: now)
            startTime = calendar.date(from: DateComponents(year: components.year, month: components.month, day: components.day, hour: 8, minute: 0)) ?? now
            endTime = calendar.date(from: DateComponents(year: components.year, month: components.month, day: components.day, hour: 16, minute: 30)) ?? now
            startPicker.date = startTime
            endPicker.date = endTime
        } else {
            let hoursString = title.replacingOccurrences(of: "h", with: "")
            let hours = Int(hoursString) ?? 1
            if modalWithTimestamp {
                // startTime → endTime
                endTime = Calendar.current.date(byAdding: .hour, value: hours, to: startTime) ?? startTime
                endPicker.date = endTime
                let now = Date()
                if endTime > now {
                    endTime = now
                    endPicker.date = now
                }
            } else {
                // endTime is fixed → derive startTime
                startTime = Calendar.current.date(byAdding: .hour, value: -hours, to: endTime) ?? endTime
                startPicker.date = startTime
            }
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
        insulinTotal = 0; bolusTotal = 0; smbTotal = 0; basalTotal = 0; carbsTotal = 0; fpuTotal = 0; profileBasalTotal = 0
        for event in events where event.date >= startTime && event.date <= endTime {
            switch event.eventType {
            case "SMB":
                smbTotal   += event.amount
            case "Bolus":
                bolusTotal += event.amount
            case "Carb Correction":
                carbsTotal += event.amount
                if (event.foodType ?? "").isEmpty {
                        fpuTotal += event.amount
                    }
            case "Temp Basal":
                basalTotal += event.amount
            default: break
            }
        }
        // scheduled basal for the timeframe
        // Round scheduled basal down to nearest 0.05
        let rawBasal = scheduledBasal(from: startTime, to: endTime)
        profileBasalTotal = floor(rawBasal / 0.05) * 0.05
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
        fpuValueLabel.text          = String(format: "%.0f g", fpuTotal)
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
        bgChartView.highlightPerTapEnabled = false
        bgChartView.scaleXEnabled = false
        bgChartView.scaleYEnabled = false
        bgChartView.drawOrder = [CombinedChartView.DrawOrder.scatter.rawValue,
                                 CombinedChartView.DrawOrder.line.rawValue]

        // Y axis 0‑24 mmol
        let y = bgChartView.leftAxis
        y.axisMinimum = 0
        y.axisMaximum = 24
        y.spaceTop = 0.02   // small headroom so dots at 23 are visible
        y.labelCount = 6
        y.gridColor = NSUIColor.lightGray.withAlphaComponent(0.4)
        y.gridLineWidth = 0.5
        y.gridLineDashLengths = [2,2]

        // threshold lines with bespoke colors using user-defined values
        let lowMmol = Double(UserDefaultsRepository.lowLine.value) / 18.0182
        let highMmol = Double(UserDefaultsRepository.highLine.value) / 18.0182

        let thresholds: [(limit: Double, color: UIColor)] = [
            (lowMmol, UIColor.red.withAlphaComponent(0.7)),
            (highMmol, UIColor.purple.withAlphaComponent(1.0))
        ]

        for (limit, color) in thresholds {
            let ll = ChartLimitLine(limit: limit)
            ll.lineColor   = color
            ll.lineWidth   = 1.5
            //ll.lineDashLengths = [4, 2]    // optional: dashed look
            //ll.label       = String(format: "%.1f", limit)
            ll.valueTextColor = color     // so the label matches
            y.addLimitLine(ll)
        }

        // Draw limit lines behind the data so the BG line stays on top
        y.drawLimitLinesBehindDataEnabled = true

        // X axis
        let x = bgChartView.xAxis
        x.labelPosition = .bottom
        x.gridColor = NSUIColor.lightGray.withAlphaComponent(0.4)
        x.gridLineWidth = 0.5
        x.gridLineDashLengths = [2,2]
        x.valueFormatter = self
        // Avoid clipping of last X‑label and give the line some breathing room
        x.avoidFirstLastClippingEnabled = false
        bgChartView.extraRightOffset = 16
    }
    
    /// Same hue interpolation as in graphs.swift, but thresholds are converted once into mmol/L
    private func setBGColorForMmol(_ mmolValue: Double) -> NSUIColor {
        // 1) Grab your mg/dL thresholds
        let minMgdl    = Double(UserDefaultsRepository.alertUrgentLowBG.value)
        let targetMgdl = Double(UserDefaultsRepository.targetLine.value)
        let maxMgdl    = Double(UserDefaultsRepository.alertUrgentHighBG.value)

        // 2) Convert once to mmol/L
        let factor = 18.0182
        let minMmol    = minMgdl    / factor
        let targetMmol = targetMgdl / factor
        let maxMmol    = maxMgdl    / factor

        // 3) Hues
        let redHue    : CGFloat = 0.0   / 360.0
        let greenHue  : CGFloat = 120.0 / 360.0
        let purpleHue : CGFloat = 270.0 / 360.0

        // 4) Interpolate
        let hue: CGFloat
        if mmolValue <= minMmol {
            hue = redHue
        } else if mmolValue >= maxMmol {
            hue = purpleHue
        } else if mmolValue <= targetMmol {
            let ratio = CGFloat((mmolValue - minMmol) / (targetMmol - minMmol))
            hue = redHue + ratio * (greenHue - redHue)
        } else {
            let ratio = CGFloat((mmolValue - targetMmol) / (maxMmol - targetMmol))
            hue = greenHue + ratio * (purpleHue - greenHue)
        }

        return UIColor(hue: hue, saturation: 0.9, brightness: 0.9, alpha: 1.0)
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
        bgDataSet.colors = entries.map { entry in
            setBGColorForMmol(entry.y)
        }
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
        smbDots.scatterShapeSize = 9
        smbDots.drawValuesEnabled = false

        // ▸ Triangles for Carb Correction: orange for “real” carbs, brown for fat/protein equivalents
        let carbCorrections = events.filter {
            $0.eventType == "Carb Correction" &&
            $0.date >= startTime && $0.date <= endTime
        }

        // Orange for those with a non-empty foodType
        let orangeEntries = carbCorrections
            .filter { ($0.foodType ?? "").isEmpty == false }
            .map { ChartDataEntry(x: $0.date.timeIntervalSince(startTime)/3600.0,
                                  y: 2.0) }
        let orangeDots = ScatterChartDataSet(entries: orangeEntries, label: "")
        orangeDots.setColor(.systemOrange.withAlphaComponent(1.0))
        orangeDots.setScatterShape(.triangle)
        orangeDots.scatterShapeSize = 9
        orangeDots.drawValuesEnabled = false

        // Brown for fat/protein equivalents (empty foodType)
        let brownEntries = carbCorrections
            .filter { ($0.foodType ?? "").isEmpty }
            .map { ChartDataEntry(x: $0.date.timeIntervalSince(startTime)/3600.0,
                                  y: 2.0) }
        let brownDots = ScatterChartDataSet(entries: brownEntries, label: "")
        brownDots.setColor(.brown.withAlphaComponent(0.8))
        brownDots.setScatterShape(.triangle)
        brownDots.scatterShapeSize = 7
        brownDots.drawValuesEnabled = false

        // Combine
        let combined = CombinedChartData()
        combined.lineData   = LineChartData(dataSet: bgDataSet)
        combined.scatterData = ScatterChartData(dataSets: [bolusDots, smbDots, orangeDots, brownDots])
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
        textLabel.textColor = .secondaryLabel
        valueLabel.textColor = .secondaryLabel
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
        // format as "X.X → Y.Y mmol/L"
        let startText = startBG != nil
        ? String(format: "%.1f", startBG!)
        : "--"
        let endText = endBG != nil
        ? String(format: "%.1f", endBG!)
        : "--"
        changeBGValueLabel.text = "\(startText) → \(endText) mmol/L"
        // ——— NEW: compute percentages below, within, and above target ———
        let windowEntries = bgEntries.filter { $0.date >= startTime && $0.date <= endTime }
        let totalCount    = windowEntries.count
        
        let lowMmol = Double(UserDefaultsRepository.lowLine.value) / 18.0182
        let highMmol = Double(UserDefaultsRepository.highLine.value) / 18.0182
        let belowCount = windowEntries.filter { $0.mmol <  lowMmol }.count
        let inCount    = windowEntries.filter { $0.mmol >= lowMmol && $0.mmol <= highMmol }.count
        let aboveCount = windowEntries.filter { $0.mmol >  highMmol }.count
        
        let belowRange = totalCount > 0
        ? Double(belowCount) / Double(totalCount) * 100
        : 0
        let inRange = totalCount > 0
        ? Double(inCount)    / Double(totalCount) * 100
            : 0
        let aboveRange = totalCount > 0
            ? Double(aboveCount) / Double(totalCount) * 100
            : 0

        // Dynamic update of the horizontal bar labels (belowBar, inBar, aboveBar)
        // Show nothing for <1%, show number only for 2–6%, show with % for ≥6%
        if belowRange < 1 {
            belowBar.text = ""
        } else if belowRange < 6 {
            belowBar.text = String(format: "%.0f", belowRange)
        } else {
            belowBar.text = String(format: "%.0f%%", belowRange)
        }
        belowBar.isHidden = false

        if inRange < 1 {
            inBar.text = ""
        } else if inRange < 6 {
            inBar.text = String(format: "%.0f", inRange)
        } else {
            inBar.text = String(format: "%.0f%%", inRange)
        }
        inBar.isHidden = false

        if aboveRange < 1 {
            aboveBar.text = ""
        } else if aboveRange < 6 {
            aboveBar.text = String(format: "%.0f", aboveRange)
        } else {
            aboveBar.text = String(format: "%.0f%%", aboveRange)
        }
        aboveBar.isHidden = false
        // Deactivate old width constraints
        belowWidthConstraint?.isActive = false
        inWidthConstraint?.isActive = false
        aboveWidthConstraint?.isActive = false
        // Create new width constraints with updated multipliers and activate
        belowWidthConstraint = belowBar.widthAnchor.constraint(equalTo: inRangeRow.widthAnchor, multiplier: CGFloat(belowRange / 100))
        inWidthConstraint    = inBar.widthAnchor   .constraint(equalTo: inRangeRow.widthAnchor, multiplier: CGFloat(inRange / 100))
        aboveWidthConstraint = aboveBar.widthAnchor.constraint(equalTo: inRangeRow.widthAnchor, multiplier: CGFloat(aboveRange / 100))
        [belowWidthConstraint, inWidthConstraint, aboveWidthConstraint].forEach { $0?.isActive = true }

        // Redraw chart
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
