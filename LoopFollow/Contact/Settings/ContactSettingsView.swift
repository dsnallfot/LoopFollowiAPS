//
//  ContactSettingsView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-12-10.
//  Copyright © 2024 Jon Fawcett. All rights reserved.
//

import SwiftUI
import Contacts

@available(iOS 16.0, *)
struct ContactSettingsView: View {
    @ObservedObject var viewModel: ContactSettingsViewModel

    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            Form {
                Section(header: Text("Kontaktintegration")) {
                    Text("Lägg till kontakter som heter '\(viewModel.contactName)' till din Apple Watch för att visa aktuellt BG och andra värden i realtid. Se till att ge appen full access till dina kontakter på telefonen när du tillfrågas.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)

                    Toggle("Aktivera kontakter", isOn: $viewModel.contactEnabled)
                        .toggleStyle(SwitchToggleStyle())
                        .onChange(of: viewModel.contactEnabled) { isEnabled in
                            if isEnabled {
                                requestContactAccess()
                            }
                        }
                }
                .listRowBackground(Color(UIColor.systemGray).opacity(0.1))

                if viewModel.contactEnabled {
                    Section(header: Text("Extra information")) {
                        Toggle("Visa trend", isOn: $viewModel.contactTrend)
                            .toggleStyle(SwitchToggleStyle())
                            .onChange(of: viewModel.contactTrend) { isTrendEnabled in
                                if isTrendEnabled {
                                    viewModel.contactDelta = false
                                }
                            }

                        Toggle("Visa delta", isOn: $viewModel.contactDelta)
                            .toggleStyle(SwitchToggleStyle())
                            .onChange(of: viewModel.contactDelta) { isDeltaEnabled in
                                if isDeltaEnabled {
                                    viewModel.contactTrend = false
                                }
                            }

                        Toggle("Visa också 10m delta", isOn: $viewModel.contactFifteenMinutes)
                            .toggleStyle(SwitchToggleStyle())
                    }
                    .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
                }
            }
            // Let gradient show through the Form background
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func requestContactAccess() {
        let contactStore = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)

        if status == .authorized {
            // Already authorized, do nothing
        } else if status == .notDetermined {
            contactStore.requestAccess(for: .contacts) { granted, error in
                DispatchQueue.main.async {
                    if !granted {
                        viewModel.contactEnabled = false
                        showAlert(title: "Access Denied", message: "Please allow access to Contacts in Settings to enable this feature.")
                    }
                }
            }
        } else if status == .denied {
            viewModel.contactEnabled = false
            showAlert(title: "Access Denied", message: "Access to Contacts is denied. Please go to Settings and enable Contacts access.")
        } else if status == .restricted {
            viewModel.contactEnabled = false
            showAlert(title: "Access Restricted", message: "Access to Contacts is restricted.")
        } else {
            viewModel.contactEnabled = false
            showAlert(title: "Error", message: "An unknown error occurred while checking Contacts access.")
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
