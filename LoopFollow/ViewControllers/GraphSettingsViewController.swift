//
//  GraphSettingsViewController.swift
//  LoopFollow
//
//  Created by Jose Paredes on 7/16/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//

import Foundation
import UIKit
import EventKit
import EventKitUI

class GraphSettingsViewController: ThemedViewController, UITableViewDataSource, UITableViewDelegate {

    var appStateController: AppStateController?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    // Background color used for section "cards", mirroring other settings views.
    private let sectionBackgroundColor = UIColor.systemGray.withAlphaComponent(0.15)

    private enum Section: Int, CaseIterable {
        case graphSettings
    }

    private enum GraphRow {
        case showDots
        case showLines
        case showValues
        case showAbsorption
        case showDIALines
        case show30MinLine
        case showMinus24hLine
        case showMidnightLines
        case smallGraphTreatments
        case smallGraphHeight
        case predictionToLoad
        case minBGScale
        case minBasalScale
        case lowLine
        case targetLine
        case highLine
        case downloadDays
    }

    // Controls whether Nightscout-specific rows are shown.
    private var isNightscoutEnabled: Bool = true

    // All rows in order.
    private var allRows: [GraphRow] {
        return [
            .showDots,
            .showLines,
            .showValues,
            .showAbsorption,
            .showDIALines,
            .show30MinLine,
            .showMinus24hLine,
            .showMidnightLines,
            .smallGraphTreatments,
            .smallGraphHeight,
            .predictionToLoad,
            .minBGScale,
            .minBasalScale,
            .lowLine,
            .targetLine,
            .highLine,
            .downloadDays
        ]
    }

