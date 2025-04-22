//
//  MealAnalysisView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-04-22.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//


import UIKit

/// Minimal representation of a treatment event we need
struct Event {
    let date: Date
    let eventType: String   // "SMB", "Bolus", "Carb Correction", etc.
    let amount: Double      // insulin units or carb grams
}

class MealAnalysisView: UIViewController {

    // All fetched events handed in by the presenting VC
    private let events: [Event]

    init(events: [Event]) {
        self.events = events
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
        label.text = "Välj starttid:"
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let startTimeLabel: UILabel = {
        let label = UILabel()
        label.text = "Välj sluttid:"
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let durationControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["1h", "2h", "3h", "4h", "5h", "6h", "24h"])
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
                    text: "Insulin Totalt",
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
            makeStatRow(text: " • Verklig Insulinkvot (CR)", valueLabel: realCRValueLabel, unit: " g/E"),
            makeStatRow(text: " • Andel Manuell Bolus",        valueLabel: manualBolusValueLabel, unit: "%"),
            makeStatRow(text: " • Andel SMB & Temp Basal",     valueLabel: smbTempValueLabel,    unit: "%")
        ])
        statsStack.axis = .vertical
        statsStack.spacing = 4

        let mainStack = UIStackView(arrangedSubviews: [startRow, endRow, durationControl, rowsStack, statsStack])
        mainStack.axis = .vertical
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
        mainStack.setCustomSpacing(20, after: durationControl)   // extra gap before totals
        mainStack.setCustomSpacing(20, after: rowsStack)   // clear separation

        recalcEndTimeBasedOnDuration()
        updateTotals()

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
    }

    @objc private func durationChanged(_ sender: UISegmentedControl) {
        recalcEndTimeBasedOnDuration()
        updateTotals()
    }

    @objc private func endTimeChanged(_ sender: UIDatePicker) {
        endTime = sender.date
        updateTotals()
    }

    private func recalcEndTimeBasedOnDuration() {
        guard let title = durationControl.titleForSegment(at: durationControl.selectedSegmentIndex) else { return }
        let hoursString = title.replacingOccurrences(of: "h", with: "")
        let hours = Int(hoursString) ?? 1
        endTime = Calendar.current.date(byAdding: .hour, value: hours, to: startTime) ?? startTime
        datePicker.date = endTime
        updateTotals()
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
        row.spacing = 6
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        if secondary {
            textLabel.textColor = .secondaryLabel
            valueLabel.textColor = .secondaryLabel
        }
        return row
    }
}

private extension UIFont {
    func withTraits(traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
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
        row.spacing = 6
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textLabel.textColor = .secondaryLabel
        valueLabel.textColor = .secondaryLabel
        return row
    }
