//
//  MealViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2024-03-21.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import UIKit

class MealViewController: UIViewController {
    
    @IBOutlet weak var carbGrams: UITextField!
    @IBOutlet weak var fatGrams: UITextField!
    @IBOutlet weak var proteinGrams: UITextField!
    @IBOutlet weak var mealNotes: UITextField!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
            
            // Do any additional setup after loading the view.
        }
    }
    
    @IBAction func sendRemoteMealPressed(_ sender: Any) {
        // Retrieve the maximum carbs value from UserDefaultsRepository
        let maxCarbs = UserDefaultsRepository.maxCarbs.value
        
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
        if let combinedString = createCombinedString(carbs: carbs, fats: fats, proteins: proteins) {
            // Show confirmation alert
            showConfirmationAlert(combinedString: combinedString)
        }
    }
    
    func createCombinedString(carbs: Int, fats: Int, proteins: Int) -> String? {
        let mealNotesValue = mealNotes.text ?? ""
        var cleanedMealNotes = mealNotesValue
        
        // Retrieve the method value from UserDefaultsRepository
        let method = UserDefaultsRepository.method.value
        
        // Construct and return the combinedString
        let combinedString = "Meal_Carbs_\(carbs)g_Fat_\(fats)g_Protein_\(proteins)g_Note_\(cleanedMealNotes)"
        
        //Alterntive combinedString formatting below, to present the meal more like a visual menu in imessage on receiving iPhone.
        //let combinedString = "Mealtime\nCarbs \(carbs)g\nFat \(fats)g\nProtein \(proteins)g \nNote \(cleanedMealNotes)"
        
        return combinedString
    }
    
    func showConfirmationAlert(combinedString: String) {
        // Confirmation alert before sending the request
        let confirmationAlert = UIAlertController(title: "Confirmation", message: "Do you want to register this meal?", preferredStyle: .alert)
        
        confirmationAlert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { (action: UIAlertAction!) in
            // Proceed with sending the request
            self.sendMealRequest(combinedString: combinedString)
        }))
        
        confirmationAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        present(confirmationAlert, animated: true, completion: nil)
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
                        let alertController = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                        self.present(alertController, animated: true, completion: nil)
                    } else if let httpResponse = response as? HTTPURLResponse {
                        if (200..<300).contains(httpResponse.statusCode) {
                            // Success: Show success alert for successful response
                            let alertController = UIAlertController(title: "Success", message: "Message sent successfully!", preferredStyle: .alert)
                            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                                // Dismiss the current view controller
                                self.dismiss(animated: true, completion: nil)
                            }))
                            self.present(alertController, animated: true, completion: nil)
                        } else {
                            // Failure: Show error alert for non-successful HTTP status code
                            let message = "HTTP Status Code: \(httpResponse.statusCode)"
                            let alertController = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
                            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                            self.present(alertController, animated: true, completion: nil)
                        }
                    } else {
                        // Failure: Show generic error alert for unexpected response
                        let alertController = UIAlertController(title: "Error", message: "Unexpected response", preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                        self.present(alertController, animated: true, completion: nil)
                    }
                }
            }.resume()
        }
    }
    
    @IBAction func doneButtonTapped(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
}

