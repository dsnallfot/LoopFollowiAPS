//
//  SnoozeViewController.swift
//  LoopFollow
//
//  Created by Jon Fawcett on 6/1/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//

import UIKit
import UserNotifications
import SwiftUI


//class SnoozeViewController: ThemedViewController, UNUserNotificationCenterDelegate { // Använd inte blå gradient för snooze-vyn eftersom den blir för ljus på natten
class SnoozeViewController: UIViewController, UNUserNotificationCenterDelegate {
    var appStateController: AppStateController?
    var snoozeTabItem: UITabBarItem = UITabBarItem()
    var mainTabItem: UITabBarItem = UITabBarItem()
    var clockTimer: Timer = Timer()
    
   
    
    @IBOutlet weak var SnoozeButton: UIButton!

    @IBOutlet weak var BGLabel: UILabel!
    @IBOutlet weak var DirectionLabel: UILabel!
    @IBOutlet weak var DeltaLabel: UILabel!
    @IBOutlet weak var MinAgoLabel: UILabel!
    @IBOutlet weak var AlertLabel: UILabel!
    @IBOutlet weak var clockLabel: UILabel!
    @IBOutlet weak var snoozeForMinuteLabel: UILabel!
    @IBOutlet weak var snoozeForMinuteUnit: UILabel!
    @IBOutlet weak var snoozeForMinuteStepper: UIStepper!
    @IBOutlet weak var debugTextView: UITextView!
    
    @IBOutlet weak var InfoButton: UIButton!
    @IBOutlet weak var BGView: UIStackView!

