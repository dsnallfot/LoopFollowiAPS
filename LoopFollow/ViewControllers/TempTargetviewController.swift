//
//  OverrideViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2024-03-21.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import UIKit

class TempTargetViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    
    @IBOutlet weak var sendTempTargetButton: UIButton!
    @IBOutlet weak var tempTargetsPicker: UIPickerView!
    
    var isAlertShowing = false // Property to track if alerts are currently showing
    var isButtonDisabled = false // Property to track if the button is currently disabled
    
    // Property to store the selected temptarget option
    var selectedTempTarget: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
        // Set the delegate and data source for the UIPickerView
        tempTargetsPicker.delegate = self
        tempTargetsPicker.dataSource = self
        
        // Set the default selected item for the UIPickerView
        tempTargetsPicker.selectRow(0, inComponent: 0, animated: false)
        
        // Set the initial selected override
        selectedTempTarget = tempTargetsOptions[0]
    }
    
    // MARK: - UIPickerViewDataSource
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return tempTargetsOptions.count
    }
    
    // MARK: - UIPickerViewDelegate
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return tempTargetsOptions[row]
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        // Update the selectedTempTarget property when an option is selected
        selectedTempTarget = tempTargetsOptions[row]
        print("Override Picker selected: \(selectedTempTarget!)")
    }
    
    @IBAction func sendRemoteTempTargetPressed(_ sender: Any) {
        // Disable the button to prevent multiple taps
        if !isButtonDisabled {
            isButtonDisabled = true
            sendTempTargetButton.isEnabled = false
        } else {
            return // If button is already disabled, return to prevent double registration
        }
        guard let selectedTempTarget = selectedTempTarget else {
            print("No temp target option selected")
            return
        }
        
        let combinedString = "TempTarget_\(selectedTempTarget)"
        print("Combined string:", combinedString)
        
        // Confirmation alert before sending the request
        let confirmationAlert = UIAlertController(title: "Bekräfta", message: "Vill du aktivera \(selectedTempTarget)?", preferredStyle: .alert)
        
        confirmationAlert.addAction(UIAlertAction(title: "Ja", style: .default, handler: { (action: UIAlertAction!) in
            // Proceed with sending the request
            self.sendTTRequest(combinedString: combinedString)
        }))
        
        confirmationAlert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: { (action: UIAlertAction!) in
            // Handle dismissal when "Cancel" is selected
            self.handleAlertDismissal()
        }))
        
        present(confirmationAlert, animated: true, completion: nil)
    }
    
    // Function to handle alert dismissal
    func handleAlertDismissal() {
        // Enable the button when alerts are dismissed
        isAlertShowing = false
        sendTempTargetButton.isEnabled = true
        isButtonDisabled = false // Reset button disable status
    }
    func sendTTRequest(combinedString: String) {
        
        // Retrieve the method value from UserDefaultsRepository
        let method = UserDefaultsRepository.method.value
        
        // Use combinedString as the text in the URL
        if method != "SMS API" {
                // URL encode combinedString
                guard let encodedString = combinedString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                    print("Failed to encode URL string")
                    return
                }
                let urlString = "shortcuts://run-shortcut?name=Remote%20Temp%20Target&input=text&text=\(encodedString)"
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
                            let alertController = UIAlertController(title: "Fel", message: error.localizedDescription, preferredStyle: .alert)
                            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                            self.present(alertController, animated: true, completion: nil)
                            self.handleAlertDismissal() // Enable send button after handling failure to be able to try again
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
                                self.handleAlertDismissal() // Enable send button after handling failure to be able to try again
                            }
                        } else {
                            // Failure: Show generic error alert for unexpected response
                            let alertController = UIAlertController(title: "Fel", message: "Oväntat svar från servern", preferredStyle: .alert)
                            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                            self.present(alertController, animated: true, completion: nil)
                            self.handleAlertDismissal() // Enable send button after handling failure to be able to try again
                        }
                    }
                }.resume()
            
        }
    }
    
    @IBAction func cancelButtonPressed(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
    
    // Data for the UIPickerView
    lazy var tempTargetsOptions: [String] = {
        let tempTargetsString = UserDefaultsRepository.tempTargetsString.value
        // Split the tempTargetsString by ", " to get individual options
        return tempTargetsString.components(separatedBy: ", ")
    }()
}

