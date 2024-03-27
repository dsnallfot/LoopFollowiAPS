//
//  MealViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2024-03-21.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import UIKit
import LocalAuthentication

class MealViewController: UIViewController {
    
    @IBOutlet weak var bolusRow: UIView!
    @IBOutlet weak var sendMealButton: UIButton!
    @IBOutlet weak var carbGrams: UITextField!
    @IBOutlet weak var fatGrams: UITextField!
    @IBOutlet weak var proteinGrams: UITextField!
    @IBOutlet weak var mealNotes: UITextField!
    @IBOutlet weak var bolusUnits: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
        
        // Check the value of hideRemoteBolus and hide the bolusRow accordingly
        if UserDefaultsRepository.hideRemoteBolus.value {
            hideBolusRow()
        }
    }
    
    
    @IBAction func presetButtonTapped(_ sender: Any) {
        let presetViewController = storyboard!.instantiateViewController(withIdentifier: "remotePreset") as! PresetViewController
        self.present(presetViewController, animated: true, completion: nil)
    }
    
    @IBAction func sendRemoteMealPressed(_ sender: Any) {
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
            return
        }
        
        // CARBS & FPU ENTRIES
        // Convert carbGrams, fatGrams, and proteinGrams to integers or default to 0 if empty
        let carbs: Int
        let fats: Int
        let proteins: Int
        
        if let carbText = carbGrams.text, !carbText.isEmpty {
            guard let carbsValue = Int(carbText) else {
                print("Error: Carb input value conversion failed")
                return
            }
            carbs = carbsValue
        } else {
            carbs = 0
        }
        
        if let fatText = fatGrams.text, !fatText.isEmpty {
            guard let fatsValue = Int(fatText) else {
                print("Error: Fat input value conversion failed")
                return
            }
            fats = fatsValue
        } else {
            fats = 0
        }
        
        if let proteinText = proteinGrams.text, !proteinText.isEmpty {
            guard let proteinsValue = Int(proteinText) else {
                print("Error: Protein input value conversion failed")
                return
            }
            proteins = proteinsValue
        } else {
            proteins = 0
        }
        
        if carbs > maxCarbs || fats > maxCarbs || proteins > maxCarbs {
            let alertController = UIAlertController(title: "Max setting exceeded", message: "The maximum allowed amount of \(maxCarbs)g is exceeded for one or more of the entries! Please try again with a smaller amount.", preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alertController, animated: true, completion: nil)
            return // Exit the function if any value exceeds maxCarbs
        }
        
        // Call createCombinedString to get the combined string
        let combinedString = createCombinedString(carbs: carbs, fats: fats, proteins: proteins)

        // Show confirmation alert
        if bolusValue != 0 {
            showMealBolusConfirmationAlert(combinedString: combinedString)
        } else {
            showMealConfirmationAlert(combinedString: combinedString)
        }
        
        func createCombinedString(carbs: Int, fats: Int, proteins: Int) -> String {
            let mealNotesValue = mealNotes.text ?? ""
            var cleanedMealNotes = mealNotesValue
            // Convert bolusValue to string and trim any leading or trailing whitespace
            let trimmedBolusValue = "\(bolusValue)".trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Construct and return the combinedString based on hideRemoteBolus setting
            if UserDefaultsRepository.hideRemoteBolus.value {
                // Construct and return the combinedString without bolus
                return "Meal_Carbs_\(carbs)g_Fat_\(fats)g_Protein_\(proteins)g_Note_\(cleanedMealNotes)"
            } else {
                // Construct and return the combinedString with bolus
                return "Meal_Carbs_\(carbs)g_Fat_\(fats)g_Protein_\(proteins)g_Note_\(cleanedMealNotes)_Insulin_\(trimmedBolusValue)"
            }
        }
        
        //Alert for meal without bolus
        func showMealConfirmationAlert(combinedString: String) {
            // Confirmation alert before sending the request
            let confirmationAlert = UIAlertController(title: "Bekräfta", message: "Vill du registrera denna måltid?", preferredStyle: .alert)
            
            confirmationAlert.addAction(UIAlertAction(title: "Ja", style: .default, handler: { (action: UIAlertAction!) in
                // Proceed with sending the request
                self.sendMealRequest(combinedString: combinedString)
            }))
            
            confirmationAlert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: nil))
            
            present(confirmationAlert, animated: true, completion: nil)
        }
        
        //Alert for meal WITH bolus
        func showMealBolusConfirmationAlert(combinedString: String) {
            // Confirmation alert before sending the request
            let confirmationAlert = UIAlertController(title: "Bekräfta", message: "Vill du registrera denna måltid och ge \(bolusValue) E bolus?", preferredStyle: .alert)
            
            confirmationAlert.addAction(UIAlertAction(title: "Ja", style: .default, handler: { (action: UIAlertAction!) in
                // Authenticate with Face ID
                self.authenticateWithBiometrics {
                    // Proceed with the request after successful authentication
                    self.sendMealRequest(combinedString: combinedString)
                }
            }))
            
            confirmationAlert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: nil))
            
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
        } else {            // If method is "SMS API", proceed with sending the request
            
            let twilioSID = UserDefaultsRepository.twilioSIDString.value
            let twilioSecret = UserDefaultsRepository.twilioSecretString.value
            let fromNumber = UserDefaultsRepository.twilioFromNumberString.value
            let toNumber = UserDefaultsRepository.twilioToNumberString.value
            let message = combinedString
            
            // Build the request
            let urlString = "https://\(twilioSID):\(twilioSecret)@api.twilio.com/2010-04-01/Accounts/\(twilioSID)/Messages"
            guard let url = URL(string: urlString) else {
                print("Invalid URL")
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = "From=\(fromNumber)&To=\(toNumber)&Body=\(message)".data(using: .utf8)
            
            // Build the completion block and send the request
            URLSession.shared.dataTask(with: request) { (data, response, error) in
                DispatchQueue.main.async {
                    if let error = error {
                        // Failure: Show error alert for network error
                        let alertController = UIAlertController(title: "Fel", message: error.localizedDescription, preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                        self.present(alertController, animated: true, completion: nil)
                    } else if let httpResponse = response as? HTTPURLResponse {
                        if (200..<300).contains(httpResponse.statusCode) {
                            // Success: Show success alert for successful response
                            let alertController = UIAlertController(title: "Lyckades!", message: "Meddelandet levererades!", preferredStyle: .alert)
                            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                                // Dismiss the current view controller
                                self.dismiss(animated: true, completion: nil)
                            }))
                            self.present(alertController, animated: true, completion: nil)
                        } else {
                            // Failure: Show error alert for non-successful HTTP status code
                            let message = "HTTP Statuskod: \(httpResponse.statusCode)"
                            let alertController = UIAlertController(title: "Fel", message: message, preferredStyle: .alert)
                            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                            self.present(alertController, animated: true, completion: nil)
                        }
                    } else {
                        // Failure: Show generic error alert for unexpected response
                        let alertController = UIAlertController(title: "Fel", message: "Oväntat svar från servern", preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                        self.present(alertController, animated: true, completion: nil)
                    }
                }
            }.resume()
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
