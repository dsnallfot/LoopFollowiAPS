//
//  RemoteViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2024-03-21.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import UIKit

class RemoteViewController: UIViewController {
    
    @IBOutlet weak var customPresetButton: UIButton!
    @IBOutlet weak var remoteBolusButton: UIButton!
    
    let method = UserDefaultsRepository.method.value
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
            
            // Initial UI setup based on hideRemoteBolus and hide hideRemoteCustom value
            updateUI()
        }
        
        // Function to update UI based on hideRemoteBolus value
        func updateUI() {
            let isRemoteBolusHidden = UserDefaultsRepository.hideRemoteBolus.value
            remoteBolusButton.isHidden = isRemoteBolusHidden

        let isCustomPresetHidden = UserDefaultsRepository.hideRemoteCustom.value
        customPresetButton.isHidden = isCustomPresetHidden
    }
    
    @IBAction func presetButtonPressed(_ sender: Any) {
        let customViewController = storyboard!.instantiateViewController(withIdentifier: "remoteCustom") as! CustomViewController
        self.present(customViewController, animated: true, completion: nil)
    }
    
    @IBAction func mealButtonPressed(_ sender: Any) {
        let mealViewController = storyboard!.instantiateViewController(withIdentifier: "remoteMeal") as! MealViewController
        self.present(mealViewController, animated: true, completion: nil)
    }
    
    @IBAction func bolusButtonPressed(_ sender: Any) {
        let bolusViewController = storyboard!.instantiateViewController(withIdentifier: "remoteBolus") as! BolusViewController
        self.present(bolusViewController, animated: true, completion: nil)
    }
    
    @IBAction func overrideButtonPressed(_ sender: Any) {
        let overrideViewController = storyboard!.instantiateViewController(withIdentifier: "remoteOverride") as! OverrideViewController
        self.present(overrideViewController, animated: true, completion: nil)
    }
    
    @IBAction func tempTargetButtonPressed(_ sender: Any) {
        let tempTargetViewController = storyboard!.instantiateViewController(withIdentifier: "remoteTempTarget") as! TempTargetViewController
        self.present(tempTargetViewController, animated: true, completion: nil)
    }
    
    @IBAction func remoteSettingsButtonTapped(_ sender: Any) {
        let remoteSettingsViewController = storyboard!.instantiateViewController(withIdentifier: "remoteSettings") as! RemoteSettingsViewController
        self.present(remoteSettingsViewController, animated: true, completion: nil)
    }
    
    @IBAction func calendarButtonTapped(_ sender: Any) {
        //Check to see if the input method is SMS API or something else
        //If SMS API, do not use shortcuts - use Nightscout API instead
        if method == "SMS API" {
            //Eventually, display a pop up to capture note text and send it off via Nightscout API
            return
        }
        //If not SMS API, we must be in the Shortcut world - so trigger the Shortcut
        else {
            let urlString = "shortcuts://run-shortcut?name=Healthlog"
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
    
    // Function to hide the bolus button
    func hideRemoteBolusButton() {
        remoteBolusButton.isHidden = true
    }
    
    // Function to show the bolus button
    func showRemoteBolusButton() {
        remoteBolusButton.isHidden = false
    }
    
    // Function to hide the custompreset button
    func hideCustomPresetButton() {
        customPresetButton.isHidden = true
    }
    
    // Function to show the custompreset button
    func showCustomPresetButton() {
        customPresetButton.isHidden = false
    }
}
