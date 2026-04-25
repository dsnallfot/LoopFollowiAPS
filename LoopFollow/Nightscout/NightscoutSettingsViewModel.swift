//
//  NightscoutSettingsViewModel.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-18.

//

import Foundation
import Combine
import SwiftUI

protocol NightscoutSettingsViewModelDelegate: AnyObject {
    func nightscoutSettingsDidFinish()
}

class NightscoutSettingsViewModel: ObservableObject {
    weak var delegate: NightscoutSettingsViewModelDelegate?

    private var initialURL: String
    private var initialToken: String

    @Published var nightscoutURL: String = ObservableUserDefaults.shared.url.value {
        willSet {
            if newValue != nightscoutURL {
                ObservableUserDefaults.shared.url.value = newValue
                triggerCheckStatus()
                if ObservableUserDefaults.shared.watchCommunicationEnabled.value {
                    PhoneSessionManager.shared.sendConfig()
                }
            }
        }
    }
    @Published var nightscoutToken: String = UserDefaultsRepository.token.value {
        willSet {
            if newValue != nightscoutToken {
                UserDefaultsRepository.token.value = newValue
                triggerCheckStatus()
                if ObservableUserDefaults.shared.watchCommunicationEnabled.value {
                    PhoneSessionManager.shared.sendConfig()
                }
            }
        }
    }
    @Published var nightscoutStatus: String = "Kontrollerar..."
    
    @Published var webSocketEnabled: Bool = Storage.shared.webSocketEnabled.value {
            didSet {
                Storage.shared.webSocketEnabled.value = webSocketEnabled
                if webSocketEnabled {
                    NightscoutSocketManager.shared.connectIfNeeded()
                } else {
                    NightscoutSocketManager.shared.disconnect()
                    triggerRefresh()
                }
            }
        }

        @Published var webSocketStatus: String = "⚫️ Frånkopplad"

        var webSocketStatusColor: Color {
            switch NightscoutSocketManager.shared.connectionState {
            case .authenticated: return .green
            case .connecting, .connected: return .orange
            case .disconnected: return .secondary
            case .error: return .red
            }
        }

    private var cancellables = Set<AnyCancellable>()
    private var checkStatusSubject = PassthroughSubject<Void, Never>()
    private var checkStatusWorkItem: DispatchWorkItem?

    init() {
        self.initialURL = ObservableUserDefaults.shared.url.value
        self.initialToken = UserDefaultsRepository.token.value

        setupDebounce()
        checkNightscoutStatus()
        observeWebSocketState()
    }

    private func setupDebounce() {
        checkStatusSubject
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.checkNightscoutStatus()
            }
            .store(in: &cancellables)
    }

    private func triggerCheckStatus() {
        checkStatusWorkItem?.cancel()

        nightscoutStatus = "Kontrollerar..."

        checkStatusWorkItem = DispatchWorkItem {
            self.checkStatusSubject.send()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: checkStatusWorkItem!)
    }

    func processURL(_ value: String) {
        var useTokenUrl = false

        if let urlComponents = URLComponents(string: value), let queryItems = urlComponents.queryItems {
            if let tokenItem = queryItems.first(where: { $0.name.lowercased() == "token" }) {
                let tokenPattern = "^[^-\\s]+-[0-9a-fA-F]{16}$"
                if let token = tokenItem.value, let _ = token.range(of: tokenPattern, options: .regularExpression) {
                    var baseComponents = urlComponents
                    baseComponents.queryItems = nil
                    if let baseURL = baseComponents.string {
                        nightscoutToken = token
                        nightscoutURL = baseURL
                        useTokenUrl = true
                    }
                }
            }
        }

        if !useTokenUrl {
            let filtered = value.replacingOccurrences(of: "[^A-Za-z0-9:/._-]", with: "", options: .regularExpression).lowercased()
            var cleanURL = filtered
            while cleanURL.count > 8 && cleanURL.last == "/" {
                cleanURL = String(cleanURL.dropLast())
            }
            nightscoutURL = cleanURL
        }
    }

    func checkNightscoutStatus() {
        NightscoutUtils.verifyURLAndToken { error, jwtToken, nsWriteAuth in
            DispatchQueue.main.async {
                ObservableUserDefaults.shared.nsWriteAuth.value = nsWriteAuth

                self.updateStatusLabel(error: error)
            }
        }
    }

    func updateStatusLabel(error: NightscoutUtils.NightscoutError?) {
        if let error = error {
            switch error {
            case .invalidURL:
                nightscoutStatus = "🔴 Felaktig URL"
            case .networkError:
                nightscoutStatus = "🔴 Nätverksfel"
            case .invalidToken:
                nightscoutStatus = "🔴 Felaktig token"
            case .tokenRequired:
                nightscoutStatus = "🟡 Token krävs"
            case .siteNotFound:
                nightscoutStatus = "🔴 Site hittades inte"
            case .unknown:
                nightscoutStatus = "🔴 Okänt fel"
            case .emptyAddress:
                nightscoutStatus = "🟡 Tom adress"
            }
            NightscoutSocketManager.shared.disconnect()
        } else {
            nightscoutStatus = "🟢 OK (Läsa\(ObservableUserDefaults.shared.nsWriteAuth.value ? " & Skriva" : ""))"

            if (nightscoutURL != initialURL || nightscoutToken != initialToken) {
                NotificationCenter.default.post(name: NSNotification.Name("refresh"), object: nil)
            }
        }
    }

    func dismiss() {
        delegate?.nightscoutSettingsDidFinish()
    }
    
    private func triggerRefresh() {
            NotificationCenter.default.post(name: NSNotification.Name("refresh"), object: nil)
        }

        private func observeWebSocketState() {
            updateWebSocketStatus()
            NotificationCenter.default.publisher(for: .nightscoutSocketStateChanged)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateWebSocketStatus()
                }
                .store(in: &cancellables)
        }

        private func updateWebSocketStatus() {
            switch NightscoutSocketManager.shared.connectionState {
            case .disconnected: webSocketStatus = "⚫️ Frånkopplad"
            case .connecting: webSocketStatus = "🟠 Ansluter..."
            case .connected: webSocketStatus = "🟠 Ansluten"
            case .authenticated: webSocketStatus = "🟢 Ansluten"
            case .error: webSocketStatus = "🔴 Fel"
            }
        }
}
