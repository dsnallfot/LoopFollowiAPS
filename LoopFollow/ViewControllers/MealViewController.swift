//
//  MealViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2024-03-21.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import UIKit
import LocalAuthentication

class MealViewController: UIViewController, UITextFieldDelegate, TwilioRequestable {
    
    @IBOutlet weak var carbsEntryField: UITextField!
    @IBOutlet weak var fatEntryField: UITextField!
    @IBOutlet weak var proteinEntryField: UITextField!
    @IBOutlet weak var notesEntryField: UITextField!
    @IBOutlet weak var bolusEntryField: UITextField!
    @IBOutlet weak var bolusRow: UIView!
    @IBOutlet weak var sendMealButton: UIButton!
    @IBOutlet weak var carbGrams: UITextField!
    @IBOutlet weak var fatGrams: UITextField!
    @IBOutlet weak var proteinGrams: UITextField!
    @IBOutlet weak var mealNotes: UITextField!
    @IBOutlet weak var bolusUnits: UITextField!
    
    var isAlertShowing = false // Property to track if alerts are currently showing
    var isButtonDisabled = false // Property to track if the button is currently disabled
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
        carbsEntryField.delegate = self
        self.focusCarbsEntryField()
    
        // Check the value of hideRemoteBolus and hide the bolusRow accordingly
        if UserDefaultsRepository.hideRemoteBolus.value {
            hideBolusRow()
        }
    }
    func focusCarbsEntryField() {
        self.carbsEntryField.becomeFirstResponder()
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
        let maxCarbs = UserDefaultsRepository.maxCarbs.value
        let maxBolus = UserDefaultsRepository.maxBolus.value
        
        // BOLUS ENTRIES
        //Process bolus entries
        guard var bolusText = bolusUnits.text else {
            print("Error: Bolus amount not entered")
            return
        }
        
        // Replace all occurrences of ',' with '.'
        bolusText = bolusText.replacingOccurrences(of: ",", with: ".")
        
        let bolusValue: Double
        if bolusText.isEmpty {
            bolusValue = 0
        } else {
            guard let bolusDouble = Double(bolusText) else {
                print("Error: Bolus amount conversion failed")
                return
            }
            bolusValue = bolusDouble
        }
        
        if bolusValue > maxBolus {
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
            print("Error: Carb amount not entered")
            return
        }
        
        carbText = carbText.replacingOccurrences(of: ",", with: ".")
        
        let carbsValue: Double
        if carbText.isEmpty {
            carbsValue = 0
        } else {
            guard let carbsDouble = Double(carbText) else {
                print("Error: Carb amount conversion failed")
                return
            }
            carbsValue = carbsDouble
        }
        
        guard var fatText = fatGrams.text else {
            print("Error: Fat amount not entered")
            return
        }
        
        fatText = fatText.replacingOccurrences(of: ",", with: ".")
        
        let fatsValue: Double
        if fatText.isEmpty {
            fatsValue = 0
        } else {
            guard let fatsDouble = Double(fatText) else {
                print("Error: Fat amount conversion failed")
                return
            }
            fatsValue = fatsDouble
        }
        
        guard var proteinText = proteinGrams.text else {
            print("Error: Protein amount not entered")
            return
        }
        
        proteinText = proteinText.replacingOccurrences(of: ",", with: ".")
        
        let proteinsValue: Double
        if proteinText.isEmpty {
            proteinsValue = 0
        } else {
            guard let proteinsDouble = Double(proteinText) else {
                print("Error: Protein amount conversion failed")
                return
            }
            proteinsValue = proteinsDouble
        }
        
        if carbsValue > maxCarbs { // || fatsValue > maxCarbs || proteinsValue > maxCarbs { // Just use the maxcarbs guardrail for carb entries until we agreed upon a better approach regarding fat and protein
            let alertController = UIAlertController(title: "Max setting exceeded", message: "The maximum allowed amount of \(maxCarbs) g is exceeded! Please try again with a smaller amount.", preferredStyle: .alert)
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
            var cleanedMealNotes = mealNotesValue
            // Convert bolusValue to string and trim any leading or trailing whitespace
            let trimmedBolusValue = "\(bolusValue)".trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Construct and return the combinedString based on hideRemoteBolus setting
            if UserDefaultsRepository.hideRemoteBolus.value {
                // Construct and return the combinedString without bolus
                return "Meal_Carbs_\(carbsValue)g_Fat_\(fatsValue)g_Protein_\(proteinsValue)g_Note_\(cleanedMealNotes)"
            } else {
                // Construct and return the combinedString with bolus
                return "Meal_Carbs_\(carbsValue)g_Fat_\(fatsValue)g_Protein_\(proteinsValue)g_Note_\(cleanedMealNotes)_Insulin_\(trimmedBolusValue)"
            }
        }
        
        //Alert for meal without bolus
        func showMealConfirmationAlert(combinedString: String) {
            // Set isAlertShowing to true before showing the alert
                    isAlertShowing = true
            // Confirmation alert before sending the request
            let confirmationAlert = UIAlertController(title: "Confirmation", message: "Do you want to register this meal?", preferredStyle: .alert)
            
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
            let confirmationAlert = UIAlertController(title: "Confirmation", message: "Do you want to register this meal and give \(bolusValue) U bolus?", preferredStyle: .alert)
            
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
                    // Show success alert
                    let alertController = UIAlertController(title: "Success", message: "Message sent successfully!", preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                        // Dismiss the current view controller
                        self.dismiss(animated: true, completion: nil)
                    }))
                    self.present(alertController, animated: true, completion: nil)
                case .failure(let error):
                    // Show error alert
                    let alertController = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
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
        let attributedTitle: NSAttributedString
        if let bolusText = bolusUnits.text, bolusText != "0" && bolusText != "" {
            attributedTitle = NSAttributedString(string: "Skicka Måltid och Bolus", attributes: attributes)
        } else {
            attributedTitle = NSAttributedString(string: "Skicka Måltid", attributes: [.font: UIFont(name: "HelveticaNeue-Medium", size: 20.0)!])
        }
        sendMealButton.setAttributedTitle(attributedTitle, for: .normal)
    }

    // Function to hide the bolusRow
    func hideBolusRow() {
        bolusRow.isHidden = true
    }
    
    // Function to show the bolusRow
    func showBolusRow() {
        bolusRow.isHidden = false
    }
    
    @IBAction func doneButtonTapped(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
}
