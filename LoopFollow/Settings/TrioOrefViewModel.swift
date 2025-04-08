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
    @Published var formattedTitle: String = "Trio Oref-variabler"
    
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
                        print("✅ Successfully fetched device status, but status list is empty.")
                        self.orefEntries = []
                        self.formattedTitle = "Trio Oref-variabler"
                        return
                    }

                    guard let oref2 = firstStatus.oref2 else {
                        print("✅ Fetched device status, but oref2 field is missing.")
                        self.orefEntries = []
                        self.formattedTitle = "Trio Oref-variabler"
                        return
                    }

                    self.orefEntries = Mirror(reflecting: oref2).children.compactMap { child in
                        guard let key = child.label else { return nil }
                        return Oref2Entry(key: key, value: "\(child.value)")
                    }
                    .sorted { $0.key < $1.key }

                    // 🔹 Format the `date` field for use in title
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm"
                    formatter.timeZone = .current
                    self.formattedTitle = "Oref \(formatter.string(from: oref2.date))"

                case .failure(let error):
                    print("❌ Failed to fetch oref2:", error)
                    self.orefEntries = []
                    self.formattedTitle = "Trio Oref-variabler"
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
    let date: Date
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
