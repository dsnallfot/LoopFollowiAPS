//
//  BolusViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2024-03-21.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import UIKit
import LocalAuthentication
import AudioToolbox

class BolusViewController: UIViewController, UITextFieldDelegate, TwilioRequestable  {
    var appStateController: AppStateController?
    
    @IBOutlet weak var bolusEntryField: UITextField!
    @IBOutlet weak var sendBolusButton: UIButton!
    @IBOutlet weak var bolusAmount: UITextField!
    @IBOutlet weak var bolusUnits: UITextField!
    @IBOutlet weak var minPredBGValue: UITextField!
    @IBOutlet weak var minPredBGStack: UIStackView!
    var isAlertShowing = false // Property to track if alerts are currently showing
    var isButtonDisabled = false // Property to track if the button is currently disabled
    
    var minGuardBG: Decimal = 0.0
    var lowThreshold: Decimal = 0.0
    
    let maxBolus = UserDefaultsRepository.maxBolus.value

    override func viewDidLoad() {
        super.viewDidLoad()
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
        bolusEntryField.delegate = self
        self.focusBolusEntryField()
        
        // Register observers for shortcut callback notifications
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutSuccess), name: NSNotification.Name("ShortcutSuccess"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutError), name: NSNotification.Name("ShortcutError"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutCancel), name: NSNotification.Name("ShortcutCancel"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutPasscode), name: NSNotification.Name("ShortcutPasscode"), object: nil)
        
        // Create a NumberFormatter instance
        let numberFormatter = NumberFormatter()
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = 1
        
        //MinGuardBG & Low Threshold
        let minGuardBG = Decimal(sharedMinGuardBG)
        let lowThreshold = Decimal(Double(UserDefaultsRepository.lowLine.value) * 0.0555)
        
        // Format the MinGuardBG value & low threshold to have one decimal place
        let formattedMinGuardBG = numberFormatter.string(from: NSDecimalNumber(decimal: minGuardBG) as NSNumber) ?? ""
        let formattedLowThreshold = numberFormatter.string(from: NSDecimalNumber(decimal: lowThreshold) as NSNumber) ?? ""
         
        // Set the text field with the formatted value of minGuardBG or "N/A" if formattedMinGuardBG is "0.0"
        minPredBGValue.text = formattedMinGuardBG == "0" ? "N/A" : formattedMinGuardBG
        print("Predicted Min BG: \(formattedMinGuardBG) mmol/L")
        print("Low threshold: \(formattedLowThreshold) mmol/L")
        
        // Check if the value of minPredBG is less than lowThreshold
        if minGuardBG < lowThreshold {
            // Show warning symbol
            minPredBGStack.isHidden = false
        } else {
            // Hide warning symbol
            minPredBGStack.isHidden = true
        }
    }
    func focusBolusEntryField() {
        self.bolusEntryField.becomeFirstResponder()
    }
    
    @IBAction func sendRemoteBolusPressed(_ sender: Any) {
        // Disable the button to prevent multiple taps
        if !isButtonDisabled {
            isButtonDisabled = true
            sendBolusButton.isEnabled = false
        } else {
            return // If button is already disabled, return to prevent double registration
        }
        // Retrieve the maximum bolus value
        let maxBolus = UserDefaultsRepository.maxBolus.value
        
        guard var bolusText = bolusAmount.text, !bolusText.isEmpty else {
            print("Error: Bolus amount not entered")
            return
        }
        
        // Replace all occurrences of ',' with '.'
        bolusText = bolusText.replacingOccurrences(of: ",", with: ".")
        
        guard let bolusValue = Double(bolusText) else {
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
        
        //Let code remain for now - to be cleaned
        if bolusValue > (maxBolus + 0.05) {
            // Play failure sound
            AudioServicesPlaySystemSound(SystemSoundID(1053))
            
            // Format maxBolus to display only one decimal place
            let formattedMaxBolus = String(format: "%.1f", maxBolus)
            
            let alertController = UIAlertController(title: "Max setting exceeded", message: "The maximum allowed bolus of \(formattedMaxBolus) U is exceeded! Please try again with a smaller amount.", preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alertController, animated: true, completion: nil)
            self.handleAlertDismissal() // Enable send button after handling failure to be able to try again
            return
        }
        // Set isAlertShowing to true before showing the alert
                            isAlertShowing = true
        // Confirmation alert before sending the request
        let confirmationAlert = UIAlertController(title: "Bekräfta bolus", message: "Vill du ge \(bolusValue) E bolus?", preferredStyle: .alert)
        
        confirmationAlert.addAction(UIAlertAction(title: "Ja", style: .default, handler: { (action: UIAlertAction!) in
            let method = UserDefaultsRepository.method.value
            
            if method == "SMS API" {
                // Authenticate with Face ID
                self.authenticateWithBiometrics {
                    // Proceed with the request after successful authentication
                    self.sendBolusRequest(bolusValue: bolusValue)
                }
            } else {
                self.sendBolusRequest(bolusValue: bolusValue)
            }
        }))
        
        confirmationAlert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: { (action: UIAlertAction!) in
            // Handle dismissal when "Cancel" is selected
            self.handleAlertDismissal()
        }))
        
        present(confirmationAlert, animated: true, completion: nil)
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
        sendBolusButton.isEnabled = true
        isButtonDisabled = false // Reset button disable status
    }
    
    func sendBolusRequest(bolusValue: Double) {
        
        // Convert bolusValue to string and trim any leading or trailing whitespace
        let trimmedBolusValue = "\(bolusValue)".trimmingCharacters(in: .whitespacesAndNewlines)
        
        //New formatting for testing (Use "Remote Bolus" as trigger word on receiving phone after triggering automation)
        let name = UserDefaultsRepository.caregiverName.value
        let secret = UserDefaultsRepository.remoteSecretCode.value
        let combinedString = "Remote Bolus\nInsulin: \(trimmedBolusValue)E\nInlagt av: \(name)\nHemlig kod: \(secret)"
        print("Combined string:", combinedString)
        
        // Retrieve the method value from UserDefaultsRepository
        let method = UserDefaultsRepository.method.value
        
        // Use combinedString as the text in the URL
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
            
            /*let urlString = "shortcuts://run-shortcut?name=Remote%20Bolus&input=text&text=\(encodedString)"
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)*/
            let urlString = "shortcuts://x-callback-url/run-shortcut?name=Remote%20Bolus&input=text&text=\(encodedString)&x-success=\(successEncoded)&x-error=\(errorEncoded)&x-cancel=\(cancelEncoded)"
            
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
        showAlert(title: NSLocalizedString("Lyckades", comment: "Lyckades"), message: NSLocalizedString("Bolusregistreringen skickades", comment: "Bolusregistreringen skickades"), completion: {
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
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "HelveticaNeue-Medium", size: 20.0)!,
        ]
        
        // Check if bolusText exceeds maxBolus
        if let bolusText = bolusUnits.text?.replacingOccurrences(of: ",", with: "."),
           let bolusValue = Decimal(string: bolusText),
           bolusValue > Decimal(maxBolus) + 0.01 { //add 0.01 to allow entry of = maxBolus due to rounding issues with double and decimals otherwise disable it when bolusValue=maxBolus
            
            // Disable button
            sendBolusButton.isEnabled = false
            
            // Format maxBolus with two decimal places
            let formattedMaxBolus = String(format: "%.2f", UserDefaultsRepository.maxBolus.value)
            
            // Update button title if bolus exceeds maxBolus
            sendBolusButton.setAttributedTitle(NSAttributedString(string: "⛔️ Maxgräns \(formattedMaxBolus) E", attributes: attributes), for: .normal)
        } else {
            // Enable button
            sendBolusButton.isEnabled = true
            
            // Update button title with bolus
            sendBolusButton.setAttributedTitle(NSAttributedString(string: "Skicka Bolus", attributes: attributes), for: .normal)
        }
    }
    
    // Function to update button state
    func updateButtonState() {
        // Disable or enable button based on isButtonDisabled
        sendBolusButton.isEnabled = !isButtonDisabled
    }
    
    @IBAction func cancelButtonPressed(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
}

