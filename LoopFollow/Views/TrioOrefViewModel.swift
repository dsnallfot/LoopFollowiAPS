//
//  TrioOrefViewModel.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-04-08.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//
import Foundation

struct Oref2Entry: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

class TrioOrefViewModel: ObservableObject {
    @Published var orefEntries: [Oref2Entry] = []
    @Published var formattedTitle: String = "Oref status"
    
    init() {
        fetchLatestOref2()
    }

    func fetchLatestOref2() {
        let parameters = ["count": "1"]
        NightscoutUtils.executeRequest(eventType: .deviceStatus, parameters: parameters) { (result: Result<[Oref2DeviceStatus], Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let statusList):
                    guard let firstStatus = statusList.first else {
                        LogManager.shared.log(category: .trio, message: "✅ Successfully fetched device status, but status list is empty.", isDebug: true)
                        self.orefEntries = []
                        self.formattedTitle = "Oref status"
                        return
                    }

                    guard let oref2 = firstStatus.oref2 else {
                        LogManager.shared.log(category: .trio, message: "✅ Fetched device status, but oref2 field is missing.", isDebug: true)
                        self.orefEntries = []
                        self.formattedTitle = "Oref status"
                        return
                    }

                    self.orefEntries = Mirror(reflecting: oref2).children.compactMap { child in
                        guard let key = child.label else { return nil }
                        return Oref2Entry(key: key, value: "\(child.value)")
                    }
                    .sorted { $0.key < $1.key }

                    // 🔹 Format the `date` string to local time
                    let isoFormatter = ISO8601DateFormatter()
                    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                    if let parsedDate = isoFormatter.date(from: oref2.date) {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "HH:mm:ss"
                        formatter.timeZone = .current
                        let localTime = formatter.string(from: parsedDate)
                        self.formattedTitle = "Trio oref status: \(localTime)"
                        LogManager.shared.log(category: .trio, message: "✅ Parsed and displayed local date: \(localTime)", isDebug: true)
                    } else {
                        LogManager.shared.log(category: .trio, message: "⚠️ Could not parse oref2.date: \(oref2.date)", isDebug: true)
                        self.formattedTitle = "Oref status"
                    }

                case .failure(let error):
                    LogManager.shared.log(category: .trio, message: "❌ Failed to fetch oref2: \(error)", isDebug: true)
                    self.orefEntries = []
                    self.formattedTitle = "Oref status"
                }
            }
        }
    }
}

struct Oref2DeviceStatus: Codable {
    let oref2: Oref2_variables?
}

struct Oref2_variables: Codable {
    let average_total_data: Decimal
    let weightedAverage: Decimal
    let past2hoursAverage: Decimal
    let date: String
    let overridePercentage: Decimal
    let useOverride: Bool
    let duration: Decimal
    let unlimited: Bool
    let overrideTarget: Decimal
    let smbIsOff: Bool
    let advancedSettings: Bool
    let isfAndCr: Bool
    let isf: Bool
    let cr: Bool
    let smbIsScheduledOff: Bool
    let start: Decimal
    let end: Decimal
    let smbMinutes: Decimal
    let uamMinutes: Decimal
}
