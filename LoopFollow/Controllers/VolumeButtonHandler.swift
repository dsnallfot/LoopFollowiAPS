// LoopFollow
// VolumeButtonHandler.swift

import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

extension Notification.Name {
    static let volumeButtonAlarmStopped = Notification.Name("volumeButtonAlarmStopped")
}

class VolumeButtonHandler: NSObject {
    static let shared = VolumeButtonHandler()

    // Volume button snoozer activation delay in seconds
    private let volumeButtonActivationDelay: TimeInterval = 0.5//0.9

    // Volume button detection parameters
    private let volumeButtonPressThreshold: Float = 0.02
    private let volumeButtonPressTimeWindow: TimeInterval = 0.3
    private let volumeButtonCooldown: TimeInterval = 0.5

    // KVO observer for system volume
    private var volumeObserver: NSKeyValueObservation?

    private var lastVolume: Float = 0.0
    private var isMonitoring = false
    private var alarmStartTime: Date?
    private var lastVolumeButtonPressTime: Date?

    // Button press detection
    private var recentVolumeChanges: [(volume: Float, timestamp: Date)] = []
    private var lastSignificantVolumeChange: Date?
    private var volumeChangePattern: [TimeInterval] = []
    
    // Remote command center for handling bluetooth/CarPlay buttons
    private var remoteCommandsEnabled = false

    // Tracks whether the upcoming stop was triggered by our own volume-button snooze
    private var didSnoozeViaVolumeButton = false

    private var cancellables = Set<AnyCancellable>()

