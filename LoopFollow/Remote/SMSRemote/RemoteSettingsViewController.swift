//
//  RemoteSettingsViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2024-03-22.

//

import UIKit
import Eureka
import EventKit
import EventKitUI

class RemoteSettingsViewController: ThemedFormViewController {
    weak var delegate: RemoteSettingsDelegate?
    var appStateController: AppStateController?
    
    var mealViewController: MealViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Check and apply user preference for dark mode
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
        applyTheme()
        
        // Build and configure advanced settings
        buildAdvancedSettings()
        
        // Reload the form initially
        reloadForm()
    }
    
    // This will catch both the "Klar" button dismissal and swipe-down dismissals.
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if self.isBeingDismissed || self.isMovingFromParent {
                delegate?.remoteSettingsDidUpdateMethod()
            }
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
        if let customActionsRow = form.rowBy(tag: "CustomActions") {
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
        
        let shortcutsSection = Section(header: "iOS Shortcut names • Textstrings examples", footer: "When iOS Shortcuts are selected as Remote command method, the entries made will be forwarded as a text string when you press 'Send Remote Meal/Bolus/Override/Temp Target' buttons. The '\\n' commands in the text strings create line breaks for better readability in imessage. (The text strings can be used as input in your shortcuts).\n\nYou need to create and customize your own iOS shortcuts and use the pre defined names listed above.") {
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
            row.value = "Remote Meal • Remote Meal\\nCarbs: 25.5g\\nFat: 20g\\nProtein: 15g\\nNotes: Testmeal)\\nDatum: 2024-06-02T20:03:44.849Z\\nInsulin: 1.55U\\nEntered by: Dad\\nSecret Code: S3cr3tc0d3"
            row.cellSetup { cell, row in
                cell.textLabel?.font = UIFont.systemFont(ofSize: 10)
            }
        }
        
        <<< TextRow("RemoteMeal"){ row in
            row.title = ""
            row.value = "Remote Meal • Remote Meal\\nCarbs: 25.5g\\nFat: 20g\\nProtein: 15g\\nNotes: Testmeal)\\nDatum: 2024-06-02T20:03:44.849Z\\nEntered by: Dad\\nSecret Code: S3cr3tc0d3"
            row.cellSetup { cell, row in
                cell.textLabel?.font = UIFont.systemFont(ofSize: 10)
            }
        }
        <<< TextRow("RemoteBolus"){ row in
            row.title = ""
            row.value = "Remote Bolus • Remote Bolus\\nInsulin: 0.75U\\nEntered by: Dad\\nSecret Code: S3cr3tc0d3"
            row.cellSetup { cell, row in
                cell.textLabel?.font = UIFont.systemFont(ofSize: 10)
            }
        }
        <<< TextRow("RemoteOverride"){ row in
            row.title = ""
            row.value = "Remote Override • Remote Override\\n🎉 Partytime\\nEntered by: Dad\\nSecret Code: S3cr3tc0d3"
            row.cellSetup { cell, row in
                cell.textLabel?.font = UIFont.systemFont(ofSize: 10)
            }
        }
        <<< TextRow("RemoteTempTarget"){ row in
            row.title = ""
            row.value = "Remote Temp Target • Remote Temp Target\\n🏃‍♂️ Exercise\\nEntered by: Dad\\nSecret Code: S3cr3tc0d3"
            row.cellSetup { cell, row in
                cell.textLabel?.font = UIFont.systemFont(ofSize: 10)
            }
        }
        
        <<< TextRow("RemoteCustomAction"){ row in
            row.title = ""
            row.value = "Remote Custom Action • Remote Custom Action\\n🍿 Popcorn\\nEntered by: Dad\\nSecret Code: S3cr3tc0d3"
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
        
        +++ Section(header: "Remote configuration", footer: "The Caregiver name will be shown in all remote actions messages sent on the receiving phone.\n\nThe Secret Code (max 10 characters) should be something unique, and the exact same code later needs to be entered when asked for it in an import question, when setting up the preconfigured shortcut for enacting remote actions on the receiving phone")
        
        <<< NameRow("caregivername"){ row in
            row.title = "Caregiver Name"
            row.value = UserDefaultsRepository.caregiverName.value
            row.cell.textField.placeholder = "Enter your name"
        }.onChange { row in
            guard let value = row.value else { return }
            UserDefaultsRepository.caregiverName.value = value
        }
        
        <<< TextRow("secretcode"){ row in
            row.title = "Secret Code"
            row.value = UserDefaultsRepository.remoteSecretCode.value
            row.cell.textField.placeholder = "Enter a secret code"
        }.onChange { row in
            guard let value = row.value else { return }
            let truncatedValue = String(value.prefix(10)) // Limiting to 10 characters
            row.value = truncatedValue
            UserDefaultsRepository.remoteSecretCode.value = truncatedValue
        }
        
        +++ Section(header: "Remote presets setup", footer: "Add the presets you would like to be able to choose from in respective views picker. Separate them by comma + blank space.  Example: Override 1, Override 2, Override 3")
        
        <<< TextRow("Overrides"){ row in
            row.title = "Overrides:"
            row.value = UserDefaultsRepository.overrideString.value
            row.cell.textField.placeholder = "👻 Resistance, 🤧 Sick day, 🏃‍♂️ Exercise, 😴 Nightmode"
        }.onChange { row in
            guard let value = row.value else { return }
            UserDefaultsRepository.overrideString.value = value
        }
        
        <<< TextRow("TempTargets"){ row in
            row.title = "Temp Targets:"
            row.value = UserDefaultsRepository.tempTargetsString.value
            row.cell.textField.placeholder = "Exercise, Eating soon, Low treatment"
        }.onChange { row in
            guard let value = row.value else { return }
            UserDefaultsRepository.tempTargetsString.value = value
        }
        
        <<< TextRow("CustomActions"){ row in
            row.title = "Custom Actions:"
            row.value = UserDefaultsRepository.customActionsString.value
            row.cell.textField.placeholder = "Custom Command 1, Custom Command 2, Custom Command 3"
        }.onChange { row in
            guard let value = row.value else { return }
            UserDefaultsRepository.customActionsString.value = value
        }
        
        form +++ Section("Advanced functions (App Restart needed)")
        <<< SwitchRow("hideRemoteCustom") { row in
            row.title = "Show Custom Actions" //Inverted code to make switch on = show instead of hide
            // Invert the value here for initial state
            row.value = !UserDefaultsRepository.hideRemoteCustomActions.value
        }.onChange { [weak self] row in
            guard let value = row.value else { return }
            // Invert the value again when saving
            UserDefaultsRepository.hideRemoteCustomActions.value = !value
            
            // Reload the form after the value changes
            self?.reloadForm()
        }
        
        <<< SwitchRow("hideRemoteBolus") { row in
            row.title = "Show Remote Bolus" //Inverted code to make switch on = show instead of hide
            // Invert the value here for initial state
            row.value = !UserDefaultsRepository.hideRemoteBolus.value
        }.onChange { [weak self] row in
            guard let value = row.value else { return }
            // Invert the value again when saving
            UserDefaultsRepository.hideRemoteBolus.value = !value
            
            // Reload the form after the value changes
            self?.reloadForm()
        }
        
        <<< SwitchRow("hideBolusCalc") { row in
            row.title = "Show Bolus Calculations"
            row.value = !UserDefaultsRepository.hideBolusCalc.value
            row.hidden = Condition.function(["hideRemoteBolus"], { form in
                return !((form.rowBy(tag: "hideRemoteBolus") as? SwitchRow)?.value ?? true)
            })
        }.onChange { [weak self] row in
            guard let value = row.value else { return }
            UserDefaultsRepository.hideBolusCalc.value = !value
            self?.reloadForm()
        }
        
        <<< SwitchRow("useDynCrInBolusCalc"){ row in
            row.title = "Use Dyn CR in Bolus Calc"
            row.value = UserDefaultsRepository.useDynCrInBolusCalc.value
        }.onChange { [weak self] row in
            guard let value = row.value else { return }
            UserDefaultsRepository.useDynCrInBolusCalc.value = value
        }
        
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
            //UserDefaultsRepository.maxCarbs.value = Int(value)
            UserDefaultsRepository.maxCarbs.value = Double(value)
        }
        
        <<< StepperRow("maxFatProtein") { row in
            row.title = "Max Fat or Protein (g)"
            row.cell.stepper.stepValue = 5
            row.cell.stepper.minimumValue = 0
            row.cell.stepper.maximumValue = 200
            row.value = Double(UserDefaultsRepository.maxFatProtein.value)
            row.displayValueFor = { value in
                guard let value = value else { return nil }
                return "\(Int(value))"
            }
        }.onChange { [weak self] row in
            guard let value = row.value else { return }
            //UserDefaultsRepository.maxFatProtein.value = Int(value)
            UserDefaultsRepository.maxFatProtein.value = Double(value)
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
        
        +++ ButtonRow() {
            $0.title = "Klar"
        }.onCellSelection { (row, arg) in
            if let navigationController = self.navigationController {
                navigationController.popViewController(animated: true)
            } else {
                // If there's no navigation controller, dismiss the current view controller
                self.dismiss(animated: true, completion: nil)
            }
        }
    }
}

protocol RemoteSettingsDelegate: AnyObject {
    func remoteSettingsDidUpdateMethod()
}
