//
//  GeneralSetingsViewController.swift
//  LoopFollow
//
//  Created by Jose Paredes on 7/16/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//

import Foundation
import UIKit
import EventKit
import EventKitUI

class GeneralSettingsViewController: ThemedViewController, UITableViewDataSource, UITableViewDelegate {
    
    var appStateController: AppStateController?
    
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    
    // Background color used for section "cards", mirroring other settings views.
    private let sectionBackgroundColor = UIColor.systemGray.withAlphaComponent(0.1)
    
    private enum Section: Int, CaseIterable {
        case appSettings
        case displaySettings
        case speakSettings
    }
    
    private enum AppRow: Int, CaseIterable {
        case appBadge
        case persistentNotification
    }
    
    private enum DisplayRow: Int, CaseIterable {
        case forceDarkMode
        case showStats
        case useIFCC
        case showSmallGraph
        case colorBGText
        case screenLock
        case showDisplayName
    }
    
    private enum SpeakRow {
        case speakBG
        case language
        case always
        case low
        case proactiveLow
        case lowLimit
        case fastDropDelta
        case high
        case highLimit
    }
    
    // Keep a reference to the "Speak BG" switch so it can be updated when the app enters the foreground.
    private weak var speakBGSwitch: UISwitch?
    
    // Compute which rows should be visible in the "Läs upp BG" section based on current settings.
    private var visibleSpeakRows: [SpeakRow] {
        let speakBGOn = UserDefaultsRepository.speakBG.value
        let alwaysOn = UserDefaultsRepository.speakBGAlways.value
        let lowOn = UserDefaultsRepository.speakLowBG.value
        let proactiveOn = UserDefaultsRepository.speakProactiveLowBG.value
        let highOn = UserDefaultsRepository.speakHighBG.value
        
        var rows: [SpeakRow] = [.speakBG]
        
        if speakBGOn {
            rows.append(.language)
            rows.append(.always)
            
            if !alwaysOn {
                rows.append(.low)
                rows.append(.proactiveLow)
                rows.append(.high)
                
                if lowOn || proactiveOn {
                    rows.append(.lowLimit)
                }
                
                if proactiveOn {
                    rows.append(.fastDropDelta)
                }
                
                if highOn || proactiveOn {
                    rows.append(.highLimit)
                }
            }
        }
        
        return rows
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Allmänna inställningar"
        
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
        
        // Observe when app enters foreground to sync "Speak BG" switch
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAppWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionKind = Section(rawValue: section) else { return 0 }
        switch sectionKind {
        case .appSettings:
            return AppRow.allCases.count
        case .displaySettings:
            return DisplayRow.allCases.count
        case .speakSettings:
            return visibleSpeakRows.count
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sectionKind = Section(rawValue: section) else { return nil }
        switch sectionKind {
        case .appSettings:
            return "Appinställningar"
        case .displaySettings:
            return "Visningsinställningar"
        case .speakSettings:
            return "Läs upp BG inställningar"
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sectionKind = Section(rawValue: indexPath.section) else {
            return UITableViewCell(style: .default, reuseIdentifier: "Cell")
        }
        
        switch sectionKind {
        case .appSettings:
            let rowKind = AppRow(rawValue: indexPath.row)!
            let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell") ?? UITableViewCell(style: .default, reuseIdentifier: "SwitchCell")
            cell.selectionStyle = .none
            
            let toggle = UISwitch()
            toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
            
            switch rowKind {
            case .appBadge:
                cell.textLabel?.text = "Visa glukos som app-bricka"
                toggle.isOn = UserDefaultsRepository.appBadge.value
                toggle.accessibilityIdentifier = "appBadge"
            case .persistentNotification:
                cell.textLabel?.text = "Beständiga notiser"
                toggle.isOn = UserDefaultsRepository.persistentNotification.value
                toggle.accessibilityIdentifier = "persistentNotification"
            }
            
            cell.accessoryView = toggle
            return cell
            
        case .displaySettings:
            let rowKind = DisplayRow(rawValue: indexPath.row)!
            let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell") ?? UITableViewCell(style: .default, reuseIdentifier: "SwitchCell")
            cell.selectionStyle = .none
            
            let toggle = UISwitch()
            toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
            
            switch rowKind {
            case .forceDarkMode:
                cell.textLabel?.text = "Forcera mörkt läge (omstart)"
                toggle.isOn = UserDefaultsRepository.forceDarkMode.value
                toggle.accessibilityIdentifier = "forceDarkMode"
            case .showStats:
                cell.textLabel?.text = "Visa statistik"
                toggle.isOn = UserDefaultsRepository.showStats.value
                toggle.accessibilityIdentifier = "showStats"
            case .useIFCC:
                cell.textLabel?.text = "Använd IFCC A1C"
                toggle.isOn = UserDefaultsRepository.useIFCC.value
                toggle.accessibilityIdentifier = "useIFCC"
            case .showSmallGraph:
                cell.textLabel?.text = "Visa liten graf"
                toggle.isOn = UserDefaultsRepository.showSmallGraph.value
                toggle.accessibilityIdentifier = "showSmallGraph"
            case .colorBGText:
                cell.textLabel?.text = "Färglägg BG-text"
                toggle.isOn = UserDefaultsRepository.colorBGText.value
                toggle.accessibilityIdentifier = "colorBGText"
            case .screenLock:
                cell.textLabel?.text = "Håll skärmen aktiv"
                toggle.isOn = UserDefaultsRepository.screenlockSwitchState.value
                toggle.accessibilityIdentifier = "screenlockSwitchState"
            case .showDisplayName:
                cell.textLabel?.text = "Visa namn"
                toggle.isOn = UserDefaultsRepository.showDisplayName.value
                toggle.accessibilityIdentifier = "showDisplayName"
            }
            
            cell.accessoryView = toggle
            return cell
            
        case .speakSettings:
            let rowKind = visibleSpeakRows[indexPath.row]
            
            switch rowKind {
            case .speakBG:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell") ?? UITableViewCell(style: .default, reuseIdentifier: "SwitchCell")
                cell.textLabel?.text = "Läs upp glukos"
                cell.selectionStyle = .none
                
                let toggle = UISwitch()
                toggle.isOn = UserDefaultsRepository.speakBG.value
                toggle.addTarget(self, action: #selector(speakBGChanged(_:)), for: .valueChanged)
                speakBGSwitch = toggle
                cell.accessoryView = toggle
                return cell
                
            case .language:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ValueCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "ValueCell")
                cell.textLabel?.text = "Talat språk"
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
                let code = UserDefaultsRepository.speakLanguage.value
                cell.detailTextLabel?.text = languageDisplayName(for: code)
                return cell
                
            case .always:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell") ?? UITableViewCell(style: .default, reuseIdentifier: "SwitchCell")
                cell.textLabel?.text = "Alltid"
                cell.selectionStyle = .none
                
                let toggle = UISwitch()
                toggle.isOn = UserDefaultsRepository.speakBGAlways.value
                toggle.addTarget(self, action: #selector(speakBGAlwaysChanged(_:)), for: .valueChanged)
                cell.accessoryView = toggle
                return cell
                
            case .low, .proactiveLow, .high:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell") ?? UITableViewCell(style: .default, reuseIdentifier: "SwitchCell")
                cell.selectionStyle = .none
                let toggle = UISwitch()
                
                switch rowKind {
                case .low:
                    cell.textLabel?.text = "Lågt"
                    toggle.isOn = UserDefaultsRepository.speakLowBG.value
                    toggle.addTarget(self, action: #selector(speakLowChanged(_:)), for: .valueChanged)
                case .proactiveLow:
                    cell.textLabel?.text = "Proaktivt lågt"
                    toggle.isOn = UserDefaultsRepository.speakProactiveLowBG.value
                    toggle.addTarget(self, action: #selector(speakProactiveLowChanged(_:)), for: .valueChanged)
                case .high:
                    cell.textLabel?.text = "Högt"
                    toggle.isOn = UserDefaultsRepository.speakHighBG.value
                    toggle.addTarget(self, action: #selector(speakHighChanged(_:)), for: .valueChanged)
                default:
                    break
                }
                
                cell.accessoryView = toggle
                return cell
                
            case .lowLimit, .fastDropDelta, .highLimit:
                let cell = tableView.dequeueReusableCell(withIdentifier: "StepperCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "StepperCell")
                cell.selectionStyle = .none
                
                let stepper = UIStepper()
                stepper.addTarget(self, action: #selector(stepperChanged(_:)), for: .valueChanged)
                
                switch rowKind {
                case .lowLimit:
                    cell.textLabel?.text = "Glukos lägre än"
                    stepper.minimumValue = 40
                    stepper.maximumValue = 108
                    stepper.stepValue = 1
                    stepper.tag = 1
                    stepper.value = Double(UserDefaultsRepository.speakLowBGLimit.value)
                    cell.detailTextLabel?.text = Localizer.toDisplayUnits(String(stepper.value))
                case .fastDropDelta:
                    cell.textLabel?.text = "Sjunker snabbt"
                    stepper.minimumValue = 3
                    stepper.maximumValue = 20
                    stepper.stepValue = 1
                    stepper.tag = 2
                    stepper.value = Double(UserDefaultsRepository.speakFastDropDelta.value)
                    cell.detailTextLabel?.text = Localizer.toDisplayUnits(String(stepper.value))
                case .highLimit:
                    cell.textLabel?.text = "Glukos högre än"
                    stepper.minimumValue = 140
                    stepper.maximumValue = 300
                    stepper.stepValue = 1
                    stepper.tag = 3
                    stepper.value = Double(UserDefaultsRepository.speakHighBGLimit.value)
                    cell.detailTextLabel?.text = Localizer.toDisplayUnits(String(stepper.value))
                default:
                    break
                }
                
                cell.accessoryView = stepper
                return cell
            }
        }
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
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
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let sectionKind = Section(rawValue: indexPath.section) else { return }
        
        if sectionKind == .speakSettings {
            let rowKind = visibleSpeakRows[indexPath.row]
            if case .language = rowKind {
                presentLanguagePicker()
            }
        }
    }
    
    // MARK: - Actions for switches and steppers
    
    @objc private func switchChanged(_ sender: UISwitch) {
        switch sender.accessibilityIdentifier {
        case "appBadge":
            UserDefaultsRepository.appBadge.value = sender.isOn
            if let appState = appStateController {
                appState.generalSettingsChanged = true
                appState.generalSettingsChanges |= GeneralSettingsChangeEnum.appBadgeChange.rawValue
            }
        case "persistentNotification":
            UserDefaultsRepository.persistentNotification.value = sender.isOn
        case "forceDarkMode":
            UserDefaultsRepository.forceDarkMode.value = sender.isOn
        case "showStats":
            UserDefaultsRepository.showStats.value = sender.isOn
            if let appState = appStateController {
                appState.generalSettingsChanged = true
                appState.generalSettingsChanges |= GeneralSettingsChangeEnum.showStatsChange.rawValue
            }
        case "useIFCC":
            UserDefaultsRepository.useIFCC.value = sender.isOn
            if let appState = appStateController {
                appState.generalSettingsChanged = true
                appState.generalSettingsChanges |= GeneralSettingsChangeEnum.useIFCCChange.rawValue
            }
        case "showSmallGraph":
            UserDefaultsRepository.showSmallGraph.value = sender.isOn
            if let appState = appStateController {
                appState.generalSettingsChanged = true
                appState.generalSettingsChanges |= GeneralSettingsChangeEnum.showSmallGraphChange.rawValue
            }
        case "colorBGText":
            UserDefaultsRepository.colorBGText.value = sender.isOn
            if let appState = appStateController {
                appState.generalSettingsChanged = true
                appState.generalSettingsChanges |= GeneralSettingsChangeEnum.colorBGTextChange.rawValue
            }
        case "screenlockSwitchState":
            UserDefaultsRepository.screenlockSwitchState.value = sender.isOn
        case "showDisplayName":
            UserDefaultsRepository.showDisplayName.value = sender.isOn
            if let appState = appStateController {
                appState.generalSettingsChanged = true
                appState.generalSettingsChanges |= GeneralSettingsChangeEnum.showDisplayNameChange.rawValue
            }
        default:
            break
        }
    }
    
    @objc private func speakBGChanged(_ sender: UISwitch) {
        UserDefaultsRepository.speakBG.value = sender.isOn
        updateSpeakBGSettingsVisibility()
    }
    
    @objc private func speakBGAlwaysChanged(_ sender: UISwitch) {
        UserDefaultsRepository.speakBGAlways.value = sender.isOn
        updateSpeakBGSettingsVisibility()
    }
    
    @objc private func speakLowChanged(_ sender: UISwitch) {
        UserDefaultsRepository.speakLowBG.value = sender.isOn
        handleLowProactiveLowToggle(currentIsLow: true, value: sender.isOn)
    }
    
    @objc private func speakProactiveLowChanged(_ sender: UISwitch) {
        UserDefaultsRepository.speakProactiveLowBG.value = sender.isOn
        handleLowProactiveLowToggle(currentIsLow: false, value: sender.isOn)
    }
    
    @objc private func speakHighChanged(_ sender: UISwitch) {
        UserDefaultsRepository.speakHighBG.value = sender.isOn
        updateSpeakBGSettingsVisibility()
    }
    
    @objc private func stepperChanged(_ sender: UIStepper) {
        let value = sender.value
        switch sender.tag {
        case 1:
            UserDefaultsRepository.speakLowBGLimit.value = Float(value)
        case 2:
            UserDefaultsRepository.speakFastDropDelta.value = Float(value)
        case 3:
            UserDefaultsRepository.speakHighBGLimit.value = Float(value)
        default:
            break
        }
        
        // Update the visible label text for this stepper's cell
        if let indexPath = indexPathForStepper(sender),
           let cell = tableView.cellForRow(at: indexPath) {
            cell.detailTextLabel?.text = Localizer.toDisplayUnits(String(value))
        }
    }
    
    private func indexPathForStepper(_ stepper: UIStepper) -> IndexPath? {
        let point = stepper.convert(CGPoint(x: 0, y: 0), to: tableView)
        return tableView.indexPathForRow(at: point)
    }
    
    // MARK: - Speak BG helpers
    
    private func languageDisplayName(for code: String?) -> String {
        switch code {
        case "en": return "Engelska"
        case "it": return "Italienska"
        case "sk": return "Slovakiska"
        case "sv": return "Svenska"
        default: return "Unknown"
        }
    }
    
    private func presentLanguagePicker() {
        let alert = UIAlertController(title: "Välj språk", message: nil, preferredStyle: .actionSheet)
        
        let codes = ["en", "it", "sk", "sv"]
        for code in codes {
            let title = languageDisplayName(for: code)
            let action = UIAlertAction(title: title, style: .default) { _ in
                UserDefaultsRepository.speakLanguage.value = code
                self.updateSpeakBGSettingsVisibility()
            }
            alert.addAction(action)
        }
        
        alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: nil))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(alert, animated: true, completion: nil)
    }
    
    private func updateSpeakBGSettingsVisibility() {
        if let sectionIndex = Section.allCases.firstIndex(of: .speakSettings) {
            tableView.reloadSections(IndexSet(integer: sectionIndex), with: .automatic)
        }
    }
    
    private func handleLowProactiveLowToggle(currentIsLow: Bool, value: Bool) {
        // Mirror the old Eureka behavior: when one of Low / Proactive Low is turned ON, the other is turned OFF.
        if value {
            if currentIsLow {
                UserDefaultsRepository.speakProactiveLowBG.value = false
            } else {
                UserDefaultsRepository.speakLowBG.value = false
            }
        }
        updateSpeakBGSettingsVisibility()
    }
    
    // MARK: - Foreground handling
    
    @objc func handleAppWillEnterForeground() {
        // Ensure the Speak BG switch reflects the current setting when app returns to foreground.
        speakBGSwitch?.isOn = UserDefaultsRepository.speakBG.value
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
    }
}
