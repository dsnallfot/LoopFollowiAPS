//
//  MealViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2024-03-21.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import UIKit
import LocalAuthentication
import AudioToolbox

class MealViewController: UIViewController, UITextFieldDelegate, TwilioRequestable  {
    var appStateController: AppStateController?
    
    @IBOutlet weak var carbsEntryField: UITextField!
    @IBOutlet weak var fatEntryField: UITextField!
    @IBOutlet weak var proteinEntryField: UITextField!
    @IBOutlet weak var notesEntryField: UITextField!
    @IBOutlet weak var bolusEntryField: UITextField!
    @IBOutlet weak var bolusRow: UIView!
    @IBOutlet weak var bolusCalcStack: UIStackView!
    @IBOutlet weak var bolusCalculated: UITextField!
    @IBOutlet weak var sendMealButton: UIButton!
    @IBOutlet weak var carbLabel: UILabel!
    @IBOutlet weak var carbGrams: UITextField!
    @IBOutlet weak var fatLabel: UILabel!
    @IBOutlet weak var fatGrams: UITextField!
    @IBOutlet weak var proteinLabel: UILabel!
    @IBOutlet weak var proteinGrams: UITextField!
    @IBOutlet weak var mealNotesLabel: UILabel!
    @IBOutlet weak var mealNotes: UITextField!
    @IBOutlet weak var mealDateTime: UIDatePicker!
    @IBOutlet weak var bolusLabel: UILabel!
    @IBOutlet weak var bolusUnits: UITextField!
    @IBOutlet weak var CRValue: UITextField!
    @IBOutlet weak var minPredBGValue: UITextField!
    @IBOutlet weak var minBGStack: UIStackView!
    @IBOutlet weak var bolusStack: UIStackView!
    @IBOutlet weak var plusSign: UIImageView!
    @IBOutlet weak var infoStack: UIStackView!
    
    var CR: Decimal = 0.0
    var minGuardBG: Decimal = 0.0
    var lowThreshold: Decimal = 0.0
    
    let maxCarbs = UserDefaultsRepository.maxCarbs.value
    let maxFatProtein = UserDefaultsRepository.maxFatProtein.value
    let maxBolus = UserDefaultsRepository.maxBolus.value
    
    var isAlertShowing = false // Property to track if alerts are currently showing
    var isButtonDisabled = false // Property to track if the button is currently disabled
    var isBolusEntryFieldPopulated = false
    
    var popupView: UIView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
        carbsEntryField.delegate = self
        fatEntryField.delegate = self
        proteinEntryField.delegate = self
        notesEntryField.delegate = self
        bolusEntryField.delegate = self
        
        setupInputAccessoryView()
        setupDatePickerLimits()
        self.focusCarbsEntryField()
        
        // Disable autocomplete and spell checking
        notesEntryField.autocorrectionType = .no
        notesEntryField.spellCheckingType = .no
        
        // Add tap gesture recognizers to labels
        addGestureRecognizers()
        
        // Add tap gesture recognizer to minBGStack
                let minBGStackTap = UITapGestureRecognizer(target: self, action: #selector(minBGStackTapped))
                minBGStack.addGestureRecognizer(minBGStackTap)
        
        // Add tap gesture recognizer to infoStack
                let infoStackTap = UITapGestureRecognizer(target: self, action: #selector(minBGStackTapped))
                infoStack.addGestureRecognizer(infoStackTap)
        
        // Register observers for shortcut callback notifications
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutSuccess), name: NSNotification.Name("ShortcutSuccess"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutError), name: NSNotification.Name("ShortcutError"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutCancel), name: NSNotification.Name("ShortcutCancel"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutPasscode), name: NSNotification.Name("ShortcutPasscode"), object: nil)
        
    //Bolus calculation preperations
        
        //Carb ratio
        if let sharedCRDouble = Double(sharedCRValue) {
            CR = Decimal(sharedCRDouble)
        } else {
            print("CR could not be fetched")
        }
        
        // Create a NumberFormatter instance
        let numberFormatter = NumberFormatter()
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = 1
        
        // Format the CR value to have one decimal place
        let formattedCR = numberFormatter.string(from: NSDecimalNumber(decimal: CR) as NSNumber) ?? ""
        
        // Set the text field with the formatted value of CR or "N/A" if formattedCR is "0.0"
        CRValue.text = formattedCR == "0" ? "N/A" : formattedCR
        print("CR: \(formattedCR) g/E")
        
        
        //print("Latest Autosens: \(sharedLatestSens)") // Just print for now. To use as info in bolusrecommendation later on
        //print("Latest ISF: \(sharedLatestISF)") // Just print for now. To use as info in bolusrecommendation later on
        //print("Latest IOB: \(sharedLatestIOB)") // Just print for now. To use as info in bolusrecommendation later on
        //print("Latest COB: \(sharedLatestCOB)") // Just print for now. To use as info in bolusrecommendation later on
        //print("Latest InsulinReq: \(sharedLatestInsulinReq)") // Just print for now. To use as info in bolusrecommendation later on
        //print("Latest CarbReq: \(sharedLatestCarbReq)") // Just print for now. To use as info in bolusrecommendation later on
        //print("Delta: \(Double(sharedDeltaBG) * 0.0555) mmol/L") // Just print for now. To use as info in bolusrecommendation later on

