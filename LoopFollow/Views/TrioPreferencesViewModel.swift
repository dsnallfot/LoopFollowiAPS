//
//  TrioPreferencesViewModel.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-02-23.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//
import Foundation

struct PreferenceEntry: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

class TrioPreferencesViewModel: ObservableObject {
    @Published var preferences: [PreferenceEntry] = []
    
    init() {
        fetchPreferences()
    }
    
    func fetchPreferences() {
        // Using your NightscoutUtils to fetch the NSProfile
        NightscoutUtils.executeRequest(eventType: .profile, parameters: [:]) { (result: Result<NSProfile, Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let profileData):
                    if let prefs = profileData.nsPreferences?.preferences {
                        self.preferences = prefs.map { key, value in
                            PreferenceEntry(key: key, value: value)
                        }
                        .sorted { $0.key < $1.key }
                    } else {
                        self.preferences = []
                    }
                case .failure(let error):
                    LogManager.shared.log(category: .trio, message: "Error fetching profile: \(error)", isDebug: true)

                    self.preferences = []
                }
            }
        }
    }
}
