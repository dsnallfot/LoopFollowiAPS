//
//  WatchSettingsViewController.swift
//  LoopFollow
//
//  Created by Jose Paredes on 7/16/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//

import Foundation
import UIKit
import EventKit
import EventKitUI

class WatchSettingsViewController: ThemedViewController, UITableViewDataSource, UITableViewDelegate {
    
    var appStateController: AppStateController?
    
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    
    // Background color used for section "cards", mirroring other settings views.
    private let sectionBackgroundColor = UIColor.systemGray.withAlphaComponent(0.1)
    
    private struct CalendarInfo {
        let title: String
        let identifier: String
    }
    
    private enum Section: Int, CaseIterable {
        case calendarIntegration
        case variables
    }
    
    private enum CalendarRow {
        case calendarAccessDeniedLabel
        case writeCalendarEvent
        case calendarIdentifier
        case watchLine1
        case watchLine2
    }
    
    private enum VariableRow: String, CaseIterable {
        case BG
        case DIRECTION
        case DELTA
        case IOB
        case COB
        case BASAL
        case LOOP
        case OVERRIDE
        case MINAGO
        case MIN15
    }
    
    private var calendars: [CalendarInfo] = []
    private var hasCalendarAccess: Bool = false
    private var isNightscoutEnabled: Bool = true
    
    private var calendarRows: [CalendarRow] {
        var rows: [CalendarRow] = []
        if !hasCalendarAccess {
            rows.append(.calendarAccessDeniedLabel)
        }
        rows.append(contentsOf: [
            .writeCalendarEvent,
            .calendarIdentifier,
            .watchLine1,
            .watchLine2
        ])
        return rows
    }
    
