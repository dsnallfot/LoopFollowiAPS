//
//  OverrideViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2024-03-21.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import UIKit
import AudioToolbox

class TempTargetViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate, TwilioRequestable  {
    var appStateController: AppStateController?
    
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
        
        // Set the initial selected temp target
        selectedTempTarget = tempTargetsOptions[0]
        
        // Register observers for shortcut callback notifications
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutSuccess), name: NSNotification.Name("ShortcutSuccess"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutError), name: NSNotification.Name("ShortcutError"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutCancel), name: NSNotification.Name("ShortcutCancel"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutPasscode), name: NSNotification.Name("ShortcutPasscode"), object: nil)
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
        print("Temp Target Picker selected: \(selectedTempTarget!)")
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

        //New formatting for testing (Use "Remote Temp Target" as trigger word on receiving phone after triggering automation)
        let name = UserDefaultsRepository.caregiverName.value
        let secret = UserDefaultsRepository.remoteSecretCode.value
        let combinedString = "Remote Temp Target\n\(selectedTempTarget)\nInlagt av: \(name)\nHemlig kod: \(secret)"
        print("Combined string:", combinedString)
        
        // Confirmation alert before sending the request
        let confirmationAlert = UIAlertController(title: "Bekräfta tillfälligt mål", message: "Vill du aktivera \(selectedTempTarget)?", preferredStyle: .alert)
        
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
                /*let urlString = "shortcuts://run-shortcut?name=Remote%20Temp%20Target&input=text&text=\(encodedString)"
                if let url = URL(string: urlString) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)*/
            let urlString = "shortcuts://x-callback-url/run-shortcut?name=Remote%20Temp%20Target&input=text&text=\(encodedString)&x-success=\(successEncoded)&x-error=\(errorEncoded)&x-cancel=\(cancelEncoded)"
            
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
        showAlert(title: NSLocalizedString("Lyckades", comment: "Lyckades"), message: NSLocalizedString("Tillfälligt mål-registreringen skickades", comment: "Tillfälligt mål-registreringen skickades"), completion: {
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

