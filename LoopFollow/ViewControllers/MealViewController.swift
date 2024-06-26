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
    @IBOutlet weak var bolusCalcRow: UIView!
    @IBOutlet weak var bolusCalculated: UITextField!
    @IBOutlet weak var sendMealButton: UIButton!
    @IBOutlet weak var carbGrams: UITextField!
    @IBOutlet weak var fatGrams: UITextField!
    @IBOutlet weak var proteinGrams: UITextField!
    @IBOutlet weak var mealNotes: UITextField!
    @IBOutlet weak var bolusUnits: UITextField!
    
    let maxCarbs = UserDefaultsRepository.maxCarbs.value
    let maxFatProtein = UserDefaultsRepository.maxFatProtein.value
    let maxBolus = UserDefaultsRepository.maxBolus.value
        
    var isAlertShowing = false // Property to track if alerts are currently showing
    var isButtonDisabled = false // Property to track if the button is currently disabled
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
        carbsEntryField.delegate = self
        fatEntryField.delegate = self
        proteinEntryField.delegate = self
        self.focusCarbsEntryField()

        // Create a NumberFormatter instance
        let numberFormatter = NumberFormatter()
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = 1
        
        // Check the value of hideRemoteBolus and hide the bolusRow accordingly
        if UserDefaultsRepository.hideRemoteBolus.value {
            hideBolusRow()
        }
    }

        // UITextFieldDelegate method to handle text changes in carbsEntryField
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        // Calculate the new text after the replacement
        let newText = (textField.text as NSString?)?.replacingCharacters(in: range, with: string) ?? string
        if !newText.isEmpty {
            // Update the text in the carbsEntryField
            textField.text = newText
        } else {
            // If the new text is empty, update button state
            updateButtonState()
            return true
        }

            // Check if the new text is a valid number
            guard let newValue = Decimal(string: newText), newValue >= 0 else {
                // Update button state
                updateButtonState()
                return false
            }

            let carbsValue = Decimal(string: carbsEntryField.text ?? "0") ?? 0
            let fatValue = Decimal(string: fatEntryField.text ?? "0") ?? 0
            let proteinValue = Decimal(string: proteinEntryField.text ?? "0") ?? 0
            
            // Check if the carbs value exceeds maxCarbs
            if carbsValue > Decimal(maxCarbs) {
                    // Disable button
                    isButtonDisabled = true
                    // Update button title
                    sendMealButton.setAttributedTitle(NSAttributedString(string: "⛔️ Max Carbs \(maxCarbs) g", attributes: [.font: UIFont(name: "HelveticaNeue-Medium", size: 20.0)!]), for: .normal)
            } else if fatValue > Decimal(maxFatProtein) || proteinValue > Decimal(maxFatProtein) {
                // Disable button
                isButtonDisabled = true
                // Update button title
                sendMealButton.setAttributedTitle(NSAttributedString(string: "⛔️ Max Fat/Protein \(maxFatProtein) g", attributes: [.font: UIFont(name: "HelveticaNeue-Medium", size: 20.0)!]), for: .normal)
            } else {
                    // Enable button
                    isButtonDisabled = false
                    // Check if bolusText is not "0" and not empty
                    if let bolusText = bolusUnits.text, bolusText != "0" && !bolusText.isEmpty {
                        // Update button title with bolus
                        sendMealButton.setAttributedTitle(NSAttributedString(string: "Send Meal and Bolus", attributes: [.font: UIFont(name: "HelveticaNeue-Medium", size: 20.0)!]), for: .normal)
                    } else {
                        // Update button title without bolus
                        sendMealButton.setAttributedTitle(NSAttributedString(string: "Send Meal", attributes: [.font: UIFont(name: "HelveticaNeue-Medium", size: 20.0)!]), for: .normal)
                    }
                }
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
    
    func focusCarbsEntryField() {
            self.carbsEntryField.becomeFirstResponder()
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
        
        // BOLUS ENTRIES
        //Process bolus entries
        guard var bolusText = bolusUnits.text else {
            print("Note: Bolus amount not entered")
            return
        }
        
        // Replace all eventual occurrences of ',' with '.
        
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
                let alertController = UIAlertController(title: "Error!", message: "Bolus entry is misformatted", preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "Change", style: .default, handler: nil))
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
                let alertController = UIAlertController(title: "Error!", message: "Carb entry is misformatted", preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "Change", style: .default, handler: nil))
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
                let alertController = UIAlertController(title: "Error!", message: "Fat entry is misformatted", preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "Change", style: .default, handler: nil))
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
                let alertController = UIAlertController(title: "Error", message: "Protein entry is misformatted", preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "Change", style: .default, handler: nil))
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
        let combinedString = createCombinedString(carbs: carbsValue, fats: fatsValue, proteins: proteinsValue)

        // Show confirmation alert
        if bolusValue != 0 {
            showMealBolusConfirmationAlert(combinedString: combinedString)
        } else {
            showMealConfirmationAlert(combinedString: combinedString)
        }
        
        func createCombinedString(carbs: Double, fats: Double, proteins: Double) -> String {
            let mealNotesValue = mealNotes.text ?? ""
            let cleanedMealNotes = mealNotesValue
            let name = UserDefaultsRepository.caregiverName.value
            let secret = UserDefaultsRepository.remoteSecretCode.value
            // Convert bolusValue to string and trim any leading or trailing whitespace
            let trimmedBolusValue = "\(bolusValue)".trimmingCharacters(in: .whitespacesAndNewlines)
            
            if UserDefaultsRepository.hideRemoteBolus.value {
                // Construct and return the combinedString without bolus
                return "Remote Meal\nCarbs: \(carbsValue)g\nFat: \(fatsValue)g\nProtein: \(proteinsValue)g\nNotes: \(cleanedMealNotes)\nEntered by: \(name)\nSecret Code: \(secret)"
            } else {
                // Construct and return the combinedString with bolus
                return "Remote Meal\nCarbs: \(carbsValue)g\nFat: \(fatsValue)g\nProtein: \(proteinsValue)g\nNotes: \(cleanedMealNotes)\nInsulin: \(trimmedBolusValue)U\nEntered by: \(name)\nSecret Code: \(secret)"
            }

        }
        
        //Alert for meal without bolus
        func showMealConfirmationAlert(combinedString: String) {
            // Set isAlertShowing to true before showing the alert
                    isAlertShowing = true
            // Confirmation alert before sending the request
            let confirmationAlert = UIAlertController(title: "Confirm Meal", message: "Do you want to register this meal?", preferredStyle: .alert)
            
            confirmationAlert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { (action: UIAlertAction!) in
                // Proceed with sending the request
                self.sendMealRequest(combinedString: combinedString)
            }))
            
            confirmationAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action: UIAlertAction!) in
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
            let confirmationAlert = UIAlertController(title: "Confirm Meal and Bolus", message: "Do you want to register this meal and give \(bolusValue) U bolus?", preferredStyle: .alert)
            
            confirmationAlert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { (action: UIAlertAction!) in
                // Authenticate with Face ID
                self.authenticateWithBiometrics {
                    // Proceed with the request after successful authentication
                    self.sendMealRequest(combinedString: combinedString)
                }
            }))
            
            confirmationAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action: UIAlertAction!) in
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
            let urlString = "shortcuts://run-shortcut?name=Remote%20Meal&input=text&text=\(encodedString)"
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            dismiss(animated: true, completion: nil)
        } else {
            // If method is "SMS API", proceed with sending the request
            twilioRequest(combinedString: combinedString) { result in
                switch result {
                case .success:
                    // Play success sound
                    AudioServicesPlaySystemSound(SystemSoundID(1322))
                    
                    // Show success alert
                    let alertController = UIAlertController(title: "Success!", message: "Message delivered", preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                        // Dismiss the current view controller
                        self.dismiss(animated: true, completion: nil)
                    }))
                    self.present(alertController, animated: true, completion: nil)
                case .failure(let error):
                    // Play failure sound
                    AudioServicesPlaySystemSound(SystemSoundID(1053))
                    
                    // Show error alert
                    let alertController = UIAlertController(title: "Error!", message: error.localizedDescription, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    @IBAction func editingChanged(_ sender: Any) {
        print("Value changed in bolus amount")
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "HelveticaNeue-Medium", size: 20.0)!,
        ]
        
        // Check if bolusText exceeds maxBolus
        if let bolusText = bolusUnits.text?.replacingOccurrences(of: ",", with: "."),
           let bolusValue = Decimal(string: bolusText),
           bolusValue > Decimal(maxBolus) + 0.01 { //add 0.01 to allow entry of = maxBolus due to rounding issues with double and decimals otherwise disable it when bolusValue=maxBolus
            
            // Disable button
            sendMealButton.isEnabled = false
            
            // Format maxBolus with two decimal places
            let formattedMaxBolus = String(format: "%.2f", UserDefaultsRepository.maxBolus.value)
            
            // Update button title if bolus exceeds maxBolus
            sendMealButton.setAttributedTitle(NSAttributedString(string: "⛔️ Max Bolus \(formattedMaxBolus) U", attributes: attributes), for: .normal)
        } else {
            // Enable button
            sendMealButton.isEnabled = true
            
            // Check if bolusText is not "0" and not empty
            if let bolusText = bolusUnits.text, bolusText != "0" && !bolusText.isEmpty {
                // Update button title with bolus
                sendMealButton.setAttributedTitle(NSAttributedString(string: "Send Meal and Bolus", attributes: attributes), for: .normal)
            } else {
                // Update button title without bolus
                sendMealButton.setAttributedTitle(NSAttributedString(string: "Send Meal", attributes: [.font: UIFont(name: "HelveticaNeue-Medium", size: 20.0)!]), for: .normal)
            }
        }
    }

    
    // Function to update button state
    func updateButtonState() {
        // Disable or enable button based on isButtonDisabled
        sendMealButton.isEnabled = !isButtonDisabled
    }

    // Function to hide the bolusRow
    func hideBolusRow() {
        bolusRow.isHidden = true
    }
    
    // Function to show the bolusRow
    func showBolusRow() {
        bolusRow.isHidden = false
    }
    
    // Function to hide the bolusCalcRow
    func hideBolusCalcRow() {
        bolusCalcRow.isHidden = true
    }
    
    // Function to show the bolusCalcRow
    func showBolusCalcRow() {
        bolusCalcRow.isHidden = false
    }
    
    @IBAction func doneButtonTapped(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
}
