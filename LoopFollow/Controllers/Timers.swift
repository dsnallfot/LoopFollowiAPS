//
//  Timers.swift
//  LoopFollow
//
//  Created by Jon Fawcett on 9/3/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//

import Foundation
import UIKit

extension MainViewController {

    // Runs a 60 second timer when an alarm is snoozed
    // Prevents the alarm from triggering again while saving the snooze time to settings
    // End function needs nothing done
    func startGraphNowTimer(time: TimeInterval = 60) {
        
        graphNowTimer = Timer.scheduledTimer(timeInterval: time,
                                               target: self,
                                               selector: #selector(MainViewController.graphNowTimerDidEnd(_:)),
                                               userInfo: nil,
                                               repeats: true)
    }
    
    @objc func graphNowTimerDidEnd(_ timer:Timer) {
        createVerticalLines()
    }
    
    // Runs a 60 second timer when an alarm is snoozed
    // Prevents the alarm from triggering again while saving the snooze time to settings
    // End function needs nothing done
    func startCheckAlarmTimer(time: TimeInterval = 60) {
        
        checkAlarmTimer.invalidate()
        checkAlarmTimer = Timer.scheduledTimer(timeInterval: time,
                                               target: self,
                                               selector: #selector(MainViewController.checkAlarmTimerDidEnd(_:)),
                                               userInfo: nil,
                                               repeats: false)
    }
    
    @objc func checkAlarmTimerDidEnd(_ timer:Timer) {
    }

    // Cancel and reset the playing alarm if it has not been snoozed after 4 min 50 seconds.
    // This allows the next BG reading to either start the timer going or not fire if the situation has been resolved
    func startAlarmPlayingTimer(time: TimeInterval = 290) {
        alarmPlayingTimer?.invalidate()
        alarmPlayingTimer = Timer.scheduledTimer(timeInterval: time,
                                           target: self,
                                           selector: #selector(MainViewController.alarmPlayingTimerDidEnd(_:)),
                                           userInfo: nil,
                                           repeats: false)
    }
    
    @objc func alarmPlayingTimerDidEnd(_ timer: Timer) {
        guard timer === alarmPlayingTimer else { return }
        // Oavsett om ljudet fortfarande spelar eller inte vill vi:
        // - nollställa whichAlarm
        // - uppdatera Snooze-vyn
        // - gömma Snooze-knapp + AlertLabel
        // - och bara stoppa ljudet om det faktiskt spelar
        stopAlarmAtNextReading()
    }
}
