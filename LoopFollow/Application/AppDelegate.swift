//
//  AppDelegate.swift
//  LoopFollow
//
//  Created by Jon Fawcett on 6/1/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//

import UIKit
import CoreData
import UserNotifications
import EventKit
import WatchConnectivity

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    let notificationCenter = UNUserNotificationCenter.current()
    var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        LogManager.shared.log(category: .general, message: "App started")
        LogManager.shared.cleanupOldLogs()

        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        notificationCenter.requestAuthorization(options: options) {
            (didAllow, error) in
            if !didAllow {
                LogManager.shared.log(category: .general, message: "User has declined notifications")
            }
        }

        let store = EKEventStore()
        store.requestCalendarAccess { (granted, error) in
            if !granted {
                LogManager.shared.log(category: .calendar, message: "Failed to get calendar access: \(String(describing: error))")
                return
            }
        }

        let action = UNNotificationAction(identifier: "OPEN_APP_ACTION", title: "Open App", options: .foreground)
        let category = UNNotificationCategory(identifier: "loopfollow.background.alert", actions: [action], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])

        UNUserNotificationCenter.current().delegate = self

        // Ensure ViewControllerManager is initialized
        _ = ViewControllerManager.shared

        _ = BLEManager.shared
        
        if Storage.shared.backgroundRefreshType.value != .none {
            LogManager.shared.log(category: .backgroundAlerts,
                                  message: "AppDelegate: starting BackgroundAlertManager on launch")
            BackgroundAlertManager.shared.startBackgroundAlert()
        }
        
        // Ensure VolumeButtonHandler is initialized so it can receive alarm notifications
        _ = VolumeButtonHandler.shared
        
        PhoneSessionManager.shared.startSession()

        // Post a Nightscout Note about app restart, debounced
        postLaunchNoteToNightscoutIfNeeded()

        return true
    }
/* Revertat ändring i 2f66847 & 94ad3e9 pga sämre UX
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Get root tab bar controller
        if let tabBar = window?.rootViewController as? UITabBarController,
           let mainVC = tabBar.viewControllers?.first as? MainViewController {

            // Immediate refresh of MinAgo
            mainVC.minAgoTaskAction()

            // Restore high-frequency updates
            TaskScheduler.shared.rescheduleTask(
                id: .minAgoUpdate,
                to: Date().addingTimeInterval(1)
            )
        }
    }
 */

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return orientationLock
    }

    func applicationWillTerminate(_ application: UIApplication) {
        if UserDefaultsRepository.alertAppInactive.value {
            AlarmSound.setSoundFile(str: "Alarm_Buzzer")
            AlarmSound.playTerminated()
        }
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // set "prevent screen lock" to ON when the app is started for the first time
        if !UserDefaultsRepository.screenlockSwitchState.exists {
            UserDefaultsRepository.screenlockSwitchState.value = true
        }

        // set the "prevent screen lock" option when the app is started
        // This method doesn't seem to be working anymore. Added to view controllers as solution offered on SO
        UIApplication.shared.isIdleTimerDisabled = UserDefaultsRepository.screenlockSwitchState.value

        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    // MARK: - Core Data stack

    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        /*
         The persistent container for the application. This implementation
         creates and returns a container, having loaded the store for the
         application to it. This property is optional since there are legitimate
         error conditions that could cause the creation of the store to fail.
         */
        let container = NSPersistentCloudKitContainer(name: "LoopFollow")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()

    // MARK: - Core Data Saving support

    func saveContext () {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "OPEN_APP_ACTION" {
            if let window = window {
                window.rootViewController?.dismiss(animated: true, completion: nil)
                window.rootViewController?.present(MainViewController(), animated: true, completion: nil)
            }
        }
        completionHandler()
    }
    // MARK: - Nightscout launch note

    private static let lastLaunchNotePostedKey = "LastLaunchNotePostedAt"

    /// Posts a Nightscout treatment "Note" when LoopFollow starts.
    /// Debounced to avoid spamming if the app is crash-looping or relaunched repeatedly.
    private func postLaunchNoteToNightscoutIfNeeded() {
        // Only upload if user has enabled "Upload app start note" in settings
        guard Storage.shared.uploadAppStartNote.value else { return }
        // Must have Nightscout configured and treatments download enabled
        // Use IsNightscoutEnabled() if available, else check directly for URL and downloadTreatments
        #if compiler(>=5.0)
        // Try to use IsNightscoutEnabled if visible, else fallback
        if ({ () -> Bool in
            // Try to call IsNightscoutEnabled() if in scope
            #if canImport(MainViewController)
            return IsNightscoutEnabled()
            #else
            return !ObservableUserDefaults.shared.url.value.isEmpty
            #endif
        })() == false || !UserDefaultsRepository.downloadTreatments.value {
            return
        }
        #else
        guard !ObservableUserDefaults.shared.url.value.isEmpty, UserDefaultsRepository.downloadTreatments.value else { return }
        #endif

        // Debounce: Send only once per 10 minutes
        let now = Date()
        if let last = UserDefaults.standard.object(forKey: Self.lastLaunchNotePostedKey) as? Date {
            if now.timeIntervalSince(last) < 10 * 60 { return }
        }

        // Build payload
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let createdAt = iso.string(from: now) // includes Z

        // enteredBy: use caregiverName if available, else fall back
        let caregiver = UserDefaultsRepository.caregiverName.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredBy = caregiver.isEmpty ? "LoopFollow" : "\(caregiver)"
        let notesString = "Loop Follow omstart (\(enteredBy) )"

        // Nightscout expects utcOffset in minutes
        let utcOffsetMinutes = TimeZone.current.secondsFromGMT(for: now) / 60

        let doc: [String: Any] = [
            "notes": notesString,
            "enteredBy": enteredBy,
            "eventType": "Note",
            "created_at": createdAt,
            "utcOffset": utcOffsetMinutes
        ]

        // Wait a moment so user defaults / storage initialization has settled
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            Task {
                do {
                    _ = try await NightscoutUtils.executePostRequestRaw(eventType: .treatments, body: doc)
                    UserDefaults.standard.set(now, forKey: Self.lastLaunchNotePostedKey)
                    LogManager.shared.log(category: .nightscout, message: "✅ Posted launch Note to Nightscout (enteredBy=\(enteredBy))", isDebug: true)
                } catch {
                    // Queue for retry on next TreatmentsTableView appearance (existing retry logic)
                    NightscoutUtils.addPendingUploadDocument(doc)
                    LogManager.shared.log(category: .nightscout, message: "⚠️ Failed to post launch Note, queued for retry: \(error)")
                }
            }
        }
    }

    struct AppUtility {
        static func lockOrientation(_ orientation: UIInterfaceOrientationMask) {
            if let delegate = UIApplication.shared.delegate as? AppDelegate {
                delegate.orientationLock = orientation
            }
        }

        static func lockOrientation(_ orientation: UIInterfaceOrientationMask, andRotateTo rotateOrientation: UIInterfaceOrientation) {
            self.lockOrientation(orientation)
            UIDevice.current.setValue(rotateOrientation.rawValue, forKey: "orientation")
            UINavigationController.attemptRotationToDeviceOrientation()
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        completionHandler(.alert)
    }
}