        //print("BG: \(sharedLatestBG) mmol/L")// Just print for now. To use as info in bolusrecommendation later on
        //print("Direction: \(sharedLatestDirection)")// Just print for now. To use as info in bolusrecommendation later on
        //print("Delta: \(sharedLatestDelta) mmol/L")// Just print for now. To use as info in bolusrecommendation later on
        print("MinGuardBG: \(sharedRawMinGuardBG) mmol/L")// Just print for now. To use as info in bolusrecommendation later on
        
        
        //MinGuardBG & Low Threshold
        let minGuardBG = Decimal(sharedMinGuardBG)
        let lowThreshold = Decimal(Double(UserDefaultsRepository.lowLine.value) * 0.0555)
        
        // Format the MinGuardBG value & low threshold to have one decimal place
        let formattedMinGuardBG = numberFormatter.string(from: NSDecimalNumber(decimal: minGuardBG) as NSNumber)?.replacingOccurrences(of: ",", with: ".") ?? ""
        let formattedLowThreshold = numberFormatter.string(from: NSDecimalNumber(decimal: lowThreshold) as NSNumber) ?? ""
         
        // Set the text field with the formatted value of minGuardBG or "N/A" if formattedMinGuardG is "0.0"
        minPredBGValue.text = formattedMinGuardBG == "0" ? "N/A" : formattedMinGuardBG
        print("Predicted Min BG: \(formattedMinGuardBG) mmol/L")
        print("Low threshold: \(formattedLowThreshold) mmol/L")
        
        // Check if the value of minGuardBG is less than lowThreshold
        if minGuardBG < lowThreshold && minGuardBG != 0 {
            // Show Min BG stack
            minBGStack.isHidden = false
            infoStack.isHidden = true
        } else {
            // Hide Min BG stack
            minBGStack.isHidden = true
            infoStack.isHidden = false
        }
        
