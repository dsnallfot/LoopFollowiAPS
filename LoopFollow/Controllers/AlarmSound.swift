//
//  AlarmSound.swift
//  scoutwatch
//
//  Created by Dirk Hermanns on 03.01.16.
//  Copyright © 2016 private. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/*
 * Class that handles the playing and the volume of the alarm sound.
 */
class AlarmSound {
    
    static var isPlaying: Bool {
        return self.audioPlayer?.isPlaying == true
    }
    
    static var isMuted: Bool {
        return self.muted
    }
    static var whichAlarm: String = "none"
    static var soundFile = "Indeed"
    static var isTesting: Bool = false
    
    //static let volumeChangeDetector = VolumeChangeDetector()
    
    static let vibrate = UserDefaultsRepository.vibrate
    
    fileprivate static var systemOutputVolumeBeforeOverride: Float?
    
    fileprivate static var soundURL = Bundle.main.url(forResource: "Indeed", withExtension: "caf")!
    fileprivate static var audioPlayer: AVAudioPlayer?
    fileprivate static let audioPlayerDelegate = AudioPlayerDelegate()
    
    fileprivate static var muted = false
    
    fileprivate static var alarmPlayingForTimer = Timer()
    fileprivate static let alarmPlayingForInterval = 290
    
    fileprivate func startAlarmPlayingForTimer(time: TimeInterval) {
        AlarmSound.alarmPlayingForTimer = Timer.scheduledTimer(timeInterval: time,
                                                               target: self,
                                                               selector: #selector(AlarmSound.alarmPlayingForTimerDidEnd(_:)),
                                                               userInfo: nil,
                                                               repeats: true)
    }
    
    @objc func alarmPlayingForTimerDidEnd(_ timer:Timer) {
        if !AlarmSound.isPlaying { return }
        AlarmSound.stop()
    }
    
    /*
     * Sets the audio volume to 0.
     */
    static func muteVolume() {
        self.audioPlayer?.volume = 0
        self.muted = true
        self.restoreSystemOutputVolume()
    }
    
    static func setSoundFile(str: String) {
        self.soundURL = Bundle.main.url(forResource: str, withExtension: "caf")!
    }
    
    /*
     * Sets the volume of the alarm back to the volume before it has been muted.
     */
    static func unmuteVolume() {
        if UserDefaultsRepository.fadeInTimeInterval.value > 0 {
            self.audioPlayer?.setVolume(1.0, fadeDuration: UserDefaultsRepository.fadeInTimeInterval.value)
        } else {
            self.audioPlayer?.volume = 1.0
        }
        self.muted = false
    }
    
    static func stop() {
        Observable.shared.alarmSoundPlaying.value = false
        
        self.audioPlayer?.stop()
        self.audioPlayer = nil
        
        self.restoreSystemOutputVolume()
    }
    
