//
//  DexcomSettingsViewModel.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-18.

//

import Foundation
import Combine

class DexcomSettingsViewModel: ObservableObject {
    @Published var userName: String = UserDefaultsRepository.shareUserName.value {
        willSet {
            if newValue != userName {
                UserDefaultsRepository.shareUserName.value = newValue
                if ObservableUserDefaults.shared.watchCommunicationEnabled.value {
                    PhoneSessionManager.shared.sendConfig()
                }
            }
        }
    }
    @Published var password: String = UserDefaultsRepository.sharePassword.value {
        willSet {
            if newValue != password {
                UserDefaultsRepository.sharePassword.value = newValue
                if ObservableUserDefaults.shared.watchCommunicationEnabled.value {
                    PhoneSessionManager.shared.sendConfig()
                }
            }
        }
    }
    @Published var server: String = UserDefaultsRepository.shareServer.value {
        willSet {
            if newValue != server {
                UserDefaultsRepository.shareServer.value = newValue
                if ObservableUserDefaults.shared.watchCommunicationEnabled.value {
                    PhoneSessionManager.shared.sendConfig()
                }
            }
        }
    }
    @Published var adhocOnly: Bool = UserDefaultsRepository.dexAdhocOnly.value {
        willSet {
            if newValue != adhocOnly {
                UserDefaultsRepository.dexAdhocOnly.value = newValue
            }
        }
    }

    init() {
    }
}