    // Rows currently visible, honoring Nightscout enabled/disabled logic.
    private var visibleRows: [GraphRow] {
        guard !allRows.isEmpty else { return [] }
        if isNightscoutEnabled {
            return allRows
        } else {
            // Hide the same rows that Eureka previously hid when Nightscout was disabled.
            return allRows.filter { row in
                switch row {
                case .predictionToLoad,
                     .smallGraphTreatments,
                     .minBasalScale,
                     .showValues,
                     .showAbsorption:
                    return false
                default:
                    return true
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Grafinställningar"

        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }

        // Configure table view
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .singleLine
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        showHideNSDetails()
    }

    // MARK: - Nightscout visibility

    func showHideNSDetails() {
        isNightscoutEnabled = IsNightscoutEnabled()
        tableView.reloadData()
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section(rawValue: section) == .graphSettings else { return 0 }
        return visibleRows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard Section(rawValue: section) == .graphSettings else { return nil }
        return "Grafinställningar"
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section(rawValue: indexPath.section) == .graphSettings else {
            return UITableViewCell(style: .default, reuseIdentifier: "Cell")
        }

        let rowKind = visibleRows[indexPath.row]

        switch rowKind {
        // MARK: Switch rows
        case .showDots,
             .showLines,
             .showValues,
             .showAbsorption,
             .showDIALines,
             .show30MinLine,
             .showMinus24hLine,
             .showMidnightLines,
             .smallGraphTreatments:

            let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell")
                ?? UITableViewCell(style: .default, reuseIdentifier: "SwitchCell")
            cell.selectionStyle = .none
            cell.accessoryType = .none

            let toggle = UISwitch()
            toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)

            switch rowKind {
            case .showDots:
                cell.textLabel?.text = "Visa punkter"
                toggle.isOn = UserDefaultsRepository.showDots.value
                toggle.accessibilityIdentifier = "showDots"
            case .showLines:
                cell.textLabel?.text = "Visa linjer"
                toggle.isOn = UserDefaultsRepository.showLines.value
                toggle.accessibilityIdentifier = "showLines"
            case .showValues:
                cell.textLabel?.text = "Visa kh/bolus-värden"
                toggle.isOn = UserDefaultsRepository.showValues.value
                toggle.accessibilityIdentifier = "showValues"
            case .showAbsorption:
                cell.textLabel?.text = "Visa kh absorption"
                toggle.isOn = UserDefaultsRepository.showAbsorption.value
                toggle.accessibilityIdentifier = "showAbsorption"
            case .showDIALines:
                cell.textLabel?.text = "Visa DIA linjer"
                toggle.isOn = UserDefaultsRepository.showDIALines.value
                toggle.accessibilityIdentifier = "showDIALines"
            case .show30MinLine:
                cell.textLabel?.text = "Visa -30 min linje"
                toggle.isOn = UserDefaultsRepository.show30MinLine.value
                toggle.accessibilityIdentifier = "show30MinLine"
            case .showMinus24hLine:
                cell.textLabel?.text = "Visa -24 h linje"
                toggle.isOn = UserDefaultsRepository.showMinus24hLine.value
                toggle.accessibilityIdentifier = "showMinus24hLine"
            case .showMidnightLines:
                cell.textLabel?.text = "Visa midnattslinjer"
                toggle.isOn = UserDefaultsRepository.showMidnightLines.value
                toggle.accessibilityIdentifier = "showMidnightLines"
            case .smallGraphTreatments:
                cell.textLabel?.text = "Behandlingar på liten graf"
                toggle.isOn = UserDefaultsRepository.smallGraphTreatments.value
                toggle.accessibilityIdentifier = "smallGraphTreatments"
            default:
                break
            }

            cell.accessoryView = toggle
            return cell

        // MARK: Stepper rows
        case .smallGraphHeight,
             .predictionToLoad,
             .minBGScale,
             .minBasalScale,
             .lowLine,
             .targetLine,
             .highLine,
             .downloadDays:

            let cell = tableView.dequeueReusableCell(withIdentifier: "StepperCell")
                ?? UITableViewCell(style: .value1, reuseIdentifier: "StepperCell")
            cell.selectionStyle = .none
            cell.accessoryType = .none

            let stepper = UIStepper()
            stepper.addTarget(self, action: #selector(stepperChanged(_:)), for: .valueChanged)

            switch rowKind {
            case .smallGraphHeight:
                cell.textLabel?.text = "Höjd på liten graf"
                stepper.minimumValue = 40
                stepper.maximumValue = 80
                stepper.stepValue = 5
                stepper.accessibilityIdentifier = "smallGraphHeight"
                stepper.value = Double(UserDefaultsRepository.smallGraphHeight.value)
                cell.detailTextLabel?.text = "\(Int(stepper.value))"

            case .predictionToLoad:
                cell.textLabel?.text = "Timmar prognos"
                stepper.minimumValue = 0.0
                stepper.maximumValue = 6.0
                stepper.stepValue = 0.25
                stepper.accessibilityIdentifier = "predictionToLoad"
                stepper.value = UserDefaultsRepository.predictionToLoad.value
                cell.detailTextLabel?.text = String(format: "%.2f", stepper.value)

            case .minBGScale:
                cell.textLabel?.text = "Min BG skala"
                let currentMin = Double(UserDefaultsRepository.minBGScale.value)
                stepper.minimumValue = currentMin
                stepper.maximumValue = 400
                stepper.stepValue = 1
                stepper.accessibilityIdentifier = "minBGScale"
                stepper.value = currentMin
                cell.detailTextLabel?.text = Localizer.toDisplayUnits(String(stepper.value))

            case .minBasalScale:
                cell.textLabel?.text = "Min basal skala"
                stepper.minimumValue = 0.5
                stepper.maximumValue = 20.0
                stepper.stepValue = 0.5
                stepper.accessibilityIdentifier = "minBasalScale"
                stepper.value = Double(UserDefaultsRepository.minBasalScale.value)
                cell.detailTextLabel?.text = String(format: "%.1f", stepper.value)

            case .lowLine:
                cell.textLabel?.text = "Lågt BG linje"
                stepper.minimumValue = 20
                stepper.maximumValue = 100
                stepper.stepValue = 10
                stepper.accessibilityIdentifier = "lowLine"
                stepper.value = Double(UserDefaultsRepository.lowLine.value)
                cell.detailTextLabel?.text = Localizer.toDisplayUnits(String(stepper.value))

            case .targetLine:
                cell.textLabel?.text = "Mål BG linje"
                stepper.minimumValue = 80
                stepper.maximumValue = 160
                stepper.stepValue = 1
                stepper.accessibilityIdentifier = "targetLine"
                stepper.value = Double(UserDefaultsRepository.targetLine.value)
                cell.detailTextLabel?.text = Localizer.toDisplayUnits(String(stepper.value))

            case .highLine:
                cell.textLabel?.text = "Högt BG linje"
                stepper.minimumValue = 120
                stepper.maximumValue = 300
                stepper.stepValue = 10
                stepper.accessibilityIdentifier = "highLine"
                stepper.value = Double(UserDefaultsRepository.highLine.value)
                cell.detailTextLabel?.text = Localizer.toDisplayUnits(String(stepper.value))

            case .downloadDays:
                cell.textLabel?.text = "Visa dagar tillbaka"
                stepper.minimumValue = 1
                stepper.maximumValue = 4
                stepper.stepValue = 1
                stepper.accessibilityIdentifier = "downloadDays"
                stepper.value = Double(UserDefaultsRepository.downloadDays.value)
                cell.detailTextLabel?.text = "\(Int(stepper.value))"

            default:
                break
            }

            cell.accessoryView = stepper
            return cell
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView,
                   willDisplay cell: UITableViewCell,
                   forRowAt indexPath: IndexPath) {
        // Match the semi-transparent card background used in other settings views, including under the accessory chevrons.
        if #available(iOS 14.0, *) {
            var background = UIBackgroundConfiguration.listGroupedCell()
            background.backgroundColor = sectionBackgroundColor
            cell.backgroundConfiguration = background
        } else {
            cell.backgroundColor = sectionBackgroundColor
            cell.contentView.backgroundColor = sectionBackgroundColor
        }
    }

    // MARK: - Switch handling

    @objc private func switchChanged(_ sender: UISwitch) {
        switch sender.accessibilityIdentifier {
        case "showDots":
            UserDefaultsRepository.showDots.value = sender.isOn
            if let appState = appStateController {
                appState.chartSettingsChanged = true
                appState.chartSettingsChanges |= ChartSettingsChangeEnum.showDotsChanged.rawValue
            }

        case "showLines":
            UserDefaultsRepository.showLines.value = sender.isOn
            if let appState = appStateController {
                appState.chartSettingsChanged = true
                appState.chartSettingsChanges |= ChartSettingsChangeEnum.showLinesChanged.rawValue
            }

        case "showValues":
            UserDefaultsRepository.showValues.value = sender.isOn

        case "showAbsorption":
            UserDefaultsRepository.showAbsorption.value = sender.isOn

        case "showDIALines":
            UserDefaultsRepository.showDIALines.value = sender.isOn
            if let appState = appStateController {
                appState.chartSettingsChanged = true
                appState.chartSettingsChanges |= ChartSettingsChangeEnum.showDIALinesChanged.rawValue
            }

        case "show30MinLine":
            UserDefaultsRepository.show30MinLine.value = sender.isOn
            if let appState = appStateController {
                appState.chartSettingsChanged = true
                appState.chartSettingsChanges |= ChartSettingsChangeEnum.show30MinLineChanged.rawValue
            }

        case "showMinus24hLine":
            UserDefaultsRepository.showMinus24hLine.value = sender.isOn
            if let appState = appStateController {
                appState.chartSettingsChanged = true
                appState.chartSettingsChanges |= ChartSettingsChangeEnum.showMinus24hLineChanged.rawValue
            }

        case "showMidnightLines":
            UserDefaultsRepository.showMidnightLines.value = sender.isOn
            if let appState = appStateController {
                appState.chartSettingsChanged = true
                appState.chartSettingsChanges |= ChartSettingsChangeEnum.showMidnightLinesChanged.rawValue
            }

        case "smallGraphTreatments":
            UserDefaultsRepository.smallGraphTreatments.value = sender.isOn

        default:
            break
        }
    }

    // MARK: - Stepper handling

    @objc private func stepperChanged(_ sender: UIStepper) {
        guard let id = sender.accessibilityIdentifier else { return }
        let value = sender.value

        switch id {
        case "smallGraphHeight":
            UserDefaultsRepository.smallGraphHeight.value = Int(value)
            if let appState = appStateController {
                appState.chartSettingsChanged = true
                appState.chartSettingsChanges |= ChartSettingsChangeEnum.smallGraphHeight.rawValue
            }

        case "predictionToLoad":
            UserDefaultsRepository.predictionToLoad.value = value

        case "minBGScale":
            UserDefaultsRepository.minBGScale.value = Float(value)

        case "minBasalScale":
            UserDefaultsRepository.minBasalScale.value = value

        case "lowLine":
            // Snap to nearest multiple of 10 to avoid odd values (e.g. 141) when stepper value has changed over time.
            var snapped = (value / 10.0).rounded() * 10.0
            if snapped < 20 { snapped = 20 }
            if snapped > 100 { snapped = 100 }
            sender.value = snapped
            UserDefaultsRepository.lowLine.value = Float(snapped)
            if let appState = appStateController {
                appState.chartSettingsChanged = true
                appState.chartSettingsChanges |= ChartSettingsChangeEnum.lowLineChanged.rawValue
            }

        case "targetLine":
            UserDefaultsRepository.targetLine.value = Float(value)
            if let appState = appStateController {
                appState.chartSettingsChanged = true
                appState.chartSettingsChanges |= ChartSettingsChangeEnum.targetLineChanged.rawValue
            }

        case "highLine":
            // Snap to nearest multiple of 10 to avoid odd values.
            var snapped = (value / 10.0).rounded() * 10.0
            if snapped < 120 { snapped = 120 }
            if snapped > 300 { snapped = 300 }
            sender.value = snapped
            UserDefaultsRepository.highLine.value = Float(snapped)
            if let appState = appStateController {
                appState.chartSettingsChanged = true
                appState.chartSettingsChanges |= ChartSettingsChangeEnum.highLineChanged.rawValue
            }

        case "downloadDays":
            UserDefaultsRepository.downloadDays.value = Int(value)

        default:
            break
        }

        // Update the visible label for this stepper's cell.
        if let indexPath = indexPathForStepper(sender),
           let cell = tableView.cellForRow(at: indexPath) {
            switch id {
            case "smallGraphHeight":
                cell.detailTextLabel?.text = "\(Int(sender.value))"
            case "predictionToLoad":
                cell.detailTextLabel?.text = String(format: "%.2f", sender.value)
            case "minBGScale":
                cell.detailTextLabel?.text = Localizer.toDisplayUnits(String(sender.value))
            case "minBasalScale":
                cell.detailTextLabel?.text = String(format: "%.1f", sender.value)
            case "lowLine", "targetLine", "highLine":
                cell.detailTextLabel?.text = Localizer.toDisplayUnits(String(sender.value))
            case "downloadDays":
                cell.detailTextLabel?.text = "\(Int(sender.value))"
            default:
                break
            }
        }
    }

    private func indexPathForStepper(_ stepper: UIStepper) -> IndexPath? {
        let point = stepper.convert(CGPoint.zero, to: tableView)
        return tableView.indexPathForRow(at: point)
    }
}