    static func playTest() {
        
        guard !self.isPlaying else {
            return
        }
        
        do {
            self.audioPlayer = try AVAudioPlayer(contentsOf: self.soundURL)
            self.audioPlayer!.delegate = self.audioPlayerDelegate
            /*
             try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category(rawValue: convertFromAVAudioSessionCategory(AVAudioSession.Category.playback)))*/
            //try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: []) // TEST
            //try AVAudioSession.sharedInstance().setActive(true)
            
            activateAudioSessionWithFallback()
            
            self.audioPlayer?.numberOfLoops = 0
            
            if !self.audioPlayer!.prepareToPlay() {
                LogManager.shared.log(category: .alarm, message: "AlarmSound - audio player failed preparing to play")
            }
            
            if self.audioPlayer!.play() {
                if !self.isPlaying {
                    LogManager.shared.log(category: .alarm, message: "AlarmSound - not playing after calling play")
                    LogManager.shared.log(category: .alarm, message: "AlarmSound - rate value: \(audioPlayer!.rate)")
                }
            } else {
                LogManager.shared.log(category: .alarm, message: "AlarmSound - audio player failed to play")
            }
            
            
        } catch let error {
            LogManager.shared.log(category: .alarm, message: "AlarmSound - unable to play sound; error: \(error)")
        }
    }
    
    
    static func play(overrideVolume: Bool, numLoops: Int) {
        guard !self.isPlaying else {
            return
        }
        
        //enableAudio()
        
        do {
            self.audioPlayer = try AVAudioPlayer(contentsOf: self.soundURL)
            self.audioPlayer!.delegate = self.audioPlayerDelegate
            //try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: []) // TEST
            /*try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category(rawValue: convertFromAVAudioSessionCategory(AVAudioSession.Category.playback)))*/
            //try AVAudioSession.sharedInstance().setActive(true)
            activateAudioSessionWithFallback()
            
            // Play endless loops
            self.audioPlayer!.numberOfLoops = numLoops
            
            // Store existing volume
            if self.systemOutputVolumeBeforeOverride == nil {
                self.systemOutputVolumeBeforeOverride = AVAudioSession.sharedInstance().outputVolume
            }
            
            if !self.audioPlayer!.prepareToPlay() {
                LogManager.shared.log(category: .alarm, message: "AlarmSound - audio player failed preparing to play")
            }
            
            if self.audioPlayer!.play() {
                if !self.isPlaying {
                    //LogManager.shared.log(category: .alarm, message: "AlarmSound - not playing after calling play")
                    //LogManager.shared.log(category: .alarm, message: "AlarmSound - rate value: \(audioPlayer!.rate)")
                    LogManager.shared.log(category: .alarm, message: "AlarmSound - not playing after calling play (rate \(audioPlayer!.rate))")
                } else {
                    Observable.shared.alarmSoundPlaying.value = true
                }
            } else {
                LogManager.shared.log(category: .alarm, message: "AlarmSound - audio player failed to play")
            }
            
            if overrideVolume {
                MPVolumeView.setVolume(UserDefaultsRepository.forcedOutputVolume.value)
            }
            
            
        } catch let error {
            LogManager.shared.log(category: .alarm, message: "AlarmSound - unable to play sound; error: \(error)")
        }
    }
    
    static func playTerminated() {
        
        guard !self.isPlaying else {
            return
        }
        
        do {
            self.audioPlayer = try AVAudioPlayer(contentsOf: self.soundURL)
            self.audioPlayer!.delegate = self.audioPlayerDelegate
            
            //try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category(rawValue: convertFromAVAudioSessionCategory(AVAudioSession.Category.playback)))
            //try AVAudioSession.sharedInstance().setActive(true)
            
            activateAudioSessionWithFallback()
            
            // Play endless loops
            self.audioPlayer!.numberOfLoops = 2
            
            // Store existing volume
            if self.systemOutputVolumeBeforeOverride == nil {
                self.systemOutputVolumeBeforeOverride = AVAudioSession.sharedInstance().outputVolume
            }
            
            
            if !self.audioPlayer!.prepareToPlay() {
                LogManager.shared.log(category: .alarm, message: "Terminate AlarmSound - audio player failed preparing to play")
            }
            
            if self.audioPlayer!.play() {
                if !self.isPlaying {
                    LogManager.shared.log(category: .alarm, message: "Terminate AlarmSound - not playing after calling play")
                    LogManager.shared.log(category: .alarm, message: "Terminate AlarmSound - rate value: \(audioPlayer!.rate)")
                }
            } else {
                LogManager.shared.log(category: .alarm, message: "Terminate AlarmSound - audio player failed to play")
            }
            
            
            MPVolumeView.setVolume(1.0)
            
            
        } catch let error {
            LogManager.shared.log(category: .alarm, message: "Terminate AlarmSound - unable to play sound; error: \(error)")
        }
    }
    
    
    fileprivate static func restoreSystemOutputVolume() {
        
        guard UserDefaultsRepository.overrideSystemOutputVolume.value else {
            return
        }
        
        // cancel any volume change observations
        // self.volumeChangeDetector.isActive = false
        
        // restore system output volume with its value before overriding it
        if let volumeBeforeOverride = self.systemOutputVolumeBeforeOverride {
            MPVolumeView.setVolume(volumeBeforeOverride)
        }
        
        self.systemOutputVolumeBeforeOverride = nil
    }
    /*
     fileprivate static func enableAudio() {
     do {
     //try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: []) // TEST
     try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
     try AVAudioSession.sharedInstance().setActive(true)
     LogManager.shared.log(category: .alarm, message: "Audio session configured for alarm playback")
     } catch {
     LogManager.shared.log(category: .general, message: "Enable audio error: \(error)")
     }
     }*/
    
