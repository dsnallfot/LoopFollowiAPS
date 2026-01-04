//
//  LogManager.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-10.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import Foundation
import Combine

class LogManager {
    static let shared = LogManager()

    private let fileManager = FileManager.default
    private let logDirectory: URL
    private let dateFormatter: DateFormatter
    private let consoleQueue = DispatchQueue(label: "com.loopfollow.log.console", qos: .background)

    private let rateLimitQueue = DispatchQueue(label: "com.loopfollow.log.ratelimit")
    private var lastLoggedTimestamps: [String: Date] = [:]
    
    let logUpdateSubject = PassthroughSubject<Void, Never>() // Notify when logs are updated

    enum Category: String, CaseIterable {
        case alarm = "Alarm"
        case analysis = "Analysis"
        case apns = "APNS"
        case backgroundAlerts = "Background Alerts"
        case bluetooth = "Bluetooth"
        case calendar = "Calendar"
        case contact = "Contact"
        case dexcom = "Dexcom"
        case deviceStatus = "Device Status"
        case general = "General"
        case nightscout = "Nightscout"
        case remote = "Remote"
        case taskScheduler = "Task Scheduler"
        case temporaryDebug = "Temporary Debug"
        case treatments = "Treatments"
        case trio = "Trio"
        case volumeButtonSnooze = "Volume Button Snooze"
    }

    init() {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        logDirectory = documentsDirectory.appendingPathComponent("Logs")
        if !fileManager.fileExists(atPath: logDirectory.path) {
            try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
    }
    
    /// Logs a message with an optional rate limit.
    ///
    /// - Parameters:
    ///   - category: The log category.
    ///   - message: The message to log.
    ///   - isDebug: Indicates if this is a debug log.
    ///   - isTempDebug: Indicates if this is a temporary more detailed debug log.
    ///   - limitIdentifier: Optional key to rate-limit similar log messages.
    ///   - limitInterval: Time interval (in seconds) to wait before logging the same type again.
    func log(category: Category, message: String, isDebug: Bool = false, isTempDebug: Bool = false, limitIdentifier: String? = nil, limitInterval: TimeInterval = 300) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] [\(category.rawValue)] \(message)"
        
        let debugEnabled = Storage.shared.debugLogLevel.value
        let tempDebugEnabled = Storage.shared.tempDebugLogLevel.value

        // 3 log levels:
        // 1) Always logs (default): always shown
        // 2) Debug logs (isDebug=true): only shown when "Visa debugloggar" is enabled
        // 3) Temp debug logs (isTempDebug=true): only shown when "Visa temporära debugloggar" is enabled
        let shouldLogThisMessage: Bool = {
            switch (isDebug, isTempDebug) {
            case (true, true):
                return debugEnabled || tempDebugEnabled
            case (true, false):
                return debugEnabled
            case (false, true):
                return tempDebugEnabled
            case (false, false):
                return true
            }
        }()
        
        if shouldLogThisMessage {
            consoleQueue.async {
                print(logMessage)
            }
        }
        
        if let key = limitIdentifier, !(debugEnabled || tempDebugEnabled) {
            let shouldLog: Bool = rateLimitQueue.sync {
                if let lastLogged = lastLoggedTimestamps[key] {
                    let interval = Date().timeIntervalSince(lastLogged)
                    if interval < limitInterval {
                        return false
                    }
                }
                lastLoggedTimestamps[key] = Date()
                return true
            }
            if !shouldLog {
                return
            }
        }
        
        if shouldLogThisMessage {
            let logFileURL = self.currentLogFileURL
            self.append(logMessage + "\n", to: logFileURL)
            logUpdateSubject.send() // Notify subscribers of the log update
        }
    }
    
    func cleanupOldLogs() {
        let today = dateFormatter.string(from: Date())
        let yesterday = dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)

        do {
            let logFiles = try fileManager.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil)
            for logFile in logFiles {
                let filename = logFile.lastPathComponent
                if !filename.contains(today) && !filename.contains(yesterday) {
                    try fileManager.removeItem(at: logFile)
                }
            }
        } catch {
            print("Failed to clean up old logs: \(error)")
        }
    }

    func logFileURL(for date: Date) -> URL {
             let dateString = dateFormatter.string(from: date)
             return logDirectory.appendingPathComponent("LoopFollow \(dateString).log")
         }

         func logFilesForTodayAndYesterday() -> [URL] {
             let today = logFileURL(for: Date())
             let yesterday = logFileURL(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
             return [today, yesterday].filter { fileManager.fileExists(atPath: $0.path) }
    }
    
    var currentLogFileURL: URL {
             return logFileURL(for: Date())
         }

    private func append(_ message: String, to fileURL: URL) {
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        }

        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
            defer { fileHandle.closeFile() }
            fileHandle.seekToEndOfFile()
            if let data = message.data(using: .utf8) {
                fileHandle.write(data)
            }
        } else {
            print("Failed to open log file at \(fileURL.path)")
        }
    }
}
