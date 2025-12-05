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
    let amount: Double         // insulin units, carb grams, or blood glucose (mmol/L)
    let foodType: String?      // non-nil for Carb Corrections with fat/protein equivalents
}

/// Glucose data point (mmol/L)
struct BGEntry {
    let date: Date
    let mmol: Double
}

class MealAnalysisView: UIViewController, ChartViewDelegate {

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
    private var events: [Event]          // will be augmented with cached entries
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
        picker.locale = Locale(identifier: "sv_SE")
        picker.translatesAutoresizingMaskIntoConstraints = false
        // Compact height
        picker.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return picker
    }()
    
    private let endPicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .compact
        picker.locale = Locale(identifier: "sv_SE")
        picker.translatesAutoresizingMaskIntoConstraints = false
        // Compact height
        picker.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return picker
    }()

    private let startTimeLabel: UILabel = {
        let label = UILabel()
        label.text = "Starttid"
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let endTimeLabel: UILabel = {
        let label = UILabel()
        label.text = "Sluttid"
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let durationControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["1h", "2h", "3h", "4h", "6h", "12h", "24h", "Dag", "Ⓢ"])
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

    /// When `true`, any undelivered insulin (< 0.05 U) at the end of a Temp‑Basal segment
    /// is carried over to the next segment.
    /// When `false`, each segment starts its own accumulator (default behaviour).
    var carryOverUndeliveredBasals: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        if modalWithTimestamp {
            //title = "Utfall efter måltid"
            title = modalTitleString
        } else {
            title = "Utv. vald tid"
        }

        // When opened without a linked meal, default to "Dag" (today 00:00–now)
        if !modalWithTimestamp {
            durationControl.selectedSegmentIndex = 7   // "Dag"
            let now = Date()
            startTime = Calendar.current.startOfDay(for: now)
            endTime = now
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
        startGroup.spacing = 8
        startGroup.setContentHuggingPriority(.required, for: .horizontal)

        let endGroup = UIStackView(arrangedSubviews: [endTimeLabel, endPicker])
        endGroup.axis = .horizontal
        endGroup.alignment = .center
        endGroup.spacing = 8
        endGroup.setContentHuggingPriority(.required, for: .horizontal)

        let timeRow = UIStackView(arrangedSubviews: [startGroup, endGroup])
        timeRow.axis = .vertical
        timeRow.alignment = .fill
        timeRow.spacing = 8

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
            makeRow(iconName: "stop.circle",
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
        mainStack.setCustomSpacing(8, after: timeRow)   // extra gap before duration
        mainStack.setCustomSpacing(20, after: durationControl)   // extra gap before totals
        mainStack.setCustomSpacing(10, after: rowsStack)   // clear separation
        mainStack.setCustomSpacing(15, after: bgChartView)   // extra gap before stats
        mainStack.setCustomSpacing(5, after: statsStack)   // smaller gap after stats

        recalcEndTimeBasedOnDuration()
        updateTotals()
        fetchBGData()
        // — Pull additional days from NightscoutCache (if any) —
        loadCachedData()

        // ← / → dag‑hopp
        let prevBtn = UIBarButtonItem(image: UIImage(systemName: "chevron.left"),
                                      style: .plain,
                                      target: self,
                                      action: #selector(previousDayTapped))
        let nextBtn = UIBarButtonItem(image: UIImage(systemName: "chevron.right"),
                                      style: .plain,
                                      target: self,
                                      action: #selector(nextDayTapped))
        navigationItem.leftBarButtonItems = [prevBtn, nextBtn]

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissSelf)
        )
    }
    
    /// Fetch BG data for the current window.
    /// - If fönstret överlappar de senaste 24 timmarna använder vi befintlig 24h‑fetchen för “live” data.
    /// - Oavsett, komplettera med BG‑värden från NightscoutCache så att äldre måltider får kurvor.
    private func fetchBGData() {
        let now = Date()
        let dayAgo = now.addingTimeInterval(-24 * 60 * 60)

        // Behåll befintligt beteende för “nära nu” (senaste 24h)
        if endTime > dayAgo {
            fetchBG24h()
        }

        // Komplettera med BG-data från NightscoutCache för hela analysfönstret.
        loadBGFromCache()
    }

    @objc private func dismissSelf() {
        dismiss(animated: true, completion: nil)
    }

    // MARK: - ±1‑day navigation
    @objc private func previousDayTapped() {
        shiftWindow(byDays: -1)
    }

    @objc private func nextDayTapped() {
        shiftWindow(byDays: 1)
    }

    /// Shifts the current time window an integral number of days while keeping its width.
    /// - Parameter days: Negative = back in time, Positive = forward.
    private func shiftWindow(byDays days: Int) {
        guard days != 0 else { return }
        let oneDay = TimeInterval(86_400 * days)

        let newStart = startTime.addingTimeInterval(oneDay)
        let newEnd   = endTime  .addingTimeInterval(oneDay)

        // Respect data limits already enforced by the pickers
        if let minDate = startPicker.minimumDate, newStart < minDate { return }
        if let maxDate = endPicker.maximumDate,  newEnd   > maxDate { return }

        startTime = newStart
        endTime   = newEnd
        startPicker.date = newStart
        endPicker.date   = newEnd

        // Clear “1h–24h” preset so UI reflects a custom interval
        if (0...6).contains(durationControl.selectedSegmentIndex) {
            durationControl.selectedSegmentIndex = UISegmentedControl.noSegment
        }

        updateTotals()
        updateBGLabels()
    }

    // MARK: - Actions

    // MARK: - Time calculations

    @objc private func startTimeChanged(_ sender: UIDatePicker) {
        // Drop "1h…24h" selection when manually adjusting dates
        if (0...6).contains(durationControl.selectedSegmentIndex) {
            durationControl.selectedSegmentIndex = UISegmentedControl.noSegment
        }
        // Grab the (optional) title now that we might have cleared it
        let title = durationControl.selectedSegmentIndex >= 0 ? durationControl.titleForSegment(at: durationControl.selectedSegmentIndex) : nil
        let calendar = Calendar.current

        if title == "Ⓢ" {
            // Schoolday: always 08:00 → (now if before 16:30 today, else 16:30)
            let comps = calendar.dateComponents([.year, .month, .day], from: sender.date)
            let newStart = calendar.date(from: DateComponents(
                year: comps.year, month: comps.month, day: comps.day,
                hour: 8, minute: 0
            ))!
            let schoolEnd = calendar.date(from: DateComponents(
                year: comps.year, month: comps.month, day: comps.day,
                hour: 16, minute: 30
            ))!
            let newEnd: Date
            if calendar.isDateInToday(sender.date), Date() < schoolEnd {
                newEnd = Date()
            } else {
                newEnd = schoolEnd
            }

            startTime = newStart
            endTime   = newEnd
            startPicker.date = newStart
            endPicker.date   = newEnd

        } else if title == "Dag" {
            // Full calendar day: midnight → (now if today, else next midnight)
            let comps = calendar.dateComponents([.year, .month, .day], from: sender.date)
            let newStart = calendar.date(from: DateComponents(
                year: comps.year, month: comps.month, day: comps.day,
                hour: 0, minute: 0
            ))!
            let newEnd: Date
            if calendar.isDateInToday(sender.date) {
                newEnd = Date()
            } else {
                newEnd = calendar.date(byAdding: .day, value: 1, to: newStart)!
            }

            startTime = newStart
            endTime   = newEnd
            startPicker.date = newStart
            endPicker.date   = newEnd

        } else {
            // Other modes (timestamp modal or fixed durations)
            startTime = sender.date
            if modalWithTimestamp && durationControl.selectedSegmentIndex != UISegmentedControl.noSegment {
                recalcEndTimeBasedOnDuration()
            }
        }

        // Update UI for all cases
        updateTotals()
        updateBGLabels()
    }

    @objc private func durationChanged(_ sender: UISegmentedControl) {
        recalcEndTimeBasedOnDuration()
        updateTotals()
        updateBGLabels()
    }

    @objc private func endTimeChanged(_ sender: UIDatePicker) {
        // Drop "1h…24h" selection when manually adjusting dates
        if (0...6).contains(durationControl.selectedSegmentIndex) {
            durationControl.selectedSegmentIndex = UISegmentedControl.noSegment
        }
        // Grab the (optional) title now that we might have cleared it
        let title = durationControl.selectedSegmentIndex >= 0 ? durationControl.titleForSegment(at: durationControl.selectedSegmentIndex) : nil
        let calendar = Calendar.current

        if title == "Ⓢ" {
            // Schoolday: always 08:00 → (now if before 16:30 today, else 16:30)
            let comps = calendar.dateComponents([.year, .month, .day], from: sender.date)
            let newStart = calendar.date(from: DateComponents(
                year: comps.year, month: comps.month, day: comps.day,
                hour: 8, minute: 0
            ))!
            let schoolEnd = calendar.date(from: DateComponents(
                year: comps.year, month: comps.month, day: comps.day,
                hour: 16, minute: 30
            ))!
            let newEnd: Date
            if calendar.isDateInToday(sender.date), Date() < schoolEnd {
                newEnd = Date()
            } else {
                newEnd = schoolEnd
            }

            startTime = newStart
            endTime   = newEnd
            startPicker.date = newStart
            endPicker.date   = newEnd

        } else if title == "Dag" {
            // Full calendar day: midnight → (now if today, else next midnight)
            let comps = calendar.dateComponents([.year, .month, .day], from: sender.date)
            let newStart = calendar.date(from: DateComponents(
                year: comps.year, month: comps.month, day: comps.day,
                hour: 0, minute: 0
            ))!
            let newEnd: Date
            if calendar.isDateInToday(sender.date) {
                newEnd = Date()
            } else {
                newEnd = calendar.date(byAdding: .day, value: 1, to: newStart)!
            }

            startTime = newStart
            endTime   = newEnd
            startPicker.date = newStart
            endPicker.date   = newEnd

        } else {
            // Other modes
            var selected = sender.date
            let now = Date()
            if selected > now {
                selected = now
                sender.date = now
            }
            endTime = selected
            if modalWithTimestamp && durationControl.selectedSegmentIndex != UISegmentedControl.noSegment {
                recalcEndTimeBasedOnDuration()
            }
        }

        updateTotals()
        updateBGLabels()
    }
    
    private func recalcEndTimeBasedOnDuration() {
        let idx = durationControl.selectedSegmentIndex
        guard idx != UISegmentedControl.noSegment,
              idx < durationControl.numberOfSegments,
              let title = durationControl.titleForSegment(at: idx) else { return }
        let calendar = Calendar.current

        if title == "Dag" {
            // Full calendar day: midnight → (now if today, else next midnight)
            let dayStart = calendar.startOfDay(for: startTime)
            startTime = dayStart
            let newEnd: Date
            if calendar.isDateInToday(dayStart) {
                newEnd = Date()
            } else {
                newEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            }
            endTime = newEnd
            startPicker.date = startTime
            endPicker.date = endTime

        } else if title == "Ⓢ" {
            // Schoolday: always 08:00 → (now if before 16:30; else 16:30)
            // Use the same calendar-day as startTime (preserves date if you entered via modal)
            let comps = calendar.dateComponents([.year, .month, .day], from: startTime)
            let newStart = calendar.date(from: DateComponents(
                year: comps.year, month: comps.month, day: comps.day,
                hour: 8, minute: 0
            ))!
            let schoolEnd = calendar.date(from: DateComponents(
                year: comps.year, month: comps.month, day: comps.day,
                hour: 16, minute: 30
            ))!
            let newEnd: Date
            if calendar.isDateInToday(newStart), Date() < schoolEnd {
                // if it’s today *and* before 16:30, end = now
                newEnd = Date()
            } else {
                // otherwise end = 16:30 of that day
                newEnd = schoolEnd
            }
            startTime = newStart
            endTime   = newEnd
            startPicker.date = newStart
            endPicker.date   = newEnd

        } else {
            // Hacker for “1h”, “2h”, etc., or modal-with-timestamp
            let hoursString = title.replacingOccurrences(of: "h", with: "")
            let hours = Int(hoursString) ?? 1

            if modalWithTimestamp {
                // From startTime + hours → endTime
                endTime = calendar.date(byAdding: .hour, value: hours, to: startTime)!
                if endTime > Date() {
                    endTime = Date()
                }
                endPicker.date = endTime
            } else {
                // From endTime − hours → startTime
                startTime = calendar.date(byAdding: .hour, value: -hours, to: endTime)!
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
            let cal = Calendar.current
            // Build DateComponents (hour,minute,second) for all schedule breakpoints
            let breakpoints: [DateComponents] = schedule.map { entry in
                let h = entry.timeAsSeconds / 3600
                let m = (entry.timeAsSeconds % 3600) / 60
                let s = entry.timeAsSeconds % 60
                var dc = DateComponents()
                dc.hour = h
                dc.minute = m
                dc.second = s
                return dc
            }
            var candidate: Date? = nil
            for dc in breakpoints {
                // Find the next occurrence of this wall time strictly AFTER `date`.
                // Use `.nextTime` + `.last` to pick the later occurrence on fall‑back days.
                if let d = cal.nextDate(after: date,
                                         matching: dc,
                                         matchingPolicy: .nextTime,
                                         repeatedTimePolicy: .last,
                                         direction: .forward) {
                    if d > date { // strictly after
                        if candidate == nil || d < candidate! {
                            candidate = d
                        }
                    }
                }
            }
            // If nothing found (shouldn’t happen), move 1 second forward to guarantee progress
            return candidate ?? cal.date(byAdding: .second, value: 1, to: date)!
        }

        while current < end {
            // Defensive: if for any reason `current` isn’t strictly advancing, push it by 1 second
            // (should be redundant with the new nextChange(), but prevents hangs)
            let rate = basalRate(at: current)
            let next = min(end, nextChange(after: current))
            // Ensure strict monotonicity across DST fall‑back;
            // if next did not move forward, bump by 1 second
            if next <= current {
                let bumped = Calendar.current.date(byAdding: .second, value: 1, to: current)!
                if bumped < end {
                    // Recompute with the bumped time to keep accounting precise
                    let strictNext = min(end, nextChange(after: bumped))
                    if strictNext > current {
                        // proceed with strictNext
                        let hours = strictNext.timeIntervalSince(current) / 3600.0
                        total += rate * hours
                        current = strictNext
                        continue
                    }
                }
                // Fallback: break to avoid an infinite loop
                break
            }
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
            default: break
            }
        }
        // ——— Delivered Temp‑Basal pulses (0.05 U) with rate‑dependent timing ———
        basalTotal = 0
        let tempBasals = events
            .filter { $0.eventType == "Temp Basal" && $0.date < endTime }
            .sorted { $0.date < $1.date }
        //#if DEBUG
        //        print("Totals ▸ TempBasal events in window:")
        //tempBasals.forEach {
        //    print("Totals ▸   event \($0.date)  rate \($0.amount) U/h")
        //}
        //#endif

        //#if DEBUG
        // Carry‑over aware pulse simulation
        //#endif
        
        var residual = 0.0                      // undelivered <0.05 U from previous segment
        for (idx, evt) in tempBasals.enumerated() {
            let segmentStart = max(evt.date, startTime)
            let segmentEnd: Date = {
                if idx + 1 < tempBasals.count {
                    return min(tempBasals[idx + 1].date, endTime)
                } else {
                    return endTime
                }
            }()
            guard segmentStart < segmentEnd else { continue }
            let rate = evt.amount                       // U/h
            guard rate > 0 else {                       // 0 U/h just closes previous segment
                if !carryOverUndeliveredBasals { residual = 0 }
                continue
            }

            let ratePerSec = rate / 3600.0
            var t = segmentStart
            var accum = carryOverUndeliveredBasals ? residual : 0.0

            //#if DEBUG
            //print("Totals ▸ TempBasal  rate=\(rate) U/h  segmentStart=\(segmentStart)  segmentEnd=\(segmentEnd)  residualIn=\(accum)")
            //#endif

            while true {
                let remaining = 0.05 - accum
                let dt = remaining / ratePerSec            // seconds to next pulse
                if t.addingTimeInterval(dt) > segmentEnd { // will not reach next pulse
                    accum += ratePerSec * segmentEnd.timeIntervalSince(t)
                    t = segmentEnd
                    break
                }
                t = t.addingTimeInterval(dt)               // pulse moment
                if t >= startTime {
                    basalTotal += 0.05
                    //#if DEBUG
                    //print("Totals ▸   counting pulse \(t)")
                    //#endif
                }
                accum = 0.0                                // reset after delivery
            }

            residual = carryOverUndeliveredBasals ? accum : 0.0
        }
        //#if DEBUG
        //print("Totals ▸ basalTotal delivered = \(basalTotal) U")
        //#endif
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
    /// Normalizes and merges BG entries by timestamp, removes duplicates, and gap-fills 5‑min intervals.
    private func normalizedMergedBG(existing: [BGEntry], new: [BGEntry]) -> [BGEntry] {
        let cal = Calendar.current
        var merged: [TimeInterval: BGEntry] = [:]

        for e in existing {
            merged[e.date.timeIntervalSince1970] = e
        }
        for e in new {
            merged[e.date.timeIntervalSince1970] = e
        }

        // Sort
        let sorted = merged.values.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [] }

        // Gap-fill 5‑min slots if >6min gaps
        var out: [BGEntry] = []
        out.reserveCapacity(sorted.count)

        for i in 0..<sorted.count {
            let curr = sorted[i]
            out.append(curr)

            if i < sorted.count - 1 {
                let next = sorted[i+1]
                let gap = next.date.timeIntervalSince(curr.date)
                if gap > 360 {
                    let missing = Int(floor((gap - 360)/300)) + 1
                    if missing > 0 {
                        for k in 1...missing {
                            let d = curr.date.addingTimeInterval(Double(k)*300)
                            let filler = BGEntry(date: d, mmol: curr.mmol)
                            out.append(filler)
                        }
                    }
                }
            }
        }
        return out
    }

    /// Laddar BG‑värden från NightscoutCache för det aktuella analysfönstret
    /// och merge:ar dem in i `bgEntries`. Detta gör att äldre måltider (även >10 dagar)
    /// får glukoskurva så länge de finns i 90‑dagarscachen.
    private func loadBGFromCache() {
        let windowStart = startTime
        let windowEnd   = endTime

        Task {
            let cal = Calendar.current
            // Use a ±12h buffer to avoid clipping SGVs just outside the visible window
            // (e.g. when the window starts/ends near midnight), then trim locally.
            let bufferedStart = cal.date(byAdding: .hour, value: -12, to: windowStart) ?? windowStart
            let bufferedEnd   = cal.date(byAdding: .hour, value: 12, to: windowEnd)   ?? windowEnd

            // NightscoutCache returns both sgv and treatments; here we only care about sgv.
            let (sgvPoints, _) = await NightscoutCache.loadWindow(from: bufferedStart, to: bufferedEnd)

            // Map cache points to BGEntry in mmol/L and clamp them back to [windowStart, windowEnd].
            let factor = 18.0182
            let cachedBG: [BGEntry] = sgvPoints.map { point in
                let mmol = Double(point.sgv) / factor
                return BGEntry(date: Date(timeIntervalSince1970: point.date), mmol: mmol)
            }
            .filter { $0.date >= windowStart && $0.date <= windowEnd }

            let merged = self.normalizedMergedBG(existing: self.bgEntries, new: cachedBG)

            await MainActor.run {
                self.bgEntries = merged
                self.refreshBGChart()
                self.updateBGLabels()
            }
        }
    }

    // MARK: - BG chart helpers
    private func setupBGChart() {
        bgChartView.delegate = self
        bgChartView.chartDescription.enabled = false
        bgChartView.legend.enabled = false
        bgChartView.rightAxis.enabled = false
        bgChartView.pinchZoomEnabled = false
        bgChartView.doubleTapToZoomEnabled = false
        bgChartView.dragEnabled = false
        bgChartView.highlightPerTapEnabled = true
        bgChartView.scaleXEnabled = false
        bgChartView.scaleYEnabled = false
        bgChartView.drawOrder = [CombinedChartView.DrawOrder.line.rawValue, CombinedChartView.DrawOrder.scatter.rawValue]

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
        // Main BG line dataset broken on gaps > 9 min
        let segmentGap: TimeInterval = 9 * 60  // seconds
        var segments: [[ChartDataEntry]] = []
        var currentSegment: [ChartDataEntry] = []
        var lastX: Double? = nil

        for entry in entries {
            if let last = lastX, (entry.x - last) * 3600.0 > segmentGap {
                if !currentSegment.isEmpty {
                    segments.append(currentSegment)
                }
                currentSegment = []
            }
            currentSegment.append(entry)
            lastX = entry.x
        }
        if !currentSegment.isEmpty {
            segments.append(currentSegment)
        }

        let lineDataSets = segments.map { segEntries -> LineChartDataSet in
            let ds = LineChartDataSet(entries: segEntries, label: "")
            ds.colors = segEntries.map { setBGColorForMmol($0.y) }
            ds.lineWidth = 3
            ds.drawCirclesEnabled = false
            ds.drawValuesEnabled = false
            ds.mode = .linear
            ds.highlightColor = .clear
            ds.highlightLineWidth = 0
            return ds
        }

        // ▸ Blue dots for Bolus at y = 22 mmol
        let bolusEntries = events.filter {
            $0.eventType == "Bolus" && $0.date >= startTime && $0.date <= endTime
        }.map { event in
            ChartDataEntry(
                x: event.date.timeIntervalSince(startTime) / 3600.0,
                y: 22.0,
                data: String(format: "%.2f E", event.amount)
            )
        }
        let bolusDots = ScatterChartDataSet(entries: bolusEntries, label: "")
        bolusDots.setColor(NSUIColor.systemBlue)
        bolusDots.setScatterShape(.circle)
        bolusDots.scatterShapeSize = 8
        bolusDots.drawValuesEnabled = false
        bolusDots.highlightEnabled = true
        bolusDots.highlightColor = .clear
        bolusDots.highlightLineWidth = 0
        
        // ▸ Blue triangles for SMB at y = 22 mmol
        let smbEntries = events.filter {
            $0.eventType == "SMB" && $0.date >= startTime && $0.date <= endTime
        }.map { event in
            ChartDataEntry(
                x: event.date.timeIntervalSince(startTime) / 3600.0,
                y: 22.0,
                data: String(format: "%.2f E", event.amount)
            )
        }
        let smbDots = ScatterChartDataSet(entries: smbEntries, label: "")
        smbDots.setColor(NSUIColor.systemBlue)
        smbDots.setScatterShape(.triangleFlipped)
        smbDots.scatterShapeSize = 9
        smbDots.drawValuesEnabled = false
        smbDots.highlightEnabled = true
        smbDots.highlightColor = .clear
        smbDots.highlightLineWidth = 0

        // ▸ Triangles for Carb Correction: orange for “real” carbs, brown for fat/protein equivalents
        let carbCorrections = events.filter {
            $0.eventType == "Carb Correction" &&
            $0.date >= startTime && $0.date <= endTime
        }

        // Orange for those with a non-empty foodType
        let orangeEntries = carbCorrections
            .filter { ($0.foodType ?? "").isEmpty == false }
            .map { event in
                ChartDataEntry(
                    x: event.date.timeIntervalSince(startTime) / 3600.0,
                    y: 2.0,
                    data: String(format: "%.0f g", event.amount)
                )
            }
        let orangeDots = ScatterChartDataSet(entries: orangeEntries, label: "")
        orangeDots.setColor(.systemOrange.withAlphaComponent(1.0))
        orangeDots.setScatterShape(.triangle)
        orangeDots.scatterShapeSize = 9
        orangeDots.drawValuesEnabled = false
        orangeDots.highlightEnabled = true
        orangeDots.highlightColor = .clear
        orangeDots.highlightLineWidth = 0

        // Brown for fat/protein equivalents (empty foodType)
        let brownEntries = carbCorrections
            .filter { ($0.foodType ?? "").isEmpty }
            .map { event in
                ChartDataEntry(
                    x: event.date.timeIntervalSince(startTime) / 3600.0,
                    y: 2.0,
                    data: String(format: "%.0f g", event.amount)
                )
            }
        let brownDots = ScatterChartDataSet(entries: brownEntries, label: "")
        brownDots.setColor(.brown.withAlphaComponent(0.8))
        brownDots.setScatterShape(.triangle)
        brownDots.scatterShapeSize = 7
        brownDots.drawValuesEnabled = false
        brownDots.highlightEnabled = true
        brownDots.highlightColor = .clear
        brownDots.highlightLineWidth = 0

        // ▸ Red circles for BG Check events at their glucose level
        let bgCheckEvents = events.filter {
            $0.eventType == "BG Check" && $0.date >= startTime && $0.date <= endTime
        }
        //print("DEBUG ▸ BG Check events: count = \(bgCheckEvents.count)")
        //for evt in bgCheckEvents {
            //let x = evt.date.timeIntervalSince(startTime) / 3600.0
            //let y = evt.amount
            //print("DEBUG ▸ BG Check event: date = \(evt.date), x = \(x), y = \(y)")
        //}
        let bgCheckEntries = bgCheckEvents.map { event in
            ChartDataEntry(
                x: event.date.timeIntervalSince(startTime) / 3600.0,
                y: event.amount,
                data: String(format: "%.1f mmol", event.amount)
            )
        }
        let bgCheckDots = ScatterChartDataSet(entries: bgCheckEntries, label: "")
        bgCheckDots.setColor(.systemRed)
        bgCheckDots.setScatterShape(.circle)
        bgCheckDots.scatterShapeSize = 7
        bgCheckDots.drawValuesEnabled = false
        bgCheckDots.highlightEnabled = true
        bgCheckDots.highlightColor = .clear
        bgCheckDots.highlightLineWidth = 0

        // ▸ Squares for Temp Basal actual deliveries (0.05 U pulses) at y = 23 mmol
        // Pulse interval = 180 / rate seconds. Counter resets on each rate change.
        let tempBasals = events
            .filter { $0.eventType == "Temp Basal" }
            .sorted { $0.date < $1.date }
        //#if DEBUG
        //print("Chart  ▸ TempBasal events in window:")
        //tempBasals.forEach {
        //print("Chart  ▸   event \($0.date)  rate \($0.amount) U/h")
        //}
        //#endif

        var basalEntries: [ChartDataEntry] = []

        // Carry‑over aware pulse simulation for scatter dots
        var residual = 0.0
        for (idx, evt) in tempBasals.enumerated() {
            let segmentStart = max(evt.date, startTime)
            let segmentEnd: Date = {
                if idx + 1 < tempBasals.count {
                    return min(tempBasals[idx + 1].date, endTime)
                } else {
                    return endTime
                }
            }()
            guard segmentStart < segmentEnd else { continue }
            let rate = evt.amount
            //#if DEBUG
            //print("Chart  ▸ TempBasal  rate=\(rate) U/h  segmentStart=\(segmentStart)  segmentEnd=\(segmentEnd)  residualIn=\(residual)")
            //#endif
            guard rate > 0 else {
                if !carryOverUndeliveredBasals { residual = 0 }
                continue
            }

            let ratePerSec = rate / 3600.0
            var t = segmentStart
            var accum = carryOverUndeliveredBasals ? residual : 0.0

            while true {
                let remaining = 0.05 - accum
                let dt = remaining / ratePerSec
                if t.addingTimeInterval(dt) > segmentEnd {        // no more pulses
                    accum += ratePerSec * segmentEnd.timeIntervalSince(t)
                    t = segmentEnd
                    break
                }
                t = t.addingTimeInterval(dt)
                if t >= startTime {
                    basalEntries.append(
                        ChartDataEntry(
                            x: t.timeIntervalSince(startTime) / 3600.0,
                            y: 23.0,
                            data: String(format: "%.2f U/h", rate)
                        )
                    )
                    //#if DEBUG
                    //print("Chart  ▸   pulse at \(t)")
                    //#endif
                }
                accum = 0.0
            }
            residual = carryOverUndeliveredBasals ? accum : 0.0
        }

        let basalSquares = ScatterChartDataSet(entries: basalEntries, label: "")
        basalSquares.setColor(NSUIColor.systemBlue.withAlphaComponent(0.45))
        basalSquares.setScatterShape(.square)
        basalSquares.scatterShapeSize = 6
        basalSquares.drawValuesEnabled = false
        basalSquares.highlightColor = .clear
        basalSquares.highlightLineWidth = 0

        // Combine
        let combined = CombinedChartData()
        combined.lineData   = LineChartData(dataSets: lineDataSets)
        combined.scatterData = ScatterChartData(dataSets: [bolusDots, smbDots, orangeDots, brownDots, bgCheckDots, basalSquares])
        bgChartView.data = combined

        // X range & labels
        let hrs = max(endTime.timeIntervalSince(startTime)/3600.0, 0.1)
        let x = bgChartView.xAxis
        x.axisMinimum = 0
        x.axisMaximum = hrs
        if hrs <= 6 {
            x.granularity = 1
            x.labelCount = Int(hrs.rounded(.up)) + 1
        } else if hrs <= 24 {
            x.granularity = 3
            x.labelCount = Int((hrs/3).rounded(.up)) + 1
        } else if hrs <= 72 {
            x.granularity = 12
            x.labelCount = Int((hrs/12).rounded(.up)) + 1
        } else {
            x.granularity = 24
            x.labelCount = Int((hrs/24).rounded(.up)) + 1
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
            // Convert mg/dL → mmol/L for new readings
            let newBG = sgv.map {
                BGEntry(date: Date(timeIntervalSince1970: $0.date),
                        mmol: Double($0.sgv) / 18.0182)
            }
            let merged = self.normalizedMergedBG(existing: self.bgEntries, new: newBG)
            self.bgEntries = merged
            
            // Update UI
            self.updateBGLabels()
            self.refreshBGChart()
        }
    }

    // MARK: - Cache integration
    /// Extend `events` and `bgEntries` with any older data kept in NightscoutCache,
    /// then widen the startPicker’s lower bound.
    private func loadCachedData() {
        Task.detached { [weak self] in
            guard let self = self else { return }
            // Ask for the full retention window (default 10 days)
            let cal = Calendar.current
            // Compute the start-of-day for the retention window
            let tempDate = cal.date(byAdding: .day,
                                    value: -NightscoutCache.retentionDays,
                                    to: Date())!
            let oldestWanted = cal.startOfDay(for: tempDate)

            LogManager.shared.log(category: .analysis, message: "Cache ▸ loadCachedData: requesting from \(oldestWanted) to now", isDebug: true)

            // Always load cached data up through the current moment
            let (sgvJSON, treatsJSON) = await NightscoutCache.loadWindow(
                from: oldestWanted,
                to: Date()
            )

            LogManager.shared.log(category: .analysis, message: "Cache ▸ raw sgvJSON.count = \(sgvJSON.count), treatsJSON.count = \(treatsJSON.count)", isDebug: true)

            // Convert SGVs → BGEntry, convert mg/dL → mmol/L (18.0182)
            let extraBG = sgvJSON.map {
                BGEntry(
                    date: Date(timeIntervalSince1970: $0.date),
                    mmol: Double($0.sgv) / 18.0182  // mg/dL → mmol/L
                )
            }

            // Convert Treatments → Event (subset of buildEventsArray logic)
            let extraEvents: [Event] = treatsJSON.compactMap { t in
                switch t.eventType {
                case "SMB":
                    guard let amt = t.insulin else { return nil }
                    return Event(date: t.created_at, eventType: "SMB", amount: amt, foodType: nil)
                case "Bolus", "Correction Bolus":
                    guard let amt = t.insulin else { return nil }
                    return Event(date: t.created_at, eventType: "Bolus", amount: amt, foodType: nil)
                case "Carb Correction":
                    guard let grams = t.carbs else { return nil }
                    return Event(date: t.created_at, eventType: "Carb Correction",
                                 amount: grams, foodType: t.foodType)
                case "Temp Basal":
                    let rate = t.rate ?? t.absolute ?? 0.0
                    return Event(date: t.created_at, eventType: "Temp Basal", amount: rate, foodType: nil)
                case "BG Check":
                    guard let glucose = t.glucose else { return nil }
                    let mmol: Double
                    if let units = t.units?.lowercased(), units.contains("mmol") {
                        mmol = glucose
                    } else {
                        mmol = glucose / 18.0
                    }
                    return Event(date: t.created_at, eventType: "BG Check", amount: mmol, foodType: nil)
                default:
                    return nil
                }
            }

            // Merge without duplicates (by exact timestamp + type)
            DispatchQueue.main.async {
                LogManager.shared.log(category: .analysis, message: "Cache ▸ existing bgEntries.count = \(self.bgEntries.count)", isDebug: true)
                LogManager.shared.log(category: .analysis, message: "Cache ▸ extraBG.count = \(extraBG.count)", isDebug: true)
                // BG merge
                let merged = self.normalizedMergedBG(existing: self.bgEntries, new: extraBG)
                self.bgEntries = merged
                LogManager.shared.log(category: .analysis, message: "Cache ▸ merged bgEntries.count = \(self.bgEntries.count)", isDebug: true)

                // Event merge
                let existingKeys = Set(self.events.map { "\($0.date.timeIntervalSince1970)|\($0.eventType)" })
                self.events += extraEvents.filter {
                    !existingKeys.contains("\($0.date.timeIntervalSince1970)|\($0.eventType)")
                }
                self.events.sort { $0.date < $1.date }
                LogManager.shared.log(category: .analysis, message: "Cache ▸ extraEvents.count = \(extraEvents.count), merged events.count = \(self.events.count)", isDebug: true)

                // Broaden the picker’s lower bound to the earliest entry we now have
                if let earliest = (self.events.map { $0.date } + self.bgEntries.map { $0.date }).min() {
                    self.startPicker.minimumDate = earliest
                    self.endPicker.minimumDate = earliest
                }

                // Refresh totals & charts if the user is looking at an older window
                self.updateTotals()
                self.updateBGLabels()
            }
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

    // MARK: - Chart popup handler (for value selection)
    func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
        let title: String
        if let s = entry.data as? String {
            title = s
        } else {
            title = String(format: "%.2f", entry.y)
        }
        let alert = UIAlertController(title: title, message: "", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}

extension MealAnalysisView: AxisValueFormatter {
    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let date = startTime.addingTimeInterval(value * 3600)
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
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