    // Background activation of a non-mixable .playback session is denied by iOS
    // (cannotInterruptOthers, 560557684) unless the app is already actively playing
    // audio. In foreground, or with Silent Tune holding a mixable session alive,
    // options: [] succeeds and lets the alarm dominate other audio. For
    // Bluetooth-heartbeat users with no Silent Tune we skip [] (it would always
    // be denied) and ladder through mixable options so activation is still
    // permitted from background. Each attempt is logged so we can see in the
    // field which fallback (if any) the user landed on.
    fileprivate static func activateAudioSessionWithFallback() {
        let isBackgroundWithoutSilentTune = UIApplication.shared.applicationState == .background
        && Storage.shared.backgroundRefreshType.value != .silentTune
        
        let dominate: (label: String, options: AVAudioSession.CategoryOptions) = ("[]", [])
        //let duck: (label: String, options: AVAudioSession.CategoryOptions) = (".duckOthers", .duckOthers)
        let mix: (label: String, options: AVAudioSession.CategoryOptions) = (".mixWithOthers", .mixWithOthers)
        
        let candidates = isBackgroundWithoutSilentTune ? [mix] : [dominate, mix]
        //let candidates = isBackgroundWithoutSilentTune ? [duck, mix] : [dominate, duck, mix]
        for candidate in candidates {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: candidate.options)
                try AVAudioSession.sharedInstance().setActive(true)
                LogManager.shared.log(category: .alarm, message: "AlarmSound - audio session active (options: \(candidate.label))")
                return
            } catch {
                let nsError = error as NSError
                LogManager.shared.log(category: .alarm, message: "AlarmSound - audio session activation failed (options: \(candidate.label)) [code \(nsError.code)]: \(error.localizedDescription)")
            }
        }
        LogManager.shared.log(category: .alarm, message: "AlarmSound - all audio session option fallbacks exhausted")
    }
}

class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {

    /* audioPlayerDidFinishPlaying:successfully: is called when a sound has finished playing. This method is NOT called if the player is stopped due to an interruption. */
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        LogManager.shared.log(category: .general, message: "AlarmRule - audioPlayerDidFinishPlaying (\(flag))", isDebug: true)
        Observable.shared.alarmSoundPlaying.value = false
    }
    
    /* if an error occurs while decoding it will be reported to the delegate. */
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error = error {
            LogManager.shared.log(category: .general, message: "AlarmRule - audioPlayerDecodeErrorDidOccur: \(error)")
        } else {
            LogManager.shared.log(category: .general, message: "AlarmRule - audioPlayerDecodeErrorDidOccur")
        }
    }
    
    /* AVAudioPlayer INTERRUPTION NOTIFICATIONS ARE DEPRECATED - Use AVAudioSession instead. */
    
    /* audioPlayerBeginInterruption: is called when the audio session has been interrupted while the player was playing. The player will have been paused. */
    func audioPlayerBeginInterruption(_ player: AVAudioPlayer) {
        LogManager.shared.log(category: .general, message: "AlarmRule - audioPlayerBeginInterruption")
        Observable.shared.alarmSoundPlaying.value = false
    }
    
    
    /* audioPlayerEndInterruption:withOptions: is called when the audio session interruption has ended and this player had been interrupted while playing. */
    /* Currently the only flag is AVAudioSessionInterruptionFlags_ShouldResume. */
    func audioPlayerEndInterruption(_ player: AVAudioPlayer, withOptions flags: Int) {
        LogManager.shared.log(category: .general, message: "AlarmRule - audioPlayerEndInterruption withOptions: \(flags)")
        Observable.shared.alarmSoundPlaying.value = false
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVAudioSessionCategory(_ input: AVAudioSession.Category) -> String {
	return input.rawValue
}


extension MPVolumeView {
    static func setVolume(_ volume: Float) {
        // Need to use the MPVolumeView in order to change volume, but don't care about UI set so frame to .zero
        let volumeView = MPVolumeView(frame: .zero)
        // Search for the slider
        let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
        // Update the slider value with the desired volume.
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.01) {
            slider?.value = volume
        }
        // Optional - Remove the HUD
        if let app = UIApplication.shared.delegate as? AppDelegate, let window = app.window {
            volumeView.alpha = 0.000001
            window.addSubview(volumeView)
        }
    }
}
