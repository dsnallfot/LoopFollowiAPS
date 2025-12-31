//
//  SMSRemoteViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2024-03-21.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import UIKit

class SMSRemoteViewController: ThemedViewController, RemoteSettingsDelegate {
    var appStateController: AppStateController?
    
    @IBOutlet weak var customActionButton: UIButton!
    @IBOutlet weak var remoteBolusButton: UIButton!
    @IBOutlet weak var remoteMealButton: UIButton!
    @IBOutlet weak var remoteOverrideButton: UIButton!
    @IBOutlet weak var remoteTempButton: UIButton!
    @IBOutlet weak var methodButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
        // Re-apply theme after potential style override
        updateBackgroundForCurrentMode()
        // Initial UI setup based on hideRemoteBolus and hide hideRemoteCustom value
        updateUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateMethodButtonImage()
    }

    private func updateMethodButtonImage() {
        let currentMethod = UserDefaultsRepository.method.value
        if currentMethod == "SMS API" {
            methodButton.setImage(UIImage(named: "twilio"), for: .normal)
        } else {
            methodButton.setImage(UIImage(named: "shortcuts"), for: .normal)
        }
    }
        
        // Function to update UI based on hideRemoteBolus value
        func updateUI() {
            let isRemoteBolusHidden = UserDefaultsRepository.hideRemoteBolus.value
            remoteBolusButton.isHidden = isRemoteBolusHidden

            let isCustomActionsHidden = UserDefaultsRepository.hideRemoteCustomActions.value
                    customActionButton.isHidden = isCustomActionsHidden
    }
    
    // MARK: - RemoteSettingsDelegate
        func remoteSettingsDidUpdateMethod() {
            updateMethodButtonImage()
        }
    
    @IBAction func customActionButtonPressed(_ sender: Any) {
        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
            let customActionViewController = storyboard!.instantiateViewController(withIdentifier: "remoteCustomAction") as! CustomActionViewController
            self.present(customActionViewController, animated: true, completion: nil)
    }
    
    @IBAction func mealButtonPressed(_ sender: Any) {
        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        let mealViewController = storyboard!.instantiateViewController(withIdentifier: "remoteMeal") as! MealViewController
        self.present(mealViewController, animated: true, completion: nil)
    }
    
    @IBAction func bolusButtonPressed(_ sender: Any) {
        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        let bolusViewController = storyboard!.instantiateViewController(withIdentifier: "remoteBolus") as! BolusViewController
        self.present(bolusViewController, animated: true, completion: nil)
    }
    
    @IBAction func overrideButtonPressed(_ sender: Any) {
        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        let overrideViewController = storyboard!.instantiateViewController(withIdentifier: "remoteOverride") as! OverrideViewController
        self.present(overrideViewController, animated: true, completion: nil)
    }
    
    @IBAction func tempTargetButtonPressed(_ sender: Any) {
        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        let tempTargetViewController = storyboard!.instantiateViewController(withIdentifier: "remoteTempTarget") as! TempTargetViewController
        self.present(tempTargetViewController, animated: true, completion: nil)
    }
    
    @IBAction func remoteSettingsButtonTapped(_ sender: Any) {
        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
            let remoteSettingsViewController = storyboard!.instantiateViewController(withIdentifier: "remoteSettings") as! RemoteSettingsViewController
            // Set self as the delegate
            remoteSettingsViewController.delegate = self
            self.present(remoteSettingsViewController, animated: true, completion: nil)
        }
    
    @IBAction func methodButtonTapped(_ sender: Any) {
        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        let remoteSettingsViewController = storyboard!.instantiateViewController(withIdentifier: "remoteSettings") as! RemoteSettingsViewController
        // Set self as the delegate
        remoteSettingsViewController.delegate = self
        self.present(remoteSettingsViewController, animated: true, completion: nil)
    }
    
    @IBAction func calendarButtonTapped(_ sender: Any) {
        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        let urlString = "shortcuts://run-shortcut?name=Hälsologgning"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
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
    
    // Function to hide the customaction button
    func hideCustomActionButton() {
        customActionButton.isHidden = true
    }
    
    // Function to show the customaction button
        func showCustomActionButton() {
            customActionButton.isHidden = false
    }
}
