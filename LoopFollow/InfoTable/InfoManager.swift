//
//  InfoManager.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-07-11.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import Foundation
import UIKit
import HealthKit

class InfoManager {
    var tableData: [InfoData]
    weak var tableView: UITableView?

    init(tableView: UITableView) {
        self.tableData = InfoType.allCases.map { InfoData(name: $0.name) }
        self.tableView = tableView
    }
/*
    func updateInfoData(type: InfoType, value: String, unit: String? = nil) {
        let displayValue = unit != nil ? "\(value) \(unit!)" : value
        tableData[type.rawValue].value = displayValue
        tableView?.reloadData()
    }
*/
    func updateInfoData(type: InfoType, value: String? = nil, unit: String? = nil) {
        let displayValue: String

        // Set a default value for the "Override" case
        if type == .override {
            if let persistentNote = Observable.shared.override.value, !persistentNote.isEmpty {
                displayValue = unit != nil ? "\(persistentNote) \(unit!)" : persistentNote
            } else {
                displayValue = value?.isEmpty == false ? (unit != nil ? "\(value!) \(unit!)" : value!) : "Normal profil"
            }
        } else {
            displayValue = unit != nil ? "\(value ?? "") \(unit!)" : (value ?? "")
        }

        tableData[type.rawValue].value = displayValue
        tableView?.reloadData()
    }

    func updateInfoData(type: InfoType, value: HKQuantity, unit: String? = nil) {
        let formattedValue = Localizer.formatQuantity(value)
        updateInfoData(type: type, value: formattedValue, unit: unit)
    }

    func updateInfoData(type: InfoType, firstValue: HKQuantity, secondValue: HKQuantity, separator: InfoDataSeparator, unit: String? = nil) {
        let formattedFirstValue = Localizer.formatQuantity(firstValue)
        let formattedSecondValue = Localizer.formatQuantity(secondValue)
        if formattedFirstValue != formattedSecondValue {
            let combinedValue = "\(formattedFirstValue) \(separator.rawValue) \(formattedSecondValue)"
            updateInfoData(type: type, value: combinedValue, unit: unit)
        } else {
            updateInfoData(type: type, value: formattedFirstValue, unit: unit)
        }
    }

    func updateInfoData(type: InfoType, value: Double, maxFractionDigits: Int = 1, minFractionDigits: Int = 0, unit: String? = nil) {
        let formattedValue = Localizer.formatToLocalizedString(value, maxFractionDigits: maxFractionDigits, minFractionDigits: minFractionDigits)
        updateInfoData(type: type, value: formattedValue, unit: unit)
    }

    func updateInfoData(type: InfoType, value: Double, enactedValue: Double, separator: InfoDataSeparator, maxFractionDigits: Int = 1, minFractionDigits: Int = 0, unit: String? = nil) {
        let formattedValue = Localizer.formatToLocalizedString(value, maxFractionDigits: maxFractionDigits, minFractionDigits: minFractionDigits)
        let formattedEnactedValue = Localizer.formatToLocalizedString(enactedValue, maxFractionDigits: maxFractionDigits, minFractionDigits: minFractionDigits)
        let combinedValue = "\(formattedValue) \(separator.rawValue) \(formattedEnactedValue)"
        updateInfoData(type: type, value: combinedValue, unit: unit)
    }

    func updateInfoData(type: InfoType, value: Metric, unit: String? = nil) {
        let formattedValue = value.formattedValue()
        let displayValue = unit != nil ? "\(formattedValue) \(unit!)" : formattedValue
        updateInfoData(type: type, value: displayValue)
    }
    
    func updateInfoDataForAF(value: Double) {
        let formattedValue = Localizer.formatToLocalizedString(value, maxFractionDigits: 2, minFractionDigits: 2)
        updateInfoData(type: .af, value: formattedValue, unit: nil)
    }
    
    func updateInfoDataForSMBRatio(value: Double) {
        let formattedValue = Localizer.formatToLocalizedString(value, maxFractionDigits: 2, minFractionDigits: 2)
        updateInfoData(type: .smbRatio, value: formattedValue, unit: nil)
    }
    
    func clearInfoData(type: InfoType) {
        // Prevent clearing the default value for .override
        if type == .override {
            if let persistentNote = Observable.shared.override.value, !persistentNote.isEmpty {
                tableData[type.rawValue].value = persistentNote // Use the persistent note if available
            } else {
                tableData[type.rawValue].value = "Normal profil" // Fallback to "Normal profil"
            }
        } else {
            tableData[type.rawValue].value = "N/A"
        }
        tableView?.reloadData()
    }

    func clearInfoData(types: [InfoType]) {
        for type in types {
            // Prevent clearing the default value for .override
            if type == .override {
                if let persistentNote = Observable.shared.override.value, !persistentNote.isEmpty {
                    tableData[type.rawValue].value = persistentNote // Use the persistent note if available
                } else {
                    tableData[type.rawValue].value = "Normal profil" // Fallback to "Normal profil"
                }
            } else {
                tableData[type.rawValue].value = "N/A"
            }
        }
        tableView?.reloadData()
    }

    func numberOfRows() -> Int {
        return UserDefaultsRepository.infoSort.value.filter { UserDefaultsRepository.infoVisible.value[$0] }.count
    }

    func dataForIndexPath(_ indexPath: IndexPath) -> InfoData? {
        let sortedAndVisibleIndexes = UserDefaultsRepository.infoSort.value.filter { UserDefaultsRepository.infoVisible.value[$0] }

        guard indexPath.row < sortedAndVisibleIndexes.count else {
            return nil
        }

        let infoIndex = sortedAndVisibleIndexes[indexPath.row]

        guard infoIndex < tableData.count else {
            return nil
        }

        return tableData[infoIndex]
    }
}
