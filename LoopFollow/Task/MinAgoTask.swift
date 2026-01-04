//
//  MinAgoTask.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-11.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//


import Foundation
import UIKit

extension Notification.Name {
    static let minAgoTextUpdated = Notification.Name("minAgoTextUpdated")
}

extension MainViewController {
    func scheduleMinAgoTask(initialDelay: TimeInterval = 1.0) {
        let firstRun = Date().addingTimeInterval(initialDelay)
        TaskScheduler.shared.scheduleTask(id: .minAgoUpdate, nextRun: firstRun) { [weak self] in
            guard let self = self else { return }
            self.minAgoTaskAction()
        }
    }
    func minAgoTaskAction() {
        
/* Revertat ändring i 2f66847 & 94ad3e9 pga sämre UX
        // MinAgo is UI-only. Avoid frequent work when backgrounded.
        let appState = UIApplication.shared.applicationState
        if appState == .background {
            // Slow cadence while backgrounded (5 min).
            TaskScheduler.shared.rescheduleTask(id: .minAgoUpdate,
                                                to: Date().addingTimeInterval(300))
            return
        }
*/

        guard bgData.count > 0, let lastBG = bgData.last else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.MinAgoText.text = ""
                self.latestMinAgoString = ""
                if let snoozer = self.tabBarController?.viewControllers?[2] as? SnoozeViewController {
                    snoozer.MinAgoLabel.text = ""
                    snoozer.BGLabel.text = ""
                    snoozer.BGLabel.attributedText = NSAttributedString(string: "")
                }
            }
            // Also notify SwiftUI views that minAgo is unavailable
            NotificationCenter.default.post(name: .minAgoTextUpdated, object: nil, userInfo: ["text": "", "short": ""])
            TaskScheduler.shared.rescheduleTask(id: .minAgoUpdate, to: Date().addingTimeInterval(1))
            return
        }

        let bgSeconds = lastBG.date
        let now = Date()
        let secondsAgo = now.timeIntervalSince1970 - bgSeconds

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .dropLeading

        let displayText: String

        if (secondsAgo >= 0 && secondsAgo < 60) {
            // Display only seconds with "s sedan"
            formatter.allowedUnits = [.second]
            let formattedDuration = formatter.string(from: secondsAgo) ?? ""
            displayText = formattedDuration + " sek sedan"
        } else if (secondsAgo >= 60 && secondsAgo < 300) {
            // Display only minutes with "m sedan"
            formatter.allowedUnits = [.minute]
            let formattedDuration = formatter.string(from: secondsAgo) ?? ""
            displayText = formattedDuration + " min sedan"
        } else if (secondsAgo >= 300 && secondsAgo < 360) {
            // Display minutes and seconds with "m sedan"
            formatter.allowedUnits = [.minute, .second]
            let formattedDuration = formatter.string(from: secondsAgo) ?? ""
            displayText = formattedDuration + " m sedan"
        } else {
            // Display only minutes with "min sedan" and strike-through after 360 seconds
            formatter.allowedUnits = [.minute]
            let formattedDuration = formatter.string(from: secondsAgo) ?? ""
            displayText = formattedDuration + " min sedan"
        }

        let shortText: String = {
            if secondsAgo >= 0 && secondsAgo < 60 {
                return "\(Int(secondsAgo))s"
            }
            if secondsAgo >= 300 && secondsAgo < 360 {
                // show m:s in the 5–6 min band where you already show seconds
                let m = Int(secondsAgo) / 60
                let s = Int(secondsAgo) % 60
                return "\(m):\(String(format: "%02d", s))"
            }
            // default: minutes
            return "\(Int(secondsAgo / 60))m"
        }()

        // Debug logging for minAgo calculation
        /*LogManager.shared.log(
            category: .analysis,
            message: "[MinAgo] lastBG.ts=\(bgSeconds), secondsAgo=\(secondsAgo), latestMinAgoString='\(latestMinAgoString)', newDisplayText='\(displayText)'",
            isDebug: true
        )
         */
        // Update UI only if the display text has changed
        if displayText != latestMinAgoString {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.MinAgoText.text = displayText
                self.latestMinAgoString = displayText

                // Notify SwiftUI views (e.g. BackgroundRefreshSettingsView) to update their minAgo label
                NotificationCenter.default.post(name: .minAgoTextUpdated, object: nil, userInfo: ["text": displayText, "short": shortText])

                if let snoozer = self.tabBarController?.viewControllers?[2] as? SnoozeViewController {
                    snoozer.MinAgoLabel.text = displayText

                    let bgLabelText = snoozer.BGLabel.text ?? ""
                    let attributeString = NSMutableAttributedString(string: bgLabelText)
                    attributeString.addAttribute(.strikethroughStyle,
                                                 value: NSUnderlineStyle.single.rawValue,
                                                 range: NSRange(location: 0, length: attributeString.length))
                    attributeString.addAttribute(.strikethroughColor,
                                                 value: secondsAgo >= 660 ? UIColor.systemRed : (secondsAgo >= 360 ? UIColor.label : UIColor.clear),
                                                 range: NSRange(location: 0, length: attributeString.length))
                    snoozer.BGLabel.attributedText = attributeString
                }
            }
        }

        // Determine the next run interval based on the current state
        let nextUpdateInterval: TimeInterval
        if (secondsAgo >= 0 && secondsAgo < 60) || (secondsAgo >= 300 && secondsAgo < 360) {
            // Update every second when showing seconds
            nextUpdateInterval = 1.0
        } else {
            // Update at the next minute boundary
            let secondsToNextMinute = 60.0 - (secondsAgo.truncatingRemainder(dividingBy: 60.0))
            nextUpdateInterval = secondsToNextMinute
        }

        // Ensure the next update interval is not negative or too small
        let safeNextInterval = max(nextUpdateInterval, 1.0)

        TaskScheduler.shared.rescheduleTask(id: .minAgoUpdate, to: Date().addingTimeInterval(safeNextInterval))
    }
}
