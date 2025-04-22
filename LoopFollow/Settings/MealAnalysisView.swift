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
    private var insulinTotal = 0.0
    private var bolusTotal   = 0.0
    private var smbTotal     = 0.0
    private var basalTotal   = 0.0
    private var carbsTotal   = 0.0

    // Value labels (placeholders for now)
    private let insulinTotalValueLabel = MealAnalysisView.makeValueLabel(bold: true)
    private let bolusValueLabel        = MealAnalysisView.makeValueLabel()
    private let smbValueLabel          = MealAnalysisView.makeValueLabel()
    private let basalValueLabel        = MealAnalysisView.makeValueLabel()
    private let carbsValueLabel: UILabel = {
        let label = MealAnalysisView.makeValueLabel(bold: true)
        label.text = "0 g"
        return label
    }()

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
                    text: "Varav Bolus",
                    valueLabel: bolusValueLabel),
            makeRow(iconName: "bolt.circle.fill",
                    iconColor: UIColor.systemBlue.withAlphaComponent(0.8),
                    text: "Varav SMB",
                    valueLabel: smbValueLabel),
            makeRow(iconName: "circle.fill",
                    iconColor: UIColor.systemBlue.withAlphaComponent(0.2),
                    text: "Varav Temp Basal",
                    valueLabel: basalValueLabel)
        ])
        rowsStack.axis = .vertical
        rowsStack.spacing = 5
        rowsStack.setCustomSpacing(12, after: carbsRow) // extra space before insulin rows

        let mainStack = UIStackView(arrangedSubviews: [startRow, endRow, durationControl, rowsStack])
        mainStack.axis = .vertical
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])

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

    // MARK: - Summation
    private func updateTotals() {
        insulinTotal = 0; bolusTotal = 0; smbTotal = 0; basalTotal = 0; carbsTotal = 0
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
        // Overall insulin = SMB + Bolus + Temp Basal
        insulinTotal = smbTotal + bolusTotal + basalTotal
        // update UI
        insulinTotalValueLabel.text = String(format: "%.2f E", insulinTotal)
        bolusValueLabel.text        = String(format: "%.2f E", bolusTotal)
        smbValueLabel.text          = String(format: "%.2f E", smbTotal)
        basalValueLabel.text        = String(format: "%.2f E", basalTotal)
        carbsValueLabel.text        = String(format: "%.0f g",  carbsTotal)
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
                         boldText: Bool = false) -> UIStackView {
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
        return row
    }
}

private extension UIFont {
    func withTraits(traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