    // 🦄 Unicorn overlay behind BGView contents (Snoozer)
    private let unicornLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "🦄"
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 360, weight: .regular)
        label.alpha = 0.0 // hidden by default
        return label
    }()
    
    // 🤲 6–7 hands overlay behind BGView contents (Snoozer)
    private let hands67ImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.image = UIImage(named: "67handsHigh")
        iv.contentMode = .scaleAspectFit
        iv.alpha = 0.0
        return iv
    }()
    
    // 🎯 target logo overlay behind BGView contents (Snoozer)
    private let targetLogoImageView: UIImageView = {
        let iv2 = UIImageView()
        iv2.translatesAutoresizingMaskIntoConstraints = false
        iv2.image = UIImage(named: "target")
        iv2.contentMode = .scaleAspectFit
        iv2.alpha = 0.0
        return iv2
    }()
    
    @IBOutlet weak var AlarmsButton: UIButton!
    
    @IBAction func SnoozeButton(_ sender: Any) {
        AlarmSound.stop()
        
        guard let mainVC = self.tabBarController!.viewControllers?[0] as? MainViewController else { return }
        mainVC.startCheckAlarmTimer(time: mainVC.checkAlarmInterval)
        
        let tabBarControllerItems = self.tabBarController?.tabBar.items
        if let arrayOfTabBarItems = tabBarControllerItems as! AnyObject as? NSArray{
            snoozeTabItem = arrayOfTabBarItems[2] as! UITabBarItem
            
        }
        
        
        setSnoozeTime()
        AlertLabel.isHidden = true
        SnoozeButton.isHidden = true
        clockLabel.isHidden = false
        snoozeForMinuteStepper.isHidden = true
        snoozeForMinuteLabel.isHidden = true
        snoozeForMinuteUnit.isHidden = true
        
    }
    
    @IBAction func snoozeForMinuteValChanged(_ sender: UIStepper) {
        snoozeForMinuteLabel.text = Int(sender.value).description
    }
    
    @IBAction func InfoButtonTapped(_ sender: Any) {
        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        let vc = UIHostingController(rootView: SnoozeStatusView())
        vc.modalPresentationStyle = .pageSheet
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        self.present(vc, animated: true)
    }
    
    // Update Time
    func startClockTimer(time: TimeInterval) {
        clockTimer = Timer.scheduledTimer(timeInterval: time,
                                           target: self,
                                           selector: #selector(clockTimerDidEnd(_:)),
                                           userInfo: nil,
                                           repeats: true)
    }
    
    // Update Time Ended
    @objc func clockTimerDidEnd(_ timer:Timer) {
        let formatter = DateFormatter()
        if dateTimeUtils.is24Hour() {
            formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("hh:mm a")
        }
        
        clockLabel.text = formatter.string(from: Date())
    }
    
    func updateDisplayWhenTriggered(bgVal: String, directionVal: String, deltaVal: String, minAgoVal: String, alertLabelVal: String, latestIOB: String, latestCOB: String) {
        loadViewIfNeeded()

        // Replace commas with periods in bgVal and deltaVal
        let bgValWithPeriod = bgVal.replacingOccurrences(of: ",", with: ".")
        let deltaValWithPeriod = deltaVal.replacingOccurrences(of: ",", with: ".")

        // Normalize LOW/HIGH so Snoozer always shows "LÅG" / "HÖG"
        // Callers may pass either mmol/L (e.g. 2.2 / 22.2) or mg/dL (e.g. 40 / 400) display strings.
        let normalizedBGDisplay: String = {
            // Fast path for exact strings
            if bgValWithPeriod == "2.2" || bgValWithPeriod == "40" {
                return "LÅG"
            }
            if bgValWithPeriod == "22.2" || bgValWithPeriod == "400" {
                return "HÖG"
            }

            // Tolerant numeric check (guards against formatting like "2.20")
            if let v = Double(bgValWithPeriod) {
                if abs(v - 2.2) < 0.0001 || abs(v - 40.0) < 0.0001 { return "LÅG" }
                if abs(v - 22.2) < 0.0001 || abs(v - 400.0) < 0.0001 { return "HÖG" }
            }
            return bgValWithPeriod
        }()

        BGLabel.text = normalizedBGDisplay
        // 🦄 Show/hide unicorn for exactly 5.5 mmol/L
        updateUnicornVisibility(forBGDisplayString: normalizedBGDisplay)
        update67HandsVisibility(forBGDisplayString: normalizedBGDisplay)
        updateTargetLogoVisibility(forBGDisplayString: normalizedBGDisplay)
        DirectionLabel.text = directionVal
        DeltaLabel.text = deltaValWithPeriod
        MinAgoLabel.text = minAgoVal
        AlertLabel.text = alertLabelVal
        if alertLabelVal == "none" { return }
        sendNotification(self, bgVal: bgVal, directionVal: directionVal, deltaVal: deltaVal, minAgoVal: minAgoVal, alertLabelVal: alertLabelVal, latestIOB: latestIOB, latestCOB: latestCOB)
    }
    
    func sendNotification(_ sender: Any, bgVal: String, directionVal: String, deltaVal: String, minAgoVal: String, alertLabelVal: String, latestIOB: String, latestCOB: String) {
        UNUserNotificationCenter.current().delegate = self
        
        // Replace commas with periods in bgVal and deltaVal
        let bgValUpdated = bgVal.replacingOccurrences(of: ",", with: ".")
        let deltaValUpdated = deltaVal.replacingOccurrences(of: ",", with: ".")
        
        let content = UNMutableNotificationContent()
        content.title = alertLabelVal
        content.subtitle += bgValUpdated + " "
        content.subtitle += directionVal + " "
        content.subtitle += deltaValUpdated + " • IOB: "
        content.subtitle += latestIOB + " COB: "
        content.subtitle += latestCOB
        content.categoryIdentifier = "category"        // This is needed to trigger vibrate on watch and phone
        // TODO:
        // See if we can use .Critcal
        // See if we should use this method instead of direct sound player
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        
        let action = UNNotificationAction(identifier: "snooze", title: "Snooze", options: [])
        let category = UNNotificationCategory(identifier: "category", actions: [action], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "snooze" {
            SnoozeButton(self)
        }
    }
    
    func setSnoozeTime() {
        guard let alarms = ViewControllerManager.shared.alarmViewController else { return }

        let snoozeDuration = TimeInterval(snoozeForMinuteStepper.value * 60)
        let longSnoozeDuration = TimeInterval(snoozeForMinuteStepper.value * 60 * 60)
        let currentDate = Date()

        switch AlarmSound.whichAlarm {
        case "⚠️ Tillfällig varning":
            UserDefaultsRepository.alertTemporaryActive.value = false
            alarms.reloadIsSnoozed(key: "alertTemporaryActive", value: false)

        case "🆘 Akut lågt!",
             "🆘 Akut lågt! (Comp. low?)":
            UserDefaultsRepository.alertUrgentLowIsSnoozed.value = true
            UserDefaultsRepository.alertUrgentLowSnoozedTime.value = currentDate.addingTimeInterval(snoozeDuration)
            alarms.reloadIsSnoozed(key: "alertUrgentLowIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertUrgentLowSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(snoozeDuration))

        case "🔴 Lågt socker",
             "🔴 Lågt socker (Comp. low?)":
            UserDefaultsRepository.alertLowIsSnoozed.value = true
            UserDefaultsRepository.alertLowSnoozedTime.value = currentDate.addingTimeInterval(snoozeDuration)
            alarms.reloadIsSnoozed(key: "alertLowIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertLowSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(snoozeDuration))

        case "⚠️ Snart akut låg!",
             "⚠️ Snart akut låg! (Comp. low?)":
            UserDefaultsRepository.alertUrgentLowIsSnoozed.value = true
            UserDefaultsRepository.alertUrgentLowSnoozedTime.value = currentDate.addingTimeInterval(snoozeDuration)
            alarms.reloadIsSnoozed(key: "alertUrgentLowIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertUrgentLowSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(snoozeDuration))

        case "🟣 Högt socker":
            UserDefaultsRepository.alertHighIsSnoozed.value = true
            UserDefaultsRepository.alertHighSnoozedTime.value = currentDate.addingTimeInterval(snoozeDuration)
            alarms.reloadIsSnoozed(key: "alertHighIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertHighSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(snoozeDuration))

        case "⚠️ Akut högt!":
            UserDefaultsRepository.alertUrgentHighIsSnoozed.value = true
            UserDefaultsRepository.alertUrgentHighSnoozedTime.value = currentDate.addingTimeInterval(snoozeDuration)
            alarms.reloadIsSnoozed(key: "alertUrgentHighIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertUrgentHighSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(snoozeDuration))

        case "⏬ Sjunker snabbt":
            UserDefaultsRepository.alertFastDropIsSnoozed.value = true
            UserDefaultsRepository.alertFastDropSnoozedTime.value = currentDate.addingTimeInterval(snoozeDuration)
            alarms.reloadIsSnoozed(key: "alertFastDropIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertFastDropSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(snoozeDuration))

        case "⏫ Stiger snabbt":
            UserDefaultsRepository.alertFastRiseIsSnoozed.value = true
            UserDefaultsRepository.alertFastRiseSnoozedTime.value = currentDate.addingTimeInterval(snoozeDuration)
            alarms.reloadIsSnoozed(key: "alertFastRiseIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertFastRiseSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(snoozeDuration))

        case "⚠️ Inga värden":
            UserDefaultsRepository.alertMissedReadingIsSnoozed.value = true
            UserDefaultsRepository.alertMissedReadingSnoozedTime.value = currentDate.addingTimeInterval(snoozeDuration)
            alarms.reloadIsSnoozed(key: "alertMissedReadingIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertMissedReadingSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(snoozeDuration))

        case "⏰ Påminnelse sensorbyte":
            UserDefaultsRepository.alertSAGEIsSnoozed.value = true
            UserDefaultsRepository.alertSAGESnoozedTime.value = currentDate.addingTimeInterval(longSnoozeDuration)
            alarms.reloadIsSnoozed(key: "alertSAGEIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertSAGESnoozedTime", setNil: false, value: currentDate.addingTimeInterval(longSnoozeDuration))

        case "⏰ Påminnelse pumpbyte":
            UserDefaultsRepository.alertCAGEIsSnoozed.value = true
            UserDefaultsRepository.alertCAGESnoozedTime.value = currentDate.addingTimeInterval(longSnoozeDuration)
            alarms.reloadIsSnoozed(key: "alertCAGEIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertCAGESnoozedTime", setNil: false, value: currentDate.addingTimeInterval(longSnoozeDuration))

        case "❌ Loop ej aktiv!":
            UserDefaultsRepository.alertNotLoopingIsSnoozed.value = true
            UserDefaultsRepository.alertNotLoopingSnoozedTime.value = currentDate.addingTimeInterval(snoozeDuration)
            alarms.reloadIsSnoozed(key: "alertNotLoopingIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertNotLoopingSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(snoozeDuration))

        case "⚠️ Missad måltidsbolus":
            UserDefaultsRepository.alertMissedBolusIsSnoozed.value = true
            UserDefaultsRepository.alertMissedBolusSnoozedTime.value = currentDate.addingTimeInterval(snoozeDuration)
            alarms.reloadIsSnoozed(key: "alertMissedBolusIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertMissedBolusSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(snoozeDuration))

        case "⚠️ Låg insulinnivå":
            UserDefaultsRepository.alertPumpIsSnoozed.value = true
            UserDefaultsRepository.alertPumpSnoozedTime.value = currentDate.addingTimeInterval(longSnoozeDuration)
            alarms.reloadIsSnoozed(key: "alertPumpIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertPumpSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(longSnoozeDuration))

        case "💉 IOB Varning":
            UserDefaultsRepository.alertIOBIsSnoozed.value = true
            UserDefaultsRepository.alertIOBSnoozedTime.value = currentDate.addingTimeInterval(longSnoozeDuration)
            alarms.reloadIsSnoozed(key: "alertIOBIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertIOBSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(longSnoozeDuration))

        case "🥨 COB Varning":
            UserDefaultsRepository.alertCOBIsSnoozed.value = true
            UserDefaultsRepository.alertCOBSnoozedTime.value = currentDate.addingTimeInterval(longSnoozeDuration)
            alarms.reloadIsSnoozed(key: "alertCOBIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertCOBSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(longSnoozeDuration))

        case "🪫 Låg batterinivå":
            UserDefaultsRepository.alertBatteryIsSnoozed.value = true
            UserDefaultsRepository.alertBatterySnoozedTime.value = currentDate.addingTimeInterval(longSnoozeDuration)
            alarms.reloadIsSnoozed(key: "alertBatteryIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertBatterySnoozedTime", setNil: false, value: currentDate.addingTimeInterval(longSnoozeDuration))

        case "👉 Rek. Bolus":
            UserDefaultsRepository.alertRecBolusIsSnoozed.value = true
            UserDefaultsRepository.alertRecBolusSnoozedTime.value = currentDate.addingTimeInterval(snoozeDuration)
            alarms.reloadIsSnoozed(key: "alertRecBolusIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertRecBolusSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(snoozeDuration))

        case "▶️ Temp Target Start":
            UserDefaultsRepository.alertTempTargetStartIsSnoozed.value = true
            UserDefaultsRepository.alertTempTargetStartSnoozedTime.value = currentDate.addingTimeInterval(snoozeDuration)
            alarms.reloadIsSnoozed(key: "alertTempTargetStartIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertTempTargetStartSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(snoozeDuration))

        case "⏹️ Temp Target End":
            UserDefaultsRepository.alertTempTargetEndIsSnoozed.value = true
            UserDefaultsRepository.alertTempTargetEndSnoozedTime.value = currentDate.addingTimeInterval(snoozeDuration)
            alarms.reloadIsSnoozed(key: "alertTempTargetEndIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertTempTargetEndSnoozedTime", setNil: false, value: currentDate.addingTimeInterval(snoozeDuration))

        default:
            LogManager.shared.log(category: .alarm, message: "Unhandled alarm: \(AlarmSound.whichAlarm)")
        }
    }

    func setPresnoozeNight(snoozeTime: Date) {
        guard let alarms = ViewControllerManager.shared.alarmViewController else { return }

        if UserDefaultsRepository.alertUrgentLowAutosnoozeNight.value {
            UserDefaultsRepository.alertUrgentLowIsSnoozed.value = true
            UserDefaultsRepository.alertUrgentLowSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertUrgentLowIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertUrgentLowSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertLowAutosnoozeNight.value {
            UserDefaultsRepository.alertLowIsSnoozed.value = true
            UserDefaultsRepository.alertLowSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertLowIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertLowSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertHighAutosnoozeNight.value {
            UserDefaultsRepository.alertHighIsSnoozed.value = true
            UserDefaultsRepository.alertHighSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertHighIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertHighSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertUrgentHighAutosnoozeNight.value {
            UserDefaultsRepository.alertUrgentHighIsSnoozed.value = true
            UserDefaultsRepository.alertUrgentHighSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertUrgentHighIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertUrgentHighSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertMissedReadingAutosnoozeNight.value {
            UserDefaultsRepository.alertMissedReadingIsSnoozed.value = true
            UserDefaultsRepository.alertMissedReadingSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertMissedReadingIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertMissedReadingSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertFastDropAutosnoozeNight.value {
            UserDefaultsRepository.alertFastDropIsSnoozed.value = true
            UserDefaultsRepository.alertFastDropSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertFastDropIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertFastDropSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertFastRiseAutosnoozeNight.value {
            UserDefaultsRepository.alertFastRiseIsSnoozed.value = true
            UserDefaultsRepository.alertFastRiseSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertFastRiseIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertFastRiseSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertNotLoopingAutosnoozeNight.value {
            UserDefaultsRepository.alertNotLoopingIsSnoozed.value = true
            UserDefaultsRepository.alertNotLoopingSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertNotLoopingIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertNotLoopingSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertMissedBolusAutosnoozeNight.value {
            UserDefaultsRepository.alertMissedBolusIsSnoozed.value = true
            UserDefaultsRepository.alertMissedBolusSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertMissedBolusIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertMissedBolusSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertOverrideStartAutosnoozeNight.value {
            UserDefaultsRepository.alertOverrideStartIsSnoozed.value = true
            UserDefaultsRepository.alertOverrideStartSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertOverrideStartIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertOverrideStartSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertOverrideEndAutosnoozeNight.value {
            UserDefaultsRepository.alertOverrideEndIsSnoozed.value = true
            UserDefaultsRepository.alertOverrideEndSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertOverrideEndIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertOverrideEndSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertCAGEAutosnoozeNight.value {
            UserDefaultsRepository.alertCAGEIsSnoozed.value = true
            UserDefaultsRepository.alertCAGESnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertCAGEIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertCAGESnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertSAGEAutosnoozeNight.value {
            UserDefaultsRepository.alertSAGEIsSnoozed.value = true
            UserDefaultsRepository.alertSAGESnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertSAGEIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertSAGESnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertPumpAutosnoozeNight.value {
            UserDefaultsRepository.alertPumpIsSnoozed.value = true
            UserDefaultsRepository.alertPumpSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertPumpIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertPumpSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertIOBAutosnoozeNight.value {
            UserDefaultsRepository.alertIOBIsSnoozed.value = true
            UserDefaultsRepository.alertIOBSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertIOBIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertIOBSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertCOBAutosnoozeNight.value {
            UserDefaultsRepository.alertCOBIsSnoozed.value = true
            UserDefaultsRepository.alertCOBSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertCOBIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertCOBSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertTempTargetStartAutosnoozeNight.value {
            UserDefaultsRepository.alertTempTargetStartIsSnoozed.value = true
            UserDefaultsRepository.alertTempTargetStartSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertTempTargetStartIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertTempTargetStartSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertTempTargetEndAutosnoozeNight.value {
            UserDefaultsRepository.alertTempTargetEndIsSnoozed.value = true
            UserDefaultsRepository.alertTempTargetEndSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertTempTargetEndIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertTempTargetEndSnoozedTime", setNil: false, value: snoozeTime)
        }
    }

    func setPreSnoozeDay(snoozeTime: Date) {
        guard let alarms = ViewControllerManager.shared.alarmViewController else { return }

        if UserDefaultsRepository.alertUrgentLowAutosnoozeDay.value {
            UserDefaultsRepository.alertUrgentLowIsSnoozed.value = true
            UserDefaultsRepository.alertUrgentLowSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertUrgentLowIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertUrgentLowSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertLowAutosnoozeDay.value {
            UserDefaultsRepository.alertLowIsSnoozed.value = true
            UserDefaultsRepository.alertLowSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertLowIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertLowSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertHighAutosnoozeDay.value {
            UserDefaultsRepository.alertHighIsSnoozed.value = true
            UserDefaultsRepository.alertHighSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertHighIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertHighSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertUrgentHighAutosnoozeDay.value {
            UserDefaultsRepository.alertUrgentHighIsSnoozed.value = true
            UserDefaultsRepository.alertUrgentHighSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertUrgentHighIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertUrgentHighSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertMissedReadingAutosnoozeDay.value {
            UserDefaultsRepository.alertMissedReadingIsSnoozed.value = true
            UserDefaultsRepository.alertMissedReadingSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertMissedReadingIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertMissedReadingSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertFastDropAutosnoozeDay.value {
            UserDefaultsRepository.alertFastDropIsSnoozed.value = true
            UserDefaultsRepository.alertFastDropSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertFastDropIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertFastDropSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertFastRiseAutosnoozeDay.value {
            UserDefaultsRepository.alertFastRiseIsSnoozed.value = true
            UserDefaultsRepository.alertFastRiseSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertFastRiseIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertFastRiseSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertNotLoopingAutosnoozeDay.value {
            UserDefaultsRepository.alertNotLoopingIsSnoozed.value = true
            UserDefaultsRepository.alertNotLoopingSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertNotLoopingIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertNotLoopingSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertMissedBolusAutosnoozeDay.value {
            UserDefaultsRepository.alertMissedBolusIsSnoozed.value = true
            UserDefaultsRepository.alertMissedBolusSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertMissedBolusIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertMissedBolusSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertOverrideStartAutosnoozeDay.value {
            UserDefaultsRepository.alertOverrideStartIsSnoozed.value = true
            UserDefaultsRepository.alertOverrideStartSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertOverrideStartIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertOverrideStartSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertOverrideEndAutosnoozeDay.value {
            UserDefaultsRepository.alertOverrideEndIsSnoozed.value = true
            UserDefaultsRepository.alertOverrideEndSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertOverrideEndIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertOverrideEndSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertCAGEAutosnoozeDay.value {
            UserDefaultsRepository.alertCAGEIsSnoozed.value = true
            UserDefaultsRepository.alertCAGESnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertCAGEIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertCAGESnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertSAGEAutosnoozeDay.value {
            UserDefaultsRepository.alertSAGEIsSnoozed.value = true
            UserDefaultsRepository.alertSAGESnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertSAGEIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertSAGESnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertPumpAutosnoozeDay.value {
            UserDefaultsRepository.alertPumpIsSnoozed.value = true
            UserDefaultsRepository.alertPumpSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertPumpIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertPumpSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertIOBAutosnoozeDay.value {
            UserDefaultsRepository.alertIOBIsSnoozed.value = true
            UserDefaultsRepository.alertIOBSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertIOBIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertIOBSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertCOBAutosnoozeDay.value {
            UserDefaultsRepository.alertCOBIsSnoozed.value = true
            UserDefaultsRepository.alertCOBSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertCOBIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertCOBSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertTempTargetStartAutosnoozeDay.value {
            UserDefaultsRepository.alertTempTargetStartIsSnoozed.value = true
            UserDefaultsRepository.alertTempTargetStartSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertTempTargetStartIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertTempTargetStartSnoozedTime", setNil: false, value: snoozeTime)
        }
        if UserDefaultsRepository.alertTempTargetEndAutosnoozeDay.value {
            UserDefaultsRepository.alertTempTargetEndIsSnoozed.value = true
            UserDefaultsRepository.alertTempTargetEndSnoozedTime.value = snoozeTime
            alarms.reloadIsSnoozed(key: "alertTempTargetEndIsSnoozed", value: true)
            alarms.reloadSnoozeTime(key: "alertTempTargetEndSnoozedTime", setNil: false, value: snoozeTime)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
        // Re-apply theme after potential style override
        // updateBackgroundForCurrentMode()
        SnoozeButton.layer.cornerRadius = 5
        SnoozeButton.contentEdgeInsets = UIEdgeInsets(top: 10,left: 10,bottom: 10,right: 10)
        // Thin white border around InfoButton
        InfoButton.layer.borderWidth = 0.5
        InfoButton.layer.borderColor = UIColor.systemGray.cgColor
        InfoButton.layer.masksToBounds = true
        applyButtonBordersIfNeeded()
        clockLabel.text = ""
        startClockTimer(time: 1)
        
        //Observe notifications from volume button snoozing and run the same actions and UI changes as when the snoozebutton in SNoozeVC is pressed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVolumeButtonAlarmStopped),
            name: .volumeButtonAlarmStopped,
            object: nil
        )
        setupSwipeUpToStatus()
        // Wire up Alarms button to open AlarmViewController
        AlarmsButton.addTarget(self, action: #selector(alarmsButtonTapped), for: .touchUpInside)
        
        // 🦄 Setup unicorn overlay behind BGView content
        BGView.insertSubview(unicornLabel, at: 0)
        NSLayoutConstraint.activate([
            unicornLabel.centerXAnchor.constraint(equalTo: BGView.centerXAnchor),
            unicornLabel.centerYAnchor.constraint(equalTo: BGView.centerYAnchor)
        ])
        
        // 🤲 Setup 6–7 hands overlay behind BGView content
        BGView.insertSubview(hands67ImageView, at: 0)
        NSLayoutConstraint.activate([
            hands67ImageView.centerXAnchor.constraint(equalTo: BGView.centerXAnchor),
            hands67ImageView.centerYAnchor.constraint(equalTo: BGView.centerYAnchor),
            hands67ImageView.widthAnchor.constraint(equalTo: BGView.widthAnchor, multiplier: 0.95),
            hands67ImageView.heightAnchor.constraint(equalTo: BGView.heightAnchor, multiplier: 0.95)
        ])
        
        // 🎯 Setup target logo overlay behind BGView content
        BGView.insertSubview(targetLogoImageView, at: 0)
        NSLayoutConstraint.activate([
            targetLogoImageView.centerXAnchor.constraint(equalTo: BGView.centerXAnchor),
            targetLogoImageView.centerYAnchor.constraint(equalTo: BGView.centerYAnchor),
            targetLogoImageView.widthAnchor.constraint(equalTo: BGView.widthAnchor, multiplier: 0.95),
            targetLogoImageView.heightAnchor.constraint(equalTo: BGView.heightAnchor, multiplier: 0.95)
        ])
    }

    @IBAction func alarmsButtonTapped(_ sender: Any) {
        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

/*
        guard let alarmVC = ViewControllerManager.shared.alarmViewController else {
            LogManager.shared.log(category: .alarm, message: "AlarmViewController not available when tapping AlarmsButton")
            return
        }
*/
        let alarmVC = ModernAlarmViewController() //kommentera ut ovan guard let... och kommentera in denna rad När vi byggt klart nya alarmvyn
        
        // Always present modally as a sheet that takes the full screen height
        let nav = UINavigationController(rootViewController: alarmVC as UIViewController)
        self.present(nav, animated: true, completion: nil)
        
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyButtonBordersIfNeeded()
    }

    private func applyButtonBordersIfNeeded() {
        // Keep InfoButton border consistent
        InfoButton.layer.borderWidth = 0.5
        InfoButton.layer.borderColor = UIColor.systemGray.cgColor
        InfoButton.layer.masksToBounds = true

        // Apply SnoozeButton border only when visible
        if !SnoozeButton.isHidden {
            SnoozeButton.layer.borderWidth = 0.5
            SnoozeButton.layer.borderColor = UIColor.systemGray.cgColor
            SnoozeButton.layer.masksToBounds = true
        } else {
            // Remove border when hidden to avoid odd states when it reappears
            SnoozeButton.layer.borderWidth = 0
        }
    }
    
    @objc private func handleVolumeButtonAlarmStopped() {
        DispatchQueue.main.async {
            self.loadViewIfNeeded() // säkerställ outlets
            self.setSnoozeTime()
            self.AlertLabel.isHidden = true
            self.SnoozeButton.isHidden = true
            self.clockLabel.isHidden = false
            self.snoozeForMinuteStepper.isHidden = true
            self.snoozeForMinuteLabel.isHidden = true
            self.snoozeForMinuteUnit.isHidden = true
        }
        LogManager.shared.log(category: .volumeButtonSnooze, message: "Snoozing alarm with volume button done and Snoozer UI updated")
    }
    
    private func setupSwipeUpToStatus() {
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUpToStatus(_:)))
        swipeUp.direction = .up
        swipeUp.numberOfTouchesRequired = 1
        swipeUp.cancelsTouchesInView = false // don't steal taps from buttons/steppers
        view.addGestureRecognizer(swipeUp)
    }

    @objc private func handleSwipeUpToStatus(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .ended else { return }
        // Require swipe to start in the lower quarter to minimize accidental triggers
        let startPoint = gesture.location(in: view)
        let lowerThreshold = view.bounds.height * 0.75
        guard startPoint.y >= lowerThreshold else { return }

        // Avoid double-presenting
        guard presentedViewController == nil else { return }

        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Present SnoozeStatusView (same as InfoButtonTapped)
        let vc = UIHostingController(rootView: SnoozeStatusView())
        vc.modalPresentationStyle = .pageSheet
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        self.present(vc, animated: true)
    }
    
    /// Shows a big unicorn behind BGView when BG is exactly 5.5 mmol/L, hides otherwise.
    fileprivate func updateUnicornVisibility(forBGDisplayString bg: String) {
        let shouldShow = (bg == "5.5")
        UIView.animate(withDuration: 0.25) {
            self.unicornLabel.alpha = shouldShow ? 0.5 : 0.0
        }
    }
    
    /// Shows the 6–7 hands image behind BGView when BG is exactly 6.7 mmol/L
    fileprivate func update67HandsVisibility(forBGDisplayString bg: String) {
        let shouldShow = (bg == "6.7")
        UIView.animate(withDuration: 0.25) {
            self.hands67ImageView.alpha = shouldShow ? 0.4 : 0.0
        }
    }
    
    /// Shows the target logo image behind BGView when BG is exactly at target mmol/L,
    /// except when target is 5.5 or 6.7 (those are reserved for unicorn / 67-hands).
    fileprivate func updateTargetLogoVisibility(forBGDisplayString bg: String) {
        let targetMgdl = Double(UserDefaultsRepository.targetLine.value)
        let targetMmolRaw = targetMgdl * GlucoseConversion.mgDlToMmolL

        // Avrunda target till 1 decimal
        let targetMmol = (targetMmolRaw * 10).rounded() / 10

        // Specialvärden som aldrig ska visa target-loggan
        if targetMmol == 5.5 || targetMmol == 6.7 {
            UIView.animate(withDuration: 0.25) {
                self.targetLogoImageView.alpha = 0.0
            }
            return
        }

        let bgValue = Double(bg)
        let shouldShow = bgValue == targetMmol

        UIView.animate(withDuration: 0.25) {
            self.targetLogoImageView.alpha = shouldShow ? 0.25 : 0.0
        }
    }
    
    /// Public-facing helper to update all BG-related easter eggs from outside SnoozeViewController.
    func updateEasterEggs(bgDisplay: String) {
        updateUnicornVisibility(forBGDisplayString: bgDisplay)
        update67HandsVisibility(forBGDisplayString: bgDisplay)
        updateTargetLogoVisibility(forBGDisplayString: bgDisplay)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .volumeButtonAlarmStopped, object: nil)
    }
}
