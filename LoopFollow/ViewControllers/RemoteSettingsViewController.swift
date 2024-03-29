//
//  RemoteSettingsViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2024-03-22.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import UIKit
import Eureka
import EventKit
import EventKitUI

class RemoteSettingsViewController: FormViewController {
    
    var mealViewController: MealViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Check and apply user preference for dark mode
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
        
        // Build and configure advanced settings
        buildAdvancedSettings()
        
        // Reload the form initially
        reloadForm()
    }
    
    func reloadForm() {
        // Check if the switch for hiding Remote Bolus is enabled
        let hideBolus = Condition.function([], { _ in
            return UserDefaultsRepository.hideRemoteBolus.value
        })

        // Find the "RemoteMealBolus" row
        if let remoteMealBolusRow = form.rowBy(tag: "RemoteMealBolus") as? TextRow {
            remoteMealBolusRow.hidden = hideBolus
            remoteMealBolusRow.evaluateHidden()
        }
        
        // Find the "RemoteBolus" row
        if let remoteMealBolusRow = form.rowBy(tag: "RemoteBolus") as? TextRow {
            remoteMealBolusRow.hidden = hideBolus
            remoteMealBolusRow.evaluateHidden()
        }

        // Find the "RemoteMeal" row
        if let remoteMealRow = form.rowBy(tag: "RemoteMeal") as? TextRow {
            remoteMealRow.hidden = Condition.function([], { _ in
                return !UserDefaultsRepository.hideRemoteBolus.value
            })
            remoteMealRow.evaluateHidden()
        }

        // Check if the switch for hiding Custom Actions is enabled
        let hideCustomActions = Condition.function([], { _ in
            return UserDefaultsRepository.hideRemoteCustomActions.value
        })

        // Find the "customActions" row
        if let customActionsRow = form.rowBy(tag: "customActions") {
            customActionsRow.hidden = hideCustomActions
            customActionsRow.evaluateHidden()
        }

        // Find the "RemoteCustomActions" row
        if let remoteCustomActionsRow = form.rowBy(tag: "RemoteCustomActions") {
            remoteCustomActionsRow.hidden = hideCustomActions
            remoteCustomActionsRow.evaluateHidden()
        }

        // Reload the form to reflect the changes
        tableView?.reloadData()
    }

    
    private func buildAdvancedSettings() {
        // Define the section
        let remoteCommandsSection = Section(header: "Twilio Settings", footer: "") {
            $0.hidden = Condition.function(["method"], { form in
                // Retrieve the value of the segmented row
                guard let methodRow = form.rowBy(tag: "method") as? SegmentedRow<String>,
                      let selectedOption = methodRow.value else {
                    return true // Default to hiding if there's no selected value
                }
                // Return true to hide the section if "iOS Shortcuts" is selected
                return selectedOption != "SMS API"
            })
        }
        
        // Add rows to the section
        remoteCommandsSection
        <<< TextRow("twilioSID"){ row in
            row.title = "Twilio SID"
            row.cell.textField.placeholder = "EnterSID"
            if (UserDefaultsRepository.twilioSIDString.value != "") {
                let maskedSecret = String(repeating: "*", count: UserDefaultsRepository.twilioSIDString.value.count)
                row.value = maskedSecret
            }
        }.onChange { row in
            UserDefaultsRepository.twilioSIDString.value = row.value ?? ""
        }
        <<< TextRow("twilioSecret"){ row in
            row.title = "Twilio Secret"
            row.cell.textField.placeholder = "EnterSecret"
            if (UserDefaultsRepository.twilioSecretString.value != "") {
                let maskedSecret = String(repeating: "*", count: UserDefaultsRepository.twilioSecretString.value.count)
                row.value = maskedSecret
            }
        }.onChange { row in
            UserDefaultsRepository.twilioSecretString.value = row.value ?? ""
            
        }
        <<< TextRow("twilioFromNumberString"){ row in
            row.title = "Twilio from Number"
            row.cell.textField.placeholder = "EnterFromNumber"
            row.cell.textField.keyboardType = UIKeyboardType.phonePad
            if (UserDefaultsRepository.twilioFromNumberString.value != "") {
                row.value = UserDefaultsRepository.twilioFromNumberString.value
            }
        }.onChange { row in
            UserDefaultsRepository.twilioFromNumberString.value =  row.value ?? ""
        }
        
        <<< TextRow("twilioToNumberString"){ row in
            row.title = "Twilio to Number"
            row.cell.textField.placeholder = "EnterToNumber"
            row.cell.textField.keyboardType = UIKeyboardType.phonePad
            if (UserDefaultsRepository.twilioToNumberString.value != "") {
                row.value = UserDefaultsRepository.twilioToNumberString.value
            }
        }.onChange { row in
            UserDefaultsRepository.twilioToNumberString.value =  row.value ?? ""
        }
        
        let shortcutsSection = Section(header: "Shortcut names • Textstrings examples", footer: "When iOS Shortcuts are selected as Remote command method, the entries made will be forwarded as a text string when you press 'Send Remote Meal/Bolus/Override/Temp Target buttons. (The text strings can be used as input in your shortcuts).\n\nYou need to create and customize your own iOS shortcuts and use the pre defined names listed above.") {
            $0.hidden = Condition.function(["method"], { form in
                // Retrieve the value of the segmented row
                guard let methodRow = form.rowBy(tag: "method") as? SegmentedRow<String>,
                      let selectedOption = methodRow.value else {
                    return true // Default to hiding if there's no selected value
                }
                // Return true to hide the section if "iOS Shortcuts" is selected
                return selectedOption != "iOS Shortcuts"
            })
        }
        
        // Add rows to the section
        shortcutsSection
        
        <<< TextRow("RemoteMealBolus"){ row in
            row.title = ""
            row.value = "Remote Meal • Meal_Carbs_25g_Fat_15g_Protein_10g_Note_Testmeal_Insulin_1.0"
            row.cellSetup { cell, row in
                cell.textLabel?.font = UIFont.systemFont(ofSize: 10)
            }
        }
        
        <<< TextRow("RemoteMeal"){ row in
            row.title = ""
            row.value = "Remote Meal • Meal_Carbs_25g_Fat_15g_Protein_10g_Note_Testmeal"
            row.cellSetup { cell, row in
                cell.textLabel?.font = UIFont.systemFont(ofSize: 10)
            }
        }
        <<< TextRow("RemoteBolus"){ row in
            row.title = ""
            row.value = "Remote Bolus • Bolus_0.6"
            row.cellSetup { cell, row in
                cell.textLabel?.font = UIFont.systemFont(ofSize: 10)
            }
        }
        <<< TextRow("RemoteOverride"){ row in
            row.title = ""
            row.value = "Remote Override • Override_🎉 Partytime"
            row.cellSetup { cell, row in
                cell.textLabel?.font = UIFont.systemFont(ofSize: 10)
            }
        }
        <<< TextRow("RemoteTempTarget"){ row in
            row.title = ""
            row.value = "Remote Temp Target • TempTarget_🏃‍♂️ Exercise"
            row.cellSetup { cell, row in
                cell.textLabel?.font = UIFont.systemFont(ofSize: 10)
            }
        }
        
        <<< TextRow("RemoteCustomActions"){ row in
            row.title = ""
            row.value = "Remote Custom Action • CustomAction_🍿 Popcorn"
            row.cellSetup { cell, row in
                cell.textLabel?.font = UIFont.systemFont(ofSize: 10)
            }
        }
        
        // Add the section to the form
        form
        +++ Section(header: "Select remote commands method", footer: "")
        <<< SegmentedRow<String>("method") { row in
            row.title = ""
            row.options = ["iOS Shortcuts", "SMS API"]
            row.value = UserDefaultsRepository.method.value
        }.onChange { row in
            guard let value = row.value else { return }
            UserDefaultsRepository.method.value = value
        }
        
        +++ remoteCommandsSection
        
        +++ shortcutsSection
        
        +++ Section(header: "Guardrails and security", footer: "")
        
        <<< StepperRow("maxCarbs") { row in
            row.title = "Max Carbs (g)"
            row.cell.stepper.stepValue = 5
            row.cell.stepper.minimumValue = 0
            row.cell.stepper.maximumValue = 200
            row.value = Double(UserDefaultsRepository.maxCarbs.value)
            row.displayValueFor = { value in
                guard let value = value else { return nil }
                return "\(Int(value))"
            }
        }.onChange { [weak self] row in
            guard let value = row.value else { return }
            UserDefaultsRepository.maxCarbs.value = Int(value)
        }
        
        <<< StepperRow("maxBolus") { row in
            row.title = "Max Bolus (U)"
            row.cell.stepper.stepValue = 0.1
            row.cell.stepper.minimumValue = 0.1
            row.cell.stepper.maximumValue = 50
            row.value = Double(UserDefaultsRepository.maxBolus.value)
            row.displayValueFor = { value in
                guard let value = value else { return nil }
                // Format the value with one fraction
                return String(format: "%.1f", value)
            }
        }.onChange { [weak self] row in
            guard let value = row.value else { return }
            UserDefaultsRepository.maxBolus.value = Double(value)
        }
        
        form +++ Section("Advanced functions (App Restart needed)")
            <<< SegmentedRow<String>("hideRemoteBolus") { row in
                row.title = "Bolus Actions"
                row.options = ["Show", "Hide"]
                row.value = UserDefaultsRepository.hideRemoteBolus.value ? "Hide" : "Show"
            }.cellSetup { cell, _ in
                cell.segmentedControl.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    cell.segmentedControl.widthAnchor.constraint(equalTo: cell.widthAnchor, multiplier: 0.5) // Adjust multiplier as needed
                ])
            }.onChange { [weak self] row in
                guard let value = row.value else { return }
                UserDefaultsRepository.hideRemoteBolus.value = value == "Hide"
                
                // Reload the form after the value changes
                self?.reloadForm()
            }
            
            <<< SegmentedRow<String>("hideRemoteCustom") { row in
                row.title = "Custom Actions"
                row.options = ["Show", "Hide"]
                row.value = UserDefaultsRepository.hideRemoteCustomActions.value ? "Hide" : "Show"
            }.cellSetup { cell, _ in
                cell.segmentedControl.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    cell.segmentedControl.widthAnchor.constraint(equalTo: cell.widthAnchor, multiplier: 0.5) // Adjust multiplier as needed
                ])
            }.onChange { [weak self] row in
                guard let value = row.value else { return }
                UserDefaultsRepository.hideRemoteCustomActions.value = value == "Hide"
                
                // Reload the form after the value changes
                self?.reloadForm()
            }
        
        +++ Section(header: "Presets Settings", footer: "Add the presets you would like to be able to choose from in respective views picker. Separate them by comma + blank space.  Example: Override 1, Override 2, Override 3")
        
        <<< TextRow("overrides"){ row in
            row.title = "Overrides:"
            row.value = UserDefaultsRepository.overrideString.value
        }.onChange { row in
            guard let value = row.value else { return }
            UserDefaultsRepository.overrideString.value = value
        }
        
        <<< TextRow("temptargets"){ row in
            row.title = "Temp Targets:"
            row.value = UserDefaultsRepository.tempTargetsString.value
        }.onChange { row in
            guard let value = row.value else { return }
            UserDefaultsRepository.tempTargetsString.value = value
        }
        
        <<< TextRow("customactions"){ row in
            row.title = "Custom Actions:"
            row.value = UserDefaultsRepository.customActionsString.value
        }.onChange { row in
            guard let value = row.value else { return }
            UserDefaultsRepository.customActionsString.value = value
        }
        +++ ButtonRow() {
            $0.title = "DONE"
        }.onCellSelection { (row, arg)  in
            self.dismiss(animated:true, completion: nil)
        }
    }
}