        // Add tap gesture recognizer to bolusStack
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(bolusStackTapped))
        bolusStack.addGestureRecognizer(tapGesture)
        
        // Check the value of hideRemoteBolus and hide the bolusRow accordingly
        if UserDefaultsRepository.hideRemoteBolus.value {
            hideBolusRow()
        }
        
        // Check the value of hideBolusCalc and hide the bolusCalcRow accordingly
        if UserDefaultsRepository.hideBolusCalc.value {
            hideBolusCalcRow()
        }
    }
    
    @objc func minBGStackTapped() {
            togglePopupView()
        }
        
        func togglePopupView() {
            if popupView == nil {
                showPopupView()
            } else {
                dismissPopupView()
            }
        }
        
    func showPopupView() {
        if popupView == nil {
            // Create a new UIView for the popup
            let popupView = UIView()
            popupView.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(1.0)
            popupView.layer.cornerRadius = 10
            popupView.translatesAutoresizingMaskIntoConstraints = false
            
            // Add the popup view to the main view
            view.addSubview(popupView)
            
            // Set up initial constraints for the popup view
            let initialTopConstraint = popupView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: -255)
            NSLayoutConstraint.activate([
                popupView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
                popupView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
                initialTopConstraint,
                popupView.heightAnchor.constraint(equalToConstant: 255)
            ])
            
            // Add content to the popup view
            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .fill
            stackView.distribution = .equalSpacing
            stackView.spacing = 2
            stackView.translatesAutoresizingMaskIntoConstraints = false
            popupView.addSubview(stackView)
            
            // Add stack view constraints
            NSLayoutConstraint.activate([
                stackView.leadingAnchor.constraint(equalTo: popupView.leadingAnchor, constant: 20),
                stackView.trailingAnchor.constraint(equalTo: popupView.trailingAnchor, constant: -20),
                stackView.topAnchor.constraint(equalTo: popupView.topAnchor, constant: 20),
                stackView.bottomAnchor.constraint(equalTo: popupView.bottomAnchor, constant: -20)
            ])
            
            // Add metrics to the popup
            let metrics = ["BG", "Autosens", "ISF", "IOB", "COB", "Behov insulin", "Behov kolhydrater", "Min-Max BG", "Prognos BG"]
            let latestBGString = (sharedLatestBG + "  " + sharedLatestDirection + "  (" + sharedLatestDelta + ")")
            let values = [
                latestBGString,
                sharedLatestSens,
                sharedLatestISF,
                sharedLatestIOB,
                sharedLatestCOB,
                sharedLatestInsulinReq,
                sharedLatestCarbReq,
                sharedLatestMinMax,
                sharedLatestEvBG
            ]

            for (index, metric) in metrics.enumerated() {
                let rowStackView = UIStackView()
                rowStackView.axis = .horizontal
                rowStackView.alignment = .center
                rowStackView.distribution = .fill
                rowStackView.spacing = 2
                
                let label = UILabel()
                label.text = metric
                label.textAlignment = .left
                label.font = UIFont.systemFont(ofSize: 15) // Set font size to 14
                
                let spacer = UIView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                spacer.widthAnchor.constraint(equalToConstant: 20).isActive = true
                
                let valueLabel = UILabel()
                valueLabel.text = values[index]
                valueLabel.textAlignment = .right
                valueLabel.font = UIFont.systemFont(ofSize: 15) // Set font size to 14
                
                rowStackView.addArrangedSubview(label)
                rowStackView.addArrangedSubview(spacer)
                rowStackView.addArrangedSubview(valueLabel)
                
                stackView.addArrangedSubview(rowStackView)
                
                // Add a divider line between rows
                if index < metrics.count {
                    let divider = UIView()
                    divider.backgroundColor = UIColor.darkGray
                    divider.translatesAutoresizingMaskIntoConstraints = false
                    stackView.addArrangedSubview(divider)
                    
                    NSLayoutConstraint.activate([
                        divider.heightAnchor.constraint(equalToConstant: 1)
                    ])
                }
            }

            // Store the popup view
            self.popupView = popupView
            
            // Animate the popup view
            view.layoutIfNeeded()
            UIView.animate(withDuration: 0.3, animations: {
                initialTopConstraint.constant = 10
                self.view.layoutIfNeeded()
            })

            // Add tap gesture recognizer to dismiss the popup view
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissPopupView))
            view.addGestureRecognizer(tapGesture)
        }
    }

        
    @objc func dismissPopupView() {
           if let popupView = self.popupView {
               // Animate the popup view to move up
               UIView.animate(withDuration: 0.3, animations: {
                   popupView.frame.origin.y = -255
                   self.view.layoutIfNeeded()
               }) { _ in
                   // Remove the popup view from the superview
                   popupView.removeFromSuperview()
                   self.popupView = nil
               }
           }
       }
    
    func setupDatePickerLimits() {
            let now = Date()
            let oneDayInterval: TimeInterval = 23 * 60 * 60 + 59 * 60
            
            mealDateTime.minimumDate = now.addingTimeInterval(-oneDayInterval)
            mealDateTime.maximumDate = now.addingTimeInterval(oneDayInterval)
        }
    
    func setupInputAccessoryView() {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            
            let nextButton = UIBarButtonItem(title: "Nästa", style: .plain, target: self, action: #selector(nextTapped))
            let doneButton = UIBarButtonItem(title: "Klar", style: .plain, target: self, action: #selector(doneTapped))
            let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            
            //toolbar.setItems([flexSpace, nextButton, doneButton], animated: false)
            toolbar.setItems([nextButton, flexSpace, doneButton], animated: false)
            
            carbsEntryField.inputAccessoryView = toolbar
            fatEntryField.inputAccessoryView = toolbar
            proteinEntryField.inputAccessoryView = toolbar
            notesEntryField.inputAccessoryView = toolbar
            bolusEntryField.inputAccessoryView = toolbar
        }
        
        @objc func nextTapped() {
            if carbsEntryField.isFirstResponder {
                fatEntryField.becomeFirstResponder()
            } else if fatEntryField.isFirstResponder {
                proteinEntryField.becomeFirstResponder()
            } else if proteinEntryField.isFirstResponder {
                notesEntryField.becomeFirstResponder()
            } else if notesEntryField.isFirstResponder {
                bolusEntryField.becomeFirstResponder()
            } else if bolusEntryField.isFirstResponder {
                carbsEntryField.becomeFirstResponder()
            }
        }
        
        @objc func doneTapped() {
            view.endEditing(true)
        }
    
    // Add tap gesture recognizers to labels
        func addGestureRecognizers() {
            let carbLabelTap = UITapGestureRecognizer(target: self, action: #selector(focusCarbsEntryField))
            carbLabel.addGestureRecognizer(carbLabelTap)
            carbLabel.isUserInteractionEnabled = true
            
            let fatLabelTap = UITapGestureRecognizer(target: self, action: #selector(focusFatEntryField))
            fatLabel.addGestureRecognizer(fatLabelTap)
            fatLabel.isUserInteractionEnabled = true
            
            let proteinLabelTap = UITapGestureRecognizer(target: self, action: #selector(focusProteinEntryField))
            proteinLabel.addGestureRecognizer(proteinLabelTap)
            proteinLabel.isUserInteractionEnabled = true
            
            let mealNotesLabelTap = UITapGestureRecognizer(target: self, action: #selector(focusNotesEntryField))
            mealNotesLabel.addGestureRecognizer(mealNotesLabelTap)
            mealNotesLabel.isUserInteractionEnabled = true
            
            let bolusLabelTap = UITapGestureRecognizer(target: self, action: #selector(focusBolusEntryField))
            bolusLabel.addGestureRecognizer(bolusLabelTap)
            bolusLabel.isUserInteractionEnabled = true
        }
        
        @objc func focusCarbsEntryField() {
            self.carbsEntryField.becomeFirstResponder()
        }
        
        @objc func focusFatEntryField() {
            self.fatEntryField.becomeFirstResponder()
        }
        
        @objc func focusProteinEntryField() {
            self.proteinEntryField.becomeFirstResponder()
        }
        
        @objc func focusNotesEntryField() {
            self.notesEntryField.becomeFirstResponder()
        }
        
        @objc func focusBolusEntryField() {
            self.bolusEntryField.becomeFirstResponder()
        }
    
    // Function to calculate the suggested bolus value based on CR and check for maxCarbs
    func calculateBolus() {
        guard let carbsText = carbsEntryField.text,
              let carbsValue = Decimal(string: carbsText) else {
            // If no valid input, clear bolusCalculated and hide plus sign
            bolusCalculated.text = ""
            hidePlusSign()
            return
        }
        
        if carbsValue > 0 {
            showPlusSign()
        } else {
            hidePlusSign()
            return
        }
        
        var bolusValue = carbsValue / CR
        // Round down to the nearest 0.05
        bolusValue = roundDown(toNearest: Decimal(0.05), value: bolusValue)
        
        // Format the bolus value based on the locale's decimal separator
        let formattedBolus = formatDecimal(bolusValue)
        
        bolusCalculated.text = "\(formattedBolus)"
    }
    
    // UITextFieldDelegate method to handle text changes in carbsEntryField
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // Ensure that the textField being changed is the carbsEntryField
        
        // Calculate the new text after the replacement
        let newText = (textField.text as NSString?)?.replacingCharacters(in: range, with: string) ?? string
        if !newText.isEmpty {
            // Update the text in the carbsEntryField
            textField.text = newText
            
            // Calculate bolus whenever the carbs text field changes
            calculateBolus()
        } else {
            // If the new text is empty, clear bolusCalculated and update button state
            bolusCalculated.text = ""
            hidePlusSign()
            updateButtonState()
            return true
        }
        
        // Check if the new text is a valid number
        guard let newValue = Decimal(string: newText), newValue >= 0 else {
            // Update button state
            updateButtonState()
            return false
        }
        
        sendMealorMealandBolus()
            
        // Update button state
        updateButtonState()
        
        return false // Return false to prevent the text field from updating its text again
    }
    
    
    // Function to round a Decimal number down to the nearest specified increment
    func roundDown(toNearest increment: Decimal, value: Decimal) -> Decimal {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        let roundedDouble = (doubleValue * 20).rounded(.down) / 20
        
        return Decimal(roundedDouble)
    }
    
    // Function to format a Decimal number based on the locale's decimal separator
    func formatDecimal(_ value: Decimal) -> String {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        
        let numberFormatter = NumberFormatter()
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.minimumIntegerDigits = 1
        numberFormatter.decimalSeparator = Locale.current.decimalSeparator
        
        guard let formattedString = numberFormatter.string(from: NSNumber(value: doubleValue)) else {
            fatalError("Failed to format the number.")
        }
        
        return formattedString
    }
    
    //func focusCarbsEntryField() {
    //    self.carbsEntryField.becomeFirstResponder()
    //}
    
    func sendMealorMealandBolus() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "HelveticaNeue-Medium", size: 20.0)!,
        ]
        
        let carbsValue = Decimal(string: carbsEntryField.text ?? "0") ?? 0
        let fatValue = Decimal(string: fatEntryField.text ?? "0") ?? 0
        let proteinValue = Decimal(string: proteinEntryField.text ?? "0") ?? 0
      
        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 0
        
        // Check if the carbs value exceeds maxCarbs
        if carbsValue > Decimal(maxCarbs) {
            // Disable button
            isButtonDisabled = true
            sendMealButton.isEnabled = false
          
            // Format maxCarbs with zero decimals
            let formattedMaxCarbs = numberFormatter.string(from: NSNumber(value: maxCarbs)) ?? ""
          
            // Update button title
            sendMealButton.setAttributedTitle(NSAttributedString(string: "⛔️ Maxgräns kolhydrater \(formattedMaxCarbs) g", attributes: attributes), for: .normal)
        } else if fatValue > Decimal(maxFatProtein) || proteinValue > Decimal(maxFatProtein) {
            // Disable button
            isButtonDisabled = true
            sendMealButton.isEnabled = false
          
            // Format maxFatProtein with zero decimals
            let formattedMaxFatProtein = numberFormatter.string(from: NSNumber(value: maxFatProtein)) ?? ""
          
            // Update button title
            sendMealButton.setAttributedTitle(NSAttributedString(string: "⛔️ Maxgräns fett/protein \(formattedMaxFatProtein) g", attributes: attributes), for: .normal)
        }
 else if let bolusText = bolusUnits.text?.replacingOccurrences(of: ",", with: "."),

           let bolusValue = Decimal(string: bolusText),
           bolusValue > Decimal(maxBolus) + 0.01 { //add 0.01 to allow entry of = maxBolus due to rounding issues with double and decimals otherwise disable it when bolusValue=maxBolus
            
            // Disable button
            isButtonDisabled = true
            sendMealButton.isEnabled = false
            
            // Format maxBolus with two decimal places
            let formattedMaxBolus = String(format: "%.2f", UserDefaultsRepository.maxBolus.value)
            
            // Update button title if bolus exceeds maxBolus
            sendMealButton.setAttributedTitle(NSAttributedString(string: "⛔️ Maxgräns bolus \(formattedMaxBolus) E", attributes: attributes), for: .normal)
        } else {
            // Enable button
            sendMealButton.isEnabled = true
            isButtonDisabled = false
           // Check if bolusText is not "0" and not empty
            if let bolusText = bolusUnits.text, bolusText != "0" && !bolusText.isEmpty {
                // Update button title with bolus
                sendMealButton.setAttributedTitle(NSAttributedString(string: "Skicka Måltid och Bolus", attributes: attributes), for: .normal)
            } else {
                // Update button title without bolus
                sendMealButton.setAttributedTitle(NSAttributedString(string: "Skicka Måltid", attributes: attributes), for: .normal)
            }
        }
    }
    
    // Action method to handle tap on bolusStack
    @objc func bolusStackTapped() {
        if isBolusEntryFieldPopulated {
            // If bolusEntryField is already populated, make it empty
            bolusEntryField.text = ""
            isBolusEntryFieldPopulated = false
            sendMealorMealandBolus()
        } else {
            // If bolusEntryField is empty, populate it with the value from bolusCalculated
            bolusEntryField.text = bolusCalculated.text
            isBolusEntryFieldPopulated = true
            sendMealorMealandBolus()
            }
        }
    
    @IBAction func presetButtonTapped(_ sender: Any) {
        let customActionViewController = storyboard!.instantiateViewController(withIdentifier: "remoteCustomAction") as! CustomActionViewController
        self.present(customActionViewController, animated: true, completion: nil)
    }
    
    @IBAction func sendRemoteMealPressed(_ sender: Any) {
        // Disable the button to prevent multiple taps
        if !isButtonDisabled {
            isButtonDisabled = true
            sendMealButton.isEnabled = false
        } else {
            return // If button is already disabled, return to prevent double registration
        }
        
        // Retrieve the maximum carbs value from UserDefaultsRepository
        //let maxCarbs = UserDefaultsRepository.maxCarbs.value
        //let maxBolus = UserDefaultsRepository.maxBolus.value
        
        // BOLUS ENTRIES
        //Process bolus entries
        guard var bolusText = bolusUnits.text else {
            print("Note: Bolus amount not entered")
            return
        }
        
        // Replace all occurrences of ',' with '.
        
        bolusText = bolusText.replacingOccurrences(of: ",", with: ".")
        
        let bolusValue: Double
        if bolusText.isEmpty {
            bolusValue = 0
        } else {
            guard let bolusDouble = Double(bolusText) else {
                print("Error: Bolus amount conversion failed")
                // Play failure sound
                AudioServicesPlaySystemSound(SystemSoundID(1053))
                // Display an alert
                let alertController = UIAlertController(title: "Fel", message: "Bolus är inmatad i fel format", preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "Ändra", style: .default, handler: nil))
                present(alertController, animated: true, completion: nil)
                self.handleAlertDismissal() // Enable send button after handling failure to be able to try again
                return
            }
            bolusValue = bolusDouble
        }
        //Let code remain for now - to be cleaned
        if bolusValue > (maxBolus + 0.05) {
            // Play failure sound
            AudioServicesPlaySystemSound(SystemSoundID(1053))
            // Format maxBolus to display only one decimal place
            let formattedMaxBolus = String(format: "%.1f", maxBolus)
            
            let alertControllerBolus = UIAlertController(title: "Max setting exceeded", message: "The maximum allowed bolus of \(formattedMaxBolus) U is exceeded! Please try again with a smaller amount.", preferredStyle: .alert)
            alertControllerBolus.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alertControllerBolus, animated: true, completion: nil)
            self.handleAlertDismissal() // Enable send button after handling failure to be able to try again
            return
        }
        
        // CARBS & FPU ENTRIES
        
        guard var carbText = carbGrams.text else {
            print("Note: Carb amount not entered")
            return
        }
        
        carbText = carbText.replacingOccurrences(of: ",", with: ".")
        
        let carbsValue: Double
        if carbText.isEmpty {
            carbsValue = 0
        } else {
            guard let carbsDouble = Double(carbText) else {
                print("Error: Carb input value conversion failed")
                // Play failure sound
                AudioServicesPlaySystemSound(SystemSoundID(1053))
                // Display an alert
                let alertController = UIAlertController(title: "Fel", message: "Kolhydrater är inmatade i fel format", preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "Ändra", style: .default, handler: nil))
                present(alertController, animated: true, completion: nil)
                self.handleAlertDismissal() // Enable send button after handling failure to be able to try again
                return
            }
            carbsValue = carbsDouble
        }
        
        guard var fatText = fatGrams.text else {
            print("Note: Fat amount not entered")
            return
        }
        
        fatText = fatText.replacingOccurrences(of: ",", with: ".")
        
        let fatsValue: Double
        if fatText.isEmpty {
            fatsValue = 0
        } else {
            guard let fatsDouble = Double(fatText) else {
                print("Error: Fat input value conversion failed")
                // Play failure sound
                AudioServicesPlaySystemSound(SystemSoundID(1053))
                // Display an alert
                let alertController = UIAlertController(title: "Fel", message: "Fett är inmatat i fel format", preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "Ändra", style: .default, handler: nil))
                present(alertController, animated: true, completion: nil)
                self.handleAlertDismissal() // Enable send button after handling failure to be able to try again
                return
            }
            fatsValue = fatsDouble
        }
        
        guard var proteinText = proteinGrams.text else {
            print("Note: Protein amount not entered")
            return
        }
        
        proteinText = proteinText.replacingOccurrences(of: ",", with: ".")
        
        let proteinsValue: Double
        if proteinText.isEmpty {
            proteinsValue = 0
        } else {
            guard let proteinsDouble = Double(proteinText) else {
                print("Error: Protein input value conversion failed")
                // Play failure sound
                AudioServicesPlaySystemSound(SystemSoundID(1053))
                // Display an alert
                let alertController = UIAlertController(title: "Fel", message: "Protein är inmatat i fel format", preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "Ändra", style: .default, handler: nil))
                present(alertController, animated: true, completion: nil)
                self.handleAlertDismissal() // Enable send button after handling failure to be able to try again
                return
            }
            proteinsValue = proteinsDouble
        }
        
        if carbsValue > maxCarbs || fatsValue > maxCarbs || proteinsValue > maxCarbs {
            // Play failure sound
            AudioServicesPlaySystemSound(SystemSoundID(1053))
            let alertController = UIAlertController(title: "Max setting exceeded", message: "The maximum allowed amount of \(maxCarbs)g is exceeded for one or more of the entries! Please try again with a smaller amount.", preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alertController, animated: true, completion: nil)
            self.handleAlertDismissal() // Enable send button after handling failure to be able to try again
            return // Exit the function if any value exceeds maxCarbs
        }
        
        // Call createCombinedString to get the combined string
        //let combinedString = createCombinedString(carbs: carbs, fats: fats, proteins: proteins)
        let combinedString = createCombinedString(carbs: carbsValue, fats: fatsValue, proteins: proteinsValue)
        
        // Show confirmation alert
        if bolusValue != 0 {
            showMealBolusConfirmationAlert(combinedString: combinedString)
        } else {
            showMealConfirmationAlert(combinedString: combinedString)
        }

        // Function to format date to ISO 8601 without seconds and milliseconds
            func formatDateToISO8601(_ date: Date) -> String {
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
                return dateFormatter.string(from: date)
            }

            // Function to create combined string with selected date
            func createCombinedString(carbs: Double, fats: Double, proteins: Double) -> String {
                let mealNotesValue = mealNotes.text ?? ""
                let cleanedMealNotes = mealNotesValue
                let name = UserDefaultsRepository.caregiverName.value
                let secret = UserDefaultsRepository.remoteSecretCode.value
                // Convert bolusValue to string and trim any leading or trailing whitespace
                let trimmedBolusValue = "\(bolusValue)".trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Get selected date from mealDateTime and format to ISO 8601
                let selectedDate = mealDateTime.date
                let formattedDate = formatDateToISO8601(selectedDate)
                
                if UserDefaultsRepository.hideRemoteBolus.value {
                    // Construct and return the combinedString without bolus
                    return "Remote Måltid\nKolhydrater: \(carbs)g\nFett: \(fats)g\nProtein: \(proteins)g\nNotering: \(cleanedMealNotes)\nDatum: \(formattedDate)\nInlagt av: \(name)\nHemlig kod: \(secret)"
                } else {
                    // Construct and return the combinedString with bolus
                    return "Remote Måltid\nKolhydrater: \(carbs)g\nFett: \(fats)g\nProtein: \(proteins)g\nNotering: \(cleanedMealNotes)\nDatum: \(formattedDate)\nInsulin: \(trimmedBolusValue)E\nInlagt av: \(name)\nHemlig kod: \(secret)"
                }
            }
        
        //Alert for meal without bolus
        func showMealConfirmationAlert(combinedString: String) {
            // Set isAlertShowing to true before showing the alert
            isAlertShowing = true
            // Confirmation alert before sending the request
            let confirmationAlert = UIAlertController(title: "Bekräfta måltid", message: "Vill du registrera denna måltid?", preferredStyle: .alert)
            
            confirmationAlert.addAction(UIAlertAction(title: "Ja", style: .default, handler: { (action: UIAlertAction!) in
                // Proceed with sending the request
                self.sendMealRequest(combinedString: combinedString)
            }))
            
            confirmationAlert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: { (action: UIAlertAction!) in
                // Handle dismissal when "Cancel" is selected
                self.handleAlertDismissal()
            }))
            
            present(confirmationAlert, animated: true, completion: nil)
        }
        
        //Alert for meal WITH bolus
        func showMealBolusConfirmationAlert(combinedString: String) {
            // Set isAlertShowing to true before showing the alert
            isAlertShowing = true
            // Confirmation alert before sending the request
            let confirmationAlert = UIAlertController(title: "Bekräfta måltid och bolus", message: "Vill du registrera denna måltid och ge \(bolusValue) E bolus?", preferredStyle: .alert)
            
            confirmationAlert.addAction(UIAlertAction(title: "Ja", style: .default, handler: { (action: UIAlertAction!) in
                let method = UserDefaultsRepository.method.value
                
                if method == "SMS API" {
                    // Authenticate with Face ID
                    self.authenticateWithBiometrics {
                        // Proceed with the request after successful authentication
                        self.sendMealRequest(combinedString: combinedString)
                    }
                } else {
                    self.sendMealRequest(combinedString: combinedString)
                }
            }))
            
            confirmationAlert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: { (action: UIAlertAction!) in
                // Handle dismissal when "Cancel" is selected
                self.handleAlertDismissal()
            }))
            
            present(confirmationAlert, animated: true, completion: nil)
        }
    }
    
    func authenticateWithBiometrics(completion: @escaping () -> Void) {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Authenticate with biometrics to proceed"
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        // Authentication successful
                        completion()
                    } else {
                        // Check for passcode authentication
                        if let error = authenticationError as NSError?,
                           error.code == LAError.biometryNotAvailable.rawValue || error.code == LAError.biometryNotEnrolled.rawValue {
                            // Biometry (Face ID or Touch ID) is not available or not enrolled, use passcode
                            self.authenticateWithPasscode(completion: completion)
                        } else {
                            // Authentication failed
                            if let error = authenticationError {
                                print("Authentication failed: \(error.localizedDescription)")
                            }
                            // Handle dismissal when authentication fails
                            self.handleAlertDismissal()
                        }
                    }
                }
            }
        } else {
            // Biometry (Face ID or Touch ID) is not available, use passcode
            self.authenticateWithPasscode(completion: completion)
        }
    }
    
    func authenticateWithPasscode(completion: @escaping () -> Void) {
        let context = LAContext()
        
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Authenticate with passcode to proceed") { success, error in
            DispatchQueue.main.async {
                if success {
                    // Authentication successful
                    completion()
                } else {
                    // Authentication failed
                    if let error = error {
                        print("Authentication failed: \(error.localizedDescription)")
                    }
                    // Handle dismissal when authentication fails
                    self.handleAlertDismissal()
                }
            }
        }
    }
    
    // Function to handle alert dismissal
    func handleAlertDismissal() {
        // Enable the button when alerts are dismissed
        isAlertShowing = false
        sendMealButton.isEnabled = true
        isButtonDisabled = false // Reset button disable status
    }
    
    func sendMealRequest(combinedString: String) {
        // Retrieve the method value from UserDefaultsRepository
        let method = UserDefaultsRepository.method.value
        
        if method != "SMS API" {
            // URL encode combinedString
            guard let encodedString = combinedString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                print("Failed to encode URL string")
                return
            }
            
            // Define your custom callback URLs
            let successCallback = "loop://completed" // Add completed for future use when the shortcut has run, but for instance the passcode was wrong. NOTE: not to mixed up with loop://success that should be returned by the remote meal shortcut to proceed with the meal registration)
            let errorCallback = "loop://error"
            let cancelCallback = "loop://cancel"
            
            // Encode the callback URLs
            guard let successEncoded = successCallback.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let errorEncoded = errorCallback.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let cancelEncoded = cancelCallback.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                print("Failed to encode callback URLs")
                return
            }
            
            
            /*let urlString = "shortcuts://run-shortcut?name=Remote%20Meal&input=text&text=\(encodedString)"
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)*/
                // Construct the final URL with x-callback-url
                let urlString = "shortcuts://x-callback-url/run-shortcut?name=Remote%20Meal&input=text&text=\(encodedString)&x-success=\(successEncoded)&x-error=\(errorEncoded)&x-cancel=\(cancelEncoded)"
                
                if let url = URL(string: urlString) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
                
                print("Waiting for shortcut completion...")
            //dismiss(animated: true, completion: nil)
        } else {
            // If method is "SMS API", proceed with sending the request
            twilioRequest(combinedString: combinedString) { result in
                switch result {
                case .success:
                    // Play success sound
                    AudioServicesPlaySystemSound(SystemSoundID(1322))
                    
                    // Show success alert
                    let alertController = UIAlertController(title: "Lyckades!", message: "Meddelandet levererades", preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                        // Dismiss the current view controller
                        self.dismiss(animated: true, completion: nil)
                    }))
                    self.present(alertController, animated: true, completion: nil)
                case .failure(let error):
                    // Play failure sound
                    AudioServicesPlaySystemSound(SystemSoundID(1053))
                    
                    // Show error alert
                    let alertController = UIAlertController(title: "Fel", message: error.localizedDescription, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    @objc private func handleShortcutSuccess() {
        print("Shortcut succeeded")
        
        // Play a success sound
        AudioServicesPlaySystemSound(SystemSoundID(1322))
        
        // Show success alert with "Lyckades"
        showAlert(title: NSLocalizedString("Lyckades", comment: "Lyckades"), message: NSLocalizedString("Måltidsregistreringen skickades", comment: "Måltidsregistreringen skickades"), completion: {
            self.dismiss(animated: true, completion: nil)  // Dismiss the view controller after showing the alert
        })
    }

    @objc private func handleShortcutError() {
        print("Shortcut failed, showing error alert...")
        
        // Play a error sound
        AudioServicesPlaySystemSound(SystemSoundID(1053))
        
        showAlert(title: NSLocalizedString("Misslyckades", comment: "Misslyckades"), message: NSLocalizedString("Ett fel uppstod när genvägen skulle köras. Du kan försöka igen.", comment: "Ett fel uppstod när genvägen skulle köras. Du kan försöka igen."), completion: {
            self.handleAlertDismissal()  // Re-enable the send button after error handling
        })
    }

    @objc private func handleShortcutCancel() {
        print("Shortcut was cancelled, showing cancellation alert...")
        
        // Play a error sound
        AudioServicesPlaySystemSound(SystemSoundID(1053))
        
        showAlert(title: NSLocalizedString("Avbröts", comment: "Avbröts"), message: NSLocalizedString("Genvägen avbröts innan den körts färdigt. Du kan försöka igen.", comment: "Genvägen avbröts innan den körts färdigt. Du kan försöka igen.") , completion: {
            self.handleAlertDismissal()  // Re-enable the send button after cancellation
        })
    }
    
    @objc private func handleShortcutPasscode() {
        print("Shortcut was cancelled due to wrong passcode, showing passcode alert...")
        
        // Play a error sound
        AudioServicesPlaySystemSound(SystemSoundID(1053))
        
        showAlert(title: NSLocalizedString("Fel lösenkod", comment: "Fel lösenkod"), message: NSLocalizedString("Genvägen avbröts pga fel lösenkod. Du kan försöka igen.", comment: "Genvägen avbröts pga fel lösenkod. Du kan försöka igen.") , completion: {
            self.handleAlertDismissal()  // Re-enable the send button after cancellation
        })
    }

    private func showAlert(title: String, message: String, completion: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            completion()  // Call the completion handler after dismissing the alert
        }))
        present(alert, animated: true, completion: nil)
    }
    
    @IBAction func editingChanged(_ sender: Any) {
        print("Value changed in bolus amount")
                
        sendMealorMealandBolus()
        
    }
    
    // Function to update button state
    func updateButtonState() {
        // Disable or enable button based on isButtonDisabled
        sendMealButton.isEnabled = !isButtonDisabled
    }

    // Function to hide both the bolusRow and bolusCalcStack
    func hideBolusRow() {
        bolusRow.isHidden = true
        bolusCalcStack.isHidden = true
    }
    
    // Function to show the bolusRow
    func showBolusRow() {
        bolusRow.isHidden = false
    }
    
    // Function to hide the bolusCalcStack
    func hideBolusCalcRow() {
        bolusCalcStack.isHidden = true
    }
    
    // Function to show the bolusCalcStack
    func showBolusCalcRow() {
        bolusCalcStack.isHidden = false
    }
    
    // Function to hide the plus sign
    func hidePlusSign() {
        plusSign.isHidden = true
    }
    
    // Function to show the plus sign
    func showPlusSign() {
        plusSign.isHidden = false
    }
    
    @IBAction func doneButtonTapped(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
}
