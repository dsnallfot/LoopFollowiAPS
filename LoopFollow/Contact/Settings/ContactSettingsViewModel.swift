//
//  ContactSettingsViewModel.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-12-10.

//

import Foundation
import Combine

extension Bundle {
    var displayName: String {
        return object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "LoopFollow"
    }
}

class ContactSettingsViewModel: ObservableObject {
    var contactName: String {
        "\(Bundle.main.displayName) - BG"
    }

    @Published var contactEnabled: Bool {
        didSet {
            storage.contactEnabled.value = contactEnabled
            triggerRefresh()
        }
    }

    @Published var contactTrend: Bool {
        didSet {
            if contactTrend {
                contactDelta = false
            }
            storage.contactTrend.value = contactTrend
            triggerRefresh()
        }
    }

    @Published var contactDelta: Bool {
        didSet {
            if contactDelta {
                contactTrend = false
            }
            storage.contactDelta.value = contactDelta
            triggerRefresh()
        }
    }
    
    @Published var contactFifteenMinutes: Bool {
             didSet {
                 storage.contactFifteenMinutes.value = contactFifteenMinutes
                 triggerRefresh()
             }
         }
    
    @Published var watchCommunicationEnabled: Bool {
        didSet {
            storage.watchCommunicationEnabled.value = watchCommunicationEnabled
            triggerRefresh()

            if watchCommunicationEnabled {
                PhoneSessionManager.shared.startSession()
                PhoneSessionManager.shared.sendConfig()
            }
        }
    }

    private let storage = ObservableUserDefaults.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.contactEnabled = storage.contactEnabled.value
        self.contactTrend = storage.contactTrend.value
        self.contactDelta = storage.contactDelta.value
        self.contactFifteenMinutes = storage.contactFifteenMinutes.value
        self.watchCommunicationEnabled = storage.watchCommunicationEnabled.value

        storage.contactEnabled.$value
            .assign(to: &$contactEnabled)

        storage.contactTrend.$value
            .assign(to: &$contactTrend)

        storage.contactDelta.$value
            .assign(to: &$contactDelta)
        
        storage.contactFifteenMinutes.$value
            .assign(to: &$contactFifteenMinutes)
        
        storage.watchCommunicationEnabled.$value
            .assign(to: &$watchCommunicationEnabled)
    }

    private func triggerRefresh() {
        NotificationCenter.default.post(name: NSNotification.Name("refresh"), object: nil)
    }
}