    override private init() {
        super.init()

        Observable.shared.alarmSoundPlaying.$value
            .removeDuplicates()
            .sink { [weak self] alarmSoundPlaying in
                guard let self = self else { return }
                if alarmSoundPlaying {
                    self.alarmStarted()
                } else {
                    let wasVolumeSnooze = self.didSnoozeViaVolumeButton
                    self.didSnoozeViaVolumeButton = false
                    if wasVolumeSnooze {
                        self.alarmStopped() // volume-button initiated
                    } else {
                        self.alarmEndedNaturally() // playback ended or stopped elsewhere
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func recordVolumeChange(currentVolume: Float, timestamp: Date) {
        recentVolumeChanges.append((volume: currentVolume, timestamp: timestamp))

        let cutoffTime = timestamp.timeIntervalSinceReferenceDate - volumeButtonPressTimeWindow
        recentVolumeChanges = recentVolumeChanges.filter { $0.timestamp.timeIntervalSinceReferenceDate > cutoffTime }

        if let lastChange = lastSignificantVolumeChange {
            let timeSinceLastChange = timestamp.timeIntervalSince(lastChange)
            volumeChangePattern.append(timeSinceLastChange)

            if volumeChangePattern.count > 5 {
                volumeChangePattern.removeFirst()
            }
        }
        lastSignificantVolumeChange = timestamp
    }

    private func isLikelyVolumeButtonPress(volumeDifference: Float, timestamp: Date) -> Bool {
        let isReasonableChange = volumeDifference >= 0.02 && volumeDifference <= 0.20
        let isDiscreteChange = recentVolumeChanges.count <= 2
        let hasConsistentTiming: Bool = {
            if let last = volumeChangePattern.last {
                return last >= 0.15
            } else {
                return true
            }
        }()
        let isNotRapidSequence: Bool = {
            if recentVolumeChanges.count < 3 { return true }
            let lastThree = recentVolumeChanges.suffix(3).map { $0.timestamp.timeIntervalSinceReferenceDate }
            return lastThree.enumerated().dropFirst().allSatisfy { index, ts in
                let prev = lastThree[index - 1]
                return ts - prev > 0.08
            }
        }()

        let decision = isReasonableChange && isDiscreteChange && hasConsistentTiming && isNotRapidSequence

        if !decision {
            let lastIntervalStr = volumeChangePattern.last.map { String(format: "%.3f", $0) } ?? "nil"
            LogManager.shared.log(
                category: .volumeButtonSnooze,
                message:
                    "Reject press: Δ=\(String(format: "%.4f", volumeDifference)); " +
                    "isReasonableChange=\(isReasonableChange) [0.03…0.12]; " +
                    "isDiscreteChange=\(isDiscreteChange) [recent=\(recentVolumeChanges.count)]; " +
                    "hasConsistentTiming=\(hasConsistentTiming) [lastInterval=\(lastIntervalStr) ≥ 0.15]; " +
                    "isNotRapidSequence=\(isNotRapidSequence) [minGap>0.08s]"
            )
        }

        return decision
    }

    private func snoozeActiveAlarm() {
        LogManager.shared.log(category: .volumeButtonSnooze, message: "Snoozing alarm")

        lastVolumeButtonPressTime = Date()
        didSnoozeViaVolumeButton = true
        AlarmSound.stop()
        //AlarmManager.shared.performSnooze()

        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }

    private func alarmStarted() {
        //guard Storage.shared.alarmConfiguration.value.enableVolumeButtonSnooze else { return }
        guard UserDefaultsRepository.enableVolumeButtonSnooze.value else { return }
            LogManager.shared.log(category: .volumeButtonSnooze, message: "Alarm start detected, setting up volume observer.")
            
            alarmStartTime = Date()
            recentVolumeChanges.removeAll()
            lastSignificantVolumeChange = nil
            volumeChangePattern.removeAll()
            
            startMonitoring()

    }

    private func alarmStopped() {
        LogManager.shared.log(category: .volumeButtonSnooze, message: "Alarm stop detected")
        //Create notification for SnoozeViewController to run the same snooze actions incl UI changes when snoozed with volume button as when the snooze button in the SnoozeVC is pressed
        NotificationCenter.default.post(name: .volumeButtonAlarmStopped, object: nil)

        alarmStartTime = nil
        stopMonitoring()

        recentVolumeChanges.removeAll()
        lastSignificantVolumeChange = nil
        volumeChangePattern.removeAll()
        
        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func alarmEndedNaturally() {
        LogManager.shared.log(category: .volumeButtonSnooze, message: "Alarm ended naturally")
        alarmStartTime = nil
        stopMonitoring()
        recentVolumeChanges.removeAll()
        lastSignificantVolumeChange = nil
        volumeChangePattern.removeAll()
    }
    
    private func setupRemoteCommandCenter() {
            guard !remoteCommandsEnabled else { return }

            let commandCenter = MPRemoteCommandCenter.shared()

            // Log current audio route to help with debugging
            let currentRoute = AVAudioSession.sharedInstance().currentRoute
            LogManager.shared.log(category: .volumeButtonSnooze, message: "Audio route: \(currentRoute.outputs.map { $0.portName }.joined(separator: ", "))")

            // Enable pause command - handles play/pause button on bluetooth devices and CarPlay
            commandCenter.pauseCommand.isEnabled = true
            commandCenter.pauseCommand.addTarget { [weak self] _ in
                guard let self = self else { return .commandFailed }

                LogManager.shared.log(category: .volumeButtonSnooze, message: "Pause command received from remote")

                // Check if alarm is currently active and activation delay has passed
                if let alarmStartTime = self.alarmStartTime {
                    let timeSinceAlarmStart = Date().timeIntervalSince(alarmStartTime)

                    if timeSinceAlarmStart > self.volumeButtonActivationDelay {
                        // Check cooldown
                        if let lastPress = self.lastVolumeButtonPressTime {
                            let timeSinceLastPress = Date().timeIntervalSince(lastPress)
                            if timeSinceLastPress < self.volumeButtonCooldown {
                                return .success
                            }
                        }

                        LogManager.shared.log(category: .volumeButtonSnooze, message: "Remote command pause received - snoozing alarm")
                        self.snoozeActiveAlarm()
                        return .success
                    }
                }

                return .commandFailed
            }

            // Enable play command as well for symmetry
            commandCenter.playCommand.isEnabled = true
            commandCenter.playCommand.addTarget { [weak self] _ in
                guard let self = self else { return .commandFailed }

                LogManager.shared.log(category: .volumeButtonSnooze, message: "Play command received from remote")

                if let alarmStartTime = self.alarmStartTime {
                    let timeSinceAlarmStart = Date().timeIntervalSince(alarmStartTime)

                    if timeSinceAlarmStart > self.volumeButtonActivationDelay {
                        if let lastPress = self.lastVolumeButtonPressTime {
                            let timeSinceLastPress = Date().timeIntervalSince(lastPress)
                            if timeSinceLastPress < self.volumeButtonCooldown {
                                return .success
                            }
                        }

                        LogManager.shared.log(category: .volumeButtonSnooze, message: "Remote command play received - snoozing alarm")
                        self.snoozeActiveAlarm()
                        return .success
                    }
                }

                return .commandFailed
            }

            // Enable toggle play/pause command - common on many bluetooth devices
            commandCenter.togglePlayPauseCommand.isEnabled = true
            commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
                guard let self = self else { return .commandFailed }

                LogManager.shared.log(category: .volumeButtonSnooze, message: "Toggle play/pause command received from remote")

                if let alarmStartTime = self.alarmStartTime {
                    let timeSinceAlarmStart = Date().timeIntervalSince(alarmStartTime)

                    if timeSinceAlarmStart > self.volumeButtonActivationDelay {
                        if let lastPress = self.lastVolumeButtonPressTime {
                            let timeSinceLastPress = Date().timeIntervalSince(lastPress)
                            if timeSinceLastPress < self.volumeButtonCooldown {
                                return .success
                            }
                        }

                        LogManager.shared.log(category: .volumeButtonSnooze, message: "Remote command toggle play/pause received - snoozing alarm")
                        self.snoozeActiveAlarm()
                        return .success
                    }
                }

                return .commandFailed
            }

            remoteCommandsEnabled = true
            LogManager.shared.log(category: .volumeButtonSnooze, message: "Remote command center configured for bluetooth/CarPlay button handling")
        }

        private func disableRemoteCommandCenter() {
            guard remoteCommandsEnabled else { return }

            let commandCenter = MPRemoteCommandCenter.shared()
            commandCenter.pauseCommand.isEnabled = false
            commandCenter.playCommand.isEnabled = false
            commandCenter.togglePlayPauseCommand.isEnabled = false

            // Remove all targets
            commandCenter.pauseCommand.removeTarget(nil)
            commandCenter.playCommand.removeTarget(nil)
            commandCenter.togglePlayPauseCommand.removeTarget(nil)

            remoteCommandsEnabled = false
            LogManager.shared.log(category: .volumeButtonSnooze, message: "Remote command center disabled")
        }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // Setup remote command center for bluetooth/CarPlay button handling
        setupRemoteCommandCenter()

        let session = AVAudioSession.sharedInstance()

        // 1) Seed:a baseline omedelbart
        var seededVolume = session.outputVolume
        self.lastVolume = max(seededVolume, 0.0001)
        LogManager.shared.log(category: .volumeButtonSnooze, message: "startMonitoring(): seeded baseline lastVolume=\(self.lastVolume)")

        // 2) Läs ev. tvingad volym (override)
        let overrideEnabled = UserDefaultsRepository.overrideSystemOutputVolume.value
        let expectedForcedVolume = overrideEnabled ? UserDefaultsRepository.forcedOutputVolume.value : nil
        if let expected = expectedForcedVolume {
            // Aligna baseline till den volym vi vet kommer att sättas av vår override
            self.lastVolume = max(expected, 0.0001)
            LogManager.shared.log(category: .volumeButtonSnooze, message: "startMonitoring(): baseline aligned to expected forced volume \(expected)")
        }

        // 3) Kort arming-delay + separat fönster för att ignorera "forced volume"-bekräftelsen
        let observerStartTime = Date()
        let armingDelay: TimeInterval = 0.10   // skydd mot spurious direkt vid attach
        let forcedVolumeWindow: TimeInterval = 1.20 // tidigt efter start brukar override:en slå till

        volumeObserver = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            guard let self = self, let alarmStartTime = self.alarmStartTime else { return }

            let currentVolume = session.outputVolume
            let now = Date()

            // Ignorera enbart event som kommer precis när observern startas (spurious sync från iOS)
            if now.timeIntervalSince(observerStartTime) < armingDelay {
                self.lastVolume = currentVolume
                return
            }

            // Om vi kör override: ignorera första bekräftelsen på den tvingade nivån inom ett kort fönster
            if let expected = expectedForcedVolume,
               now.timeIntervalSince(observerStartTime) < forcedVolumeWindow,
               abs(currentVolume - expected) <= 0.02 {
                LogManager.shared.log(
                    category: .volumeButtonSnooze,
                    message: "Ignore: forced system volume applied (current=\(String(format: "%.3f", currentVolume)), expected=\(String(format: "%.3f", expected)))"
                )
                self.lastVolume = currentVolume
                return
            }

            // Vanlig knappdetektering
            let volumeDifference = abs(currentVolume - self.lastVolume)
            if volumeDifference <= self.volumeButtonPressThreshold {
                LogManager.shared.log(
                    category: .volumeButtonSnooze,
                    message: "Ignore: Δ=\(String(format: "%.4f", volumeDifference)) ≤ threshold \(self.volumeButtonPressThreshold)"
                )
            }

            if volumeDifference > self.volumeButtonPressThreshold {
                let timeSinceAlarmStart = now.timeIntervalSince(alarmStartTime)

                // Ignorera larmets egen volym-ramp i början
                if timeSinceAlarmStart < 2.0, currentVolume > self.lastVolume {
                    if volumeDifference <= 0.15, timeSinceAlarmStart < 1.5 {
                        LogManager.shared.log(
                            category: .volumeButtonSnooze,
                            message: "Ignore: ramp-up guard (sinceStart=\(String(format: "%.3f", timeSinceAlarmStart))s, Δ=\(String(format: "%.4f", volumeDifference)) ≤ 0.15, rising)"
                        )
                        self.lastVolume = currentVolume
                        return
                    }
                }

                // Viktigt för heuristiken & felsökning
                self.recordVolumeChange(currentVolume: currentVolume, timestamp: now)

                // Respektera aktiveringsfördröjning
                if timeSinceAlarmStart > self.volumeButtonActivationDelay {
                    // Cooldown mellan godkända tryck
                    if let lastPress = self.lastVolumeButtonPressTime {
                        let timeSinceLastPress = now.timeIntervalSince(lastPress)
                        if timeSinceLastPress < self.volumeButtonCooldown {
                            LogManager.shared.log(
                                category: .volumeButtonSnooze,
                                message: "Ignore: cooldown (Δt=\(String(format: "%.3f", timeSinceLastPress))s < \(self.volumeButtonCooldown)s)"
                            )
                            self.lastVolume = currentVolume
                            return
                        }
                    }

                    // Heuristik: ser detta ut som en riktig volymknapp?
                    if self.isLikelyVolumeButtonPress(volumeDifference: volumeDifference, timestamp: now) {
                        self.snoozeActiveAlarm()
                        LogManager.shared.log(
                            category: .volumeButtonSnooze,
                            message: "Snoozing active alarm due to likely volume button press (Δ=\(String(format: "%.4f", volumeDifference)))"
                        )
                    } else {
                        LogManager.shared.log(
                            category: .volumeButtonSnooze,
                            message: "Heuristics rejected press candidate (Δ=\(String(format: "%.4f", volumeDifference)); recent=\(self.recentVolumeChanges.count))"
                        )
                    }
                } else {
                    LogManager.shared.log(
                        category: .volumeButtonSnooze,
                        message: "Ignore: activationDelay not met (sinceStart=\(String(format: "%.3f", timeSinceAlarmStart))s < \(self.volumeButtonActivationDelay)s)"
                    )
                }
            }

            // Uppdatera baseline för nästa event
            self.lastVolume = currentVolume
        }
    }
/* ORIGINAL KOD NEDAN IFALL DEN NYA INTE FUNKAR SOM TÄNKT
    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true

        volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            guard let self = self, let alarmStartTime = self.alarmStartTime else { return }

            let currentVolume = session.outputVolume
            let now = Date()

            // On the first observation, capture the initial volume when the audio session
            // becomes active. This solves the race condition. We then return to avoid
            // treating this initial setup as a user-initiated button press.
            if self.lastVolume == 0.0, currentVolume > 0.0 {
                LogManager.shared.log(category: .volumeButtonSnooze, message: "Observer received initial valid volume: \(currentVolume)")
                self.lastVolume = currentVolume
                return
            }

            guard self.lastVolume > 0.0 else { return }

            let volumeDifference = abs(currentVolume - self.lastVolume)

            if volumeDifference > self.volumeButtonPressThreshold {
                let timeSinceAlarmStart = now.timeIntervalSince(alarmStartTime)

                // Ignore volume changes from the alarm system's own ramp-up.
                if timeSinceAlarmStart < 2.0, currentVolume > self.lastVolume {
                    if volumeDifference <= 0.15, timeSinceAlarmStart < 1.5 {
                        self.lastVolume = currentVolume
                        return
                    }
                }

                self.recordVolumeChange(currentVolume: currentVolume, timestamp: now)

                if timeSinceAlarmStart > self.volumeButtonActivationDelay {
                    if let lastPress = self.lastVolumeButtonPressTime {
                        let timeSinceLastPress = now.timeIntervalSince(lastPress)
                        if timeSinceLastPress < self.volumeButtonCooldown {
                            self.lastVolume = currentVolume
                            return
                        }
                    }

                    if self.isLikelyVolumeButtonPress(volumeDifference: volumeDifference, timestamp: now) {
                        self.snoozeActiveAlarm()
                        LogManager.shared.log(category: .volumeButtonSnooze, message: "Snoozing active alarm due to likely volume button press")
                    }
                }
            }
            self.lastVolume = currentVolume
        }
    }
*/
    func stopMonitoring() {
        guard isMonitoring else { return }

        LogManager.shared.log(category: .volumeButtonSnooze, message: "Invalidating volume observer.")

        // Invalidate the observer to stop receiving notifications and prevent memory leaks.
        volumeObserver?.invalidate()
        volumeObserver = nil
        
        // Disable remote command center
        disableRemoteCommandCenter()

        isMonitoring = false
        lastVolume = 0.0 // Reset for the next alarm.
    }
}