    private var variableRows: [VariableRow] {
        let all = VariableRow.allCases
        guard !all.isEmpty else { return [] }
        
        if isNightscoutEnabled {
            return all
        } else {
            // Hide Nightscout-specific variables when disabled, matching previous Eureka behavior.
            return all.filter { row in
                switch row {
                case .IOB, .COB, .BASAL, .LOOP, .OVERRIDE:
                    return false
                default:
                    return true
                }
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Kalendertrick"
        
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
        
        // Initial Nightscout state
        showHideNSDetails()
        
        // Request calendar access and load calendars accordingly
        let eventStore = EKEventStore()
        eventStore.requestCalendarAccess { [weak self] (granted, error) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.hasCalendarAccess = granted
                if granted {
                    self.reloadCalendars()
                }
                self.tableView.reloadData()
                self.showHideNSDetails()
            }
        }
    }
    
    // MARK: - Calendar loading
    
    private func reloadCalendars() {
        let store = EKEventStore()
        let ekCalendars = store.calendars(for: .event)
        calendars = ekCalendars.map { cal in
            CalendarInfo(title: cal.title, identifier: cal.calendarIdentifier)
        }
    }
    
    // MARK: - Nightscout visibility
    
    func showHideNSDetails() {
        isNightscoutEnabled = IsNightscoutEnabled()
        
        if let variablesSectionIndex = Section.allCases.firstIndex(of: .variables) {
            tableView.reloadSections(IndexSet(integer: variablesSectionIndex), with: .automatic)
        } else {
            tableView.reloadData()
        }
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionKind = Section(rawValue: section) else { return 0 }
        switch sectionKind {
        case .calendarIntegration:
            return calendarRows.count
        case .variables:
            return variableRows.count
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sectionKind = Section(rawValue: section) else { return nil }
        switch sectionKind {
        case .calendarIntegration:
            return "Kalenderintegration"
        case .variables:
            return "Tillgängliga variabler"
        }
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let sectionKind = Section(rawValue: section) else { return nil }
        switch sectionKind {
        case .calendarIntegration:
            return "Add the Apple calendar complication to your Apple Watch face or Carplay to see BG readings. Create a new calendar called 'Follow' and modify the calendar settings in the iPhone Watch/Carplay App to only display the Follow calendar on your watch or car. It is important to use a new calendar because this will delete other events on the same calendar. Edit Line 1 and Line 2 to be displayed using variables below that will be replaced by the values. Other text entered will not be replaced."
        case .variables:
            return nil
        }
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sectionKind = Section(rawValue: indexPath.section) else {
            return UITableViewCell(style: .default, reuseIdentifier: "Cell")
        }
        
        switch sectionKind {
        case .calendarIntegration:
            let rowKind = calendarRows[indexPath.row]
            switch rowKind {
            case .calendarAccessDeniedLabel:
                let cell = tableView.dequeueReusableCell(withIdentifier: "DeniedCell")
                    ?? UITableViewCell(style: .default, reuseIdentifier: "DeniedCell")
                cell.textLabel?.text = "Kalenderaccess nekades"
                cell.textLabel?.textColor = .red
                cell.selectionStyle = .none
                cell.accessoryView = nil
                cell.accessoryType = .none
                return cell
                
            case .writeCalendarEvent:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell")
                    ?? UITableViewCell(style: .default, reuseIdentifier: "SwitchCell")
                cell.textLabel?.text = "Spara BG till kalender"
                cell.selectionStyle = .none
                
                let toggle = UISwitch()
                toggle.isOn = UserDefaultsRepository.writeCalendarEvent.value
                toggle.addTarget(self, action: #selector(writeCalendarEventChanged(_:)), for: .valueChanged)
                cell.accessoryView = toggle
                cell.accessoryType = .none
                return cell
                
            case .calendarIdentifier:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ValueCell")
                    ?? UITableViewCell(style: .value1, reuseIdentifier: "ValueCell")
                cell.textLabel?.text = "Kalender"
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
                
                let currentId = UserDefaultsRepository.calendarIdentifier.value

                if !currentId.isEmpty,
                   let match = calendars.first(where: {
                       $0.identifier == currentId || $0.title.range(of: currentId) != nil
                   }) {
                    cell.detailTextLabel?.text = match.title
                } else {
                    cell.detailTextLabel?.text = " - "
                }
                return cell
                
            case .watchLine1:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ValueCell")
                    ?? UITableViewCell(style: .value1, reuseIdentifier: "ValueCell")
                cell.textLabel?.text = "Linje 1"
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
                let value = UserDefaultsRepository.watchLine1.value ?? ""
                cell.detailTextLabel?.text = value.isEmpty ? " " : value
                return cell
                
            case .watchLine2:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ValueCell")
                    ?? UITableViewCell(style: .value1, reuseIdentifier: "ValueCell")
                cell.textLabel?.text = "Linje 2"
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
                let value = UserDefaultsRepository.watchLine2.value ?? ""
                cell.detailTextLabel?.text = value.isEmpty ? " " : value
                return cell
            }
            
        case .variables:
            let rowKind = variableRows[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "VariableCell")
                ?? UITableViewCell(style: .default, reuseIdentifier: "VariableCell")
            cell.selectionStyle = .none
            cell.accessoryType = .none
            
            switch rowKind {
            case .BG:
                cell.textLabel?.text = "%BG% : Blood Glucose Reading"
            case .DIRECTION:
                cell.textLabel?.text = "%DIRECTION% : Dexcom Trend Arrow"
            case .DELTA:
                cell.textLabel?.text = "%DELTA% : +/- From Last Reading"
            case .IOB:
                cell.textLabel?.text = "%IOB% : Insulin on Board"
            case .COB:
                cell.textLabel?.text = "%COB% : Carbs on Board"
            case .BASAL:
                cell.textLabel?.text = "%BASAL% : Current Basal u/hr"
            case .LOOP:
                cell.textLabel?.text = "%LOOP% : Loop Status Symbol"
            case .OVERRIDE:
                cell.textLabel?.text = "%OVERRIDE% : Active Override %"
            case .MINAGO:
                cell.textLabel?.text = "%MINAGO% : Only displays for old readings"
            case .MIN15:
                cell.textLabel?.text = "%15MIN% : Display 15min trend"
            }
            
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
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let sectionKind = Section(rawValue: indexPath.section) else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        
        switch sectionKind {
        case .calendarIntegration:
            let rowKind = calendarRows[indexPath.row]
            switch rowKind {
            case .calendarIdentifier:
                presentCalendarPicker(from: indexPath)
            case .watchLine1:
                presentWatchLineEditor(title: "Linje 1",
                                        currentValue: UserDefaultsRepository.watchLine1.value ?? "") { newValue in
                    UserDefaultsRepository.watchLine1.value = newValue
                    if let cell = tableView.cellForRow(at: indexPath) {
                        cell.detailTextLabel?.text = newValue.isEmpty ? " " : newValue
                    }
                }
            case .watchLine2:
                presentWatchLineEditor(title: "Linje 2",
                                        currentValue: UserDefaultsRepository.watchLine2.value ?? "") { newValue in
                    UserDefaultsRepository.watchLine2.value = newValue
                    if let cell = tableView.cellForRow(at: indexPath) {
                        cell.detailTextLabel?.text = newValue.isEmpty ? " " : newValue
                    }
                }
            default:
                break
            }
            
        case .variables:
            break
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: - Actions
    
    @objc private func writeCalendarEventChanged(_ sender: UISwitch) {
        UserDefaultsRepository.writeCalendarEvent.value = sender.isOn
    }
    
    // MARK: - Helpers
    
    private func presentCalendarPicker(from indexPath: IndexPath) {
        guard hasCalendarAccess else {
            let alert = UIAlertController(title: "Kalenderaccess nekades",
                                          message: "Gå till Inställningar → Sekretess → Kalender för att ge Loop Follow tillgång.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
            return
        }
        
        guard !calendars.isEmpty else {
            let alert = UIAlertController(title: "Inga kalendrar",
                                          message: "Inga kalendrar hittades i Kalender-appen.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
            return
        }
        
        let alert = UIAlertController(title: "Välj kalender", message: nil, preferredStyle: .actionSheet)
        
        let currentId = UserDefaultsRepository.calendarIdentifier.value
        
        for calendar in calendars {
            let title = calendar.title
            let style: UIAlertAction.Style = (calendar.identifier == currentId) ? .destructive : .default
            
            let action = UIAlertAction(title: title, style: style) { [weak self] _ in
                guard let self = self else { return }
                UserDefaultsRepository.calendarIdentifier.value = calendar.identifier
                self.tableView.reloadRows(at: [indexPath], with: .none)
            }
            alert.addAction(action)
        }
        
        alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: nil))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX,
                                        y: view.bounds.midY,
                                        width: 0,
                                        height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(alert, animated: true, completion: nil)
    }
    
    private func presentWatchLineEditor(title: String,
                                        currentValue: String,
                                        onSave: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = currentValue
            textField.placeholder = title
        }
        
        alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Spara", style: .default, handler: { _ in
            let newValue = alert.textFields?.first?.text ?? ""
            onSave(newValue)
        }))
        
        present(alert, animated: true, completion: nil)
    }
}
